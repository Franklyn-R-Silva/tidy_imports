// Package imports:
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/config.dart';

/// The lint rules whose verdict depends on how imports are written — the
/// ones this tool can agree with or fight.
const importLints = [
  'directives_ordering',
  'prefer_relative_imports',
  'always_use_package_imports',
];

/// The lint rules an analysis options file leaves switched on.
class LintState {
  /// Every enabled rule, mapped to where it was switched on: the options file
  /// itself, or the `include:` it came from. The source is what makes a
  /// finding actionable — "`directives_ordering` is on" sends the reader
  /// hunting through a file that never mentions it.
  final Map<String, String> enabled;

  /// What could not be read, as sentences: an include that does not resolve,
  /// a file that does not parse. Rules from there are unknown, not off.
  final List<String> problems;

  const LintState(this.enabled, [this.problems = const []]);

  /// Whether [rule] is on.
  bool has(String rule) => enabled.containsKey(rule);
}

/// Reads the lint rules in force for the options file at [optionsPath].
///
/// Follows `include:` — a string or, since Dart 3.6, a list — the way the
/// analyzer merges it: every included file first, in order, then the file's
/// own rules on top, so a later word wins. `linter: rules:` is either a list
/// (each entry switched on) or a map (`true` on, `false` off). A rule that
/// `analyzer: errors:` sets to `ignore` is off, whatever enabled it.
///
/// Pure: [read] returns a file's contents or null when it does not exist, and
/// [packageDir] returns the directory a `package:<name>/` URI starts in — the
/// package's `lib/` — or null when the package is not resolved. Paths are
/// written with `/`.
LintState readLints(
  String optionsPath, {
  required String? Function(String path) read,
  required String? Function(String package) packageDir,
}) {
  final enabled = <String, String>{};
  final ignored = <String>{};
  final problems = <String>[];
  final visiting = <String>{};

  void apply(String path, String label) {
    if (!visiting.add(path)) {
      problems.add('$label includes itself, directly or through another '
          'file. It is read once.');
      return;
    }

    final text = read(path);
    if (text == null) {
      problems.add('$label could not be read. Its rules are unknown here.');
      visiting.remove(path);
      return;
    }

    final Object? yaml;
    try {
      yaml = loadYaml(text);
    } on Object catch (error) {
      problems.add('$label is not valid YAML — '
          '${'$error'.split('\n').first.replaceFirst(RegExp('^Error on '), '')}'
          '. Its rules are unknown here.');
      visiting.remove(path);
      return;
    }
    if (yaml is! YamlMap) {
      visiting.remove(path);
      return;
    }

    final include = yaml['include'];
    final includes = include is String
        ? [include]
        : include is YamlList
            ? include.whereType<String>().toList()
            : const <String>[];
    for (final reference in includes) {
      final target =
          _resolveInclude(reference, from: path, packageDir: packageDir);
      if (target == null) {
        problems.add('`include: $reference` in $label does not resolve — run '
            '`dart pub get`, so the rules it brings can be read.');
        continue;
      }
      apply(target, reference);
    }

    final linter = yaml['linter'];
    final rules = linter is YamlMap ? linter['rules'] : null;
    if (rules is YamlList) {
      for (final rule in rules.whereType<String>()) {
        enabled[rule] = label;
      }
    } else if (rules is YamlMap) {
      for (final entry in rules.entries) {
        final rule = '${entry.key}';
        if (entry.value == false) {
          enabled.remove(rule);
        } else {
          enabled[rule] = label;
        }
      }
    }

    final analyzer = yaml['analyzer'];
    final errors = analyzer is YamlMap ? analyzer['errors'] : null;
    if (errors is YamlMap) {
      for (final entry in errors.entries) {
        final rule = '${entry.key}';
        if (entry.value == 'ignore') {
          ignored.add(rule);
        } else {
          ignored.remove(rule);
        }
      }
    }

    visiting.remove(path);
  }

  apply(_normalize(optionsPath), 'analysis_options.yaml');
  enabled.removeWhere((rule, _) => ignored.contains(rule));
  return LintState(enabled, problems);
}

/// The file an `include:` of [reference], written in [from], points at.
String? _resolveInclude(
  String reference, {
  required String from,
  required String? Function(String package) packageDir,
}) {
  if (reference.startsWith('package:')) {
    final slash = reference.indexOf('/');
    if (slash < 0) return null;
    final dir = packageDir(reference.substring('package:'.length, slash));
    if (dir == null) return null;
    return _normalize('$dir/${reference.substring(slash + 1)}');
  }
  if (reference.startsWith('/') || _drive.hasMatch(reference)) {
    return _normalize(reference);
  }
  final base = _normalize(from).split('/')..removeLast();
  return _normalize('${base.join('/')}/$reference');
}

final _drive = RegExp(r'^[A-Za-z]:[\\/]');

/// [path] with `\` written as `/`, and `.`, `..` and doubled slashes folded.
String _normalize(String path) {
  final posix = path.replaceAll('\\', '/');
  final out = <String>[];
  for (final segment in posix.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return '${posix.startsWith('/') ? '/' : ''}${out.join('/')}';
}

/// How much a [DoctorFinding] matters.
enum FindingKind {
  /// Two lints that cannot both be satisfied. Only the options file can fix
  /// it, so there is nothing to apply.
  conflict,

  /// The configuration makes every run write what a lint reports, or undo
  /// what the formatter writes. The two tools undo each other forever.
  fight,

  /// A lint is on and an option would satisfy it, but nothing fights: the
  /// tool leaves those lines alone rather than making them worse.
  suggestion,

  /// Worth knowing, nothing to change.
  note,
}

/// One thing `--doctor` has to say.
class DoctorFinding {
  final FindingKind kind;

  /// A finished sentence, ready to print.
  final String message;

  /// The configuration keys that settle it, with their values. Empty for a
  /// [FindingKind.conflict] or a [FindingKind.note].
  final Map<String, Object> fix;

  const DoctorFinding(this.kind, this.message, [this.fix = const {}]);
}

/// What [lints] and [config] have to say to each other.
///
/// [formatterSeparates] is whether the `dart format` in use writes a blank
/// line between the `package:` and relative imports on its own — 3.13 and
/// later do — which is what makes `separate_relative_imports: false` a fight
/// rather than a taste (issue #1).
///
/// This judges the configuration, which is what every future run reads, not
/// a flag typed for one run.
List<DoctorFinding> diagnose(
  LintState lints,
  TidyConfig config, {
  required bool formatterSeparates,
}) {
  final findings = <DoctorFinding>[];
  String rule(String name) => '`$name` (from ${lints.enabled[name]})';

  final wantsRelative = lints.has('prefer_relative_imports');
  final wantsPackage = lints.has('always_use_package_imports');

  if (wantsRelative && wantsPackage) {
    findings.add(DoctorFinding(
      FindingKind.conflict,
      '${rule('prefer_relative_imports')} and '
      '${rule('always_use_package_imports')} are both on, and they contradict '
      'each other: every import of your own package breaks one of them. Turn '
      'one off in analysis_options.yaml — tidy_imports follows either, with '
      '`relative_imports` or `package_imports`.',
    ));
  } else if (wantsRelative) {
    if (config.packageImports) {
      findings.add(DoctorFinding(
        FindingKind.fight,
        '${rule('prefer_relative_imports')} is on, but `package_imports` '
        'rewrites every relative import under lib/ as `package:` — each run '
        'writes the imports the lint reports.',
        const {'package_imports': false, 'relative_imports': true},
      ));
    } else if (!config.relativeImports) {
      // The opposite key is set too: a config asking for both reads as both
      // off, and writing only this one would leave the pair — and the
      // suggestion — exactly where they were.
      findings.add(DoctorFinding(
        FindingKind.suggestion,
        '${rule('prefer_relative_imports')} is on. `relative_imports` '
        'rewrites your own `package:` imports under lib/ into the relative '
        'form it asks for.',
        const {'relative_imports': true, 'package_imports': false},
      ));
    }
  } else if (wantsPackage) {
    if (config.relativeImports) {
      findings.add(DoctorFinding(
        FindingKind.fight,
        '${rule('always_use_package_imports')} is on, but `relative_imports` '
        'rewrites your own imports under lib/ as relative paths — each run '
        'writes the imports the lint reports.',
        const {'relative_imports': false, 'package_imports': true},
      ));
    } else if (!config.packageImports) {
      findings.add(DoctorFinding(
        FindingKind.suggestion,
        '${rule('always_use_package_imports')} is on. `package_imports` '
        'rewrites the relative imports under lib/ into the `package:` form it '
        'asks for.',
        const {'package_imports': true, 'relative_imports': false},
      ));
    }
  }

  final wantsOrdering = lints.has('directives_ordering');
  if (wantsOrdering) {
    if (!config.flat) {
      findings.add(DoctorFinding(
        FindingKind.fight,
        '${rule('directives_ordering')} wants one alphabetical run per '
        'section, and the grouped output breaks it: Flutter first and your own '
        'package last are both out of alphabetical order. `flat` writes the '
        'order the lint asks for, and `sort_exports` moves exports below the '
        'imports, where it wants them too.',
        {'flat': true, if (!config.sortExports) 'sort_exports': true},
      ));
    } else if (!config.sortExports) {
      findings.add(DoctorFinding(
        FindingKind.suggestion,
        '${rule('directives_ordering')} also wants every export after the '
        'imports. Under `flat` exports only move with `sort_exports`.',
        const {'sort_exports': true},
      ));
    }

    final shaping = [
      if (config.customTiers.isNotEmpty) '`tiers`',
      if (config.groupProjectByFolder || config.groupProjectByFolderDepth > 0)
        '`group_project_by_folder`',
      if (config.testImports) '`test_imports`',
    ];
    if (shaping.isNotEmpty) {
      findings.add(DoctorFinding(
        FindingKind.note,
        '${shaping.join(', ')} shape groups, and `flat` has none: '
        '${shaping.length == 1 ? 'it has' : 'they have'} no effect under it.',
      ));
    }
  }

  // Under `flat` the section breaks are written anyway, and without blank
  // lines there is nothing for the formatter to disagree with.
  if (formatterSeparates &&
      !config.separateRelativeImports &&
      !config.noBlankLines &&
      !config.flat &&
      !wantsOrdering) {
    findings.add(const DoctorFinding(
      FindingKind.fight,
      '`separate_relative_imports` is off, and `dart format` 3.13+ puts a '
      'blank line between the `package:` and relative imports by itself — the '
      'two tools undo each other on every run (issue #1).',
      {'separate_relative_imports': true},
    ));
  }

  // Worst first, keeping the order within a kind.
  return [
    for (final kind in FindingKind.values)
      ...findings.where((finding) => finding.kind == kind),
  ];
}

/// Every key the [findings] would set, merged in order. Only fights and
/// suggestions carry a fix.
Map<String, Object> fixesOf(List<DoctorFinding> findings) => {
      for (final finding in findings)
        if (finding.kind == FindingKind.fight ||
            finding.kind == FindingKind.suggestion)
          ...finding.fix,
    };
