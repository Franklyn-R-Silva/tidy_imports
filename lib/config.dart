// Dart imports:
import 'dart:io';

// Package imports:
import 'package:yaml/yaml.dart';

/// Every key the reader below understands.
///
/// Anything else in a config file is a typo, or an option from a version the
/// user is not running. Either way they meant something by it, and dropping it
/// without a word is how a config ends up describing a run that never happened.
/// **Adding an option means adding it here too** — the test
/// `every option the reader supports passes without a word` fails when the two
/// drift apart.
const _knownKeys = {
  'emojis',
  'comments',
  'blank_lines',
  'sort_pubspec',
  'group_project_by_folder',
  'group_project_by_folder_depth',
  'separate_relative_imports',
  'test_imports',
  'test_import_prefixes',
  'ignored_files',
  'report_roots',
  'tiers',
  'sort_exports',
  'remove_duplicates',
  'remove_unused',
  'flat',
  'relative_imports',
  'attach_comments',
};

/// The known key [name] was probably meant to be, or null when nothing is
/// close enough to guess.
///
/// Two edits is the ceiling: it catches the plausible slips (`sort_export`,
/// `ignored_file`, `emoji`) without turning an unrelated word into a confident
/// wrong suggestion, which reads as the tool misunderstanding the file.
String? _closestKey(String name) {
  String? closest;
  var best = 3;
  for (final key in _knownKeys) {
    final distance = _editDistance(name, key);
    if (distance < best) {
      best = distance;
      closest = key;
    }
  }
  return closest;
}

/// Levenshtein distance, two rows at a time.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (final i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      current[j + 1] = substitution < insertion
          ? (substitution < deletion ? substitution : deletion)
          : (insertion < deletion ? insertion : deletion);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  return previous[b.length];
}

/// A user-defined import tier that sits between generic `package:` imports
/// and project imports. See issue import_sorter#81.
class CustomTier {
  /// The comment label written above the group (without a leading `//`).
  final String name;

  /// Substring matched against an import line to assign it to this tier.
  /// For example `package:ptp_shared` groups all imports from that package.
  final String pattern;

  const CustomTier(this.name, this.pattern);
}

/// Resolved configuration for a tidy_imports run.
///
/// Configuration is read from `tidy_imports.yaml` at the project root if it
/// exists (issue import_sorter#67), otherwise from the `tidy_imports:` block
/// in `pubspec.yaml`. Command-line flags take precedence over both.
class TidyConfig {
  /// File-name prefixes treated as test doubles when [testImports] is on.
  static const defaultTestImportPrefixes = ['fake_', 'mock_'];

  final bool emojis;
  final bool noComments;
  final bool noBlankLines;
  final bool sortPubspec;
  final bool groupProjectByFolder;

  /// Whether a blank line separates the `package:<self>/…` and relative halves
  /// of the project group.
  ///
  /// **On by default**, and the only option here that is. It is not a matter of
  /// taste: since 3.13 `dart format` inserts that blank line itself, so with
  /// this off the two tools undo each other's work on every single run
  /// (issue #1). Under `blank_lines: false` it is suppressed anyway.
  final bool separateRelativeImports;
  final bool testImports;
  final List<String> testImportPrefixes;
  final List<String> ignoredFiles;
  final List<CustomTier> customTiers;

  /// Extra entry points for `--report`, as regular expressions matched against
  /// the project-relative path (`/lib/app/bootstrap.dart`). An entry point is
  /// unreferenced by definition, so anything the report cannot recognise on
  /// its own — a file run with `dart run lib/tool.dart`, a flavour main in a
  /// subfolder — is declared here rather than reported forever.
  final List<String> reportRoots;

  /// Whether `export` directives are sorted into their own block. Opt-in: on
  /// by default it would rewrite the barrel file of every existing project.
  final bool sortExports;

  /// Whether a directive written identically twice is folded into one.
  /// Opt-in: removing a line is not something a sorter should do uninvited.
  final bool removeDuplicates;

  /// Whether `dart fix --apply --code=unused_import` runs before sorting.
  /// Opt-in for the same reason, and because it costs an analyzer pass.
  final bool removeUnused;

  /// Whether the groups are dropped for one alphabetical run per section —
  /// the shape the `directives_ordering` lint expects. Opt-in: it throws away
  /// the group comments that are this tool's most recognisable output.
  final bool flat;

  /// Whether a `//` comment written directly above a directive moves with it.
  /// Opt-in: it changes where existing comments end up, and the note above the
  /// first directive is a file header in either case.
  final bool attachComments;

  /// Whether `package:<self>/…` imports are rewritten as relative paths,
  /// matching the `prefer_relative_imports` lint. Opt-in, and the opposite of
  /// what `always_use_package_imports` wants — the two lints disagree, so the
  /// choice has to be the user's.
  final bool relativeImports;

  /// How many folder segments — counted after the package root — the project
  /// group is broken up by. 0 keeps the whole path, which is the original
  /// behaviour of [groupProjectByFolder]. Any value above 0 also switches
  /// that grouping on, since setting a depth is asking for it.
  final int groupProjectByFolderDepth;

  /// Every problem found while reading the configuration, as a sentence ready
  /// to print.
  ///
  /// Configuration failures used to be invisible: a file in the wrong shape,
  /// or a key with a typo in it, was read, discarded and replaced by defaults
  /// without a word — the run looked successful and did the opposite of what
  /// the file said. These are what make that audible. `lib/` still prints
  /// nothing; `bin/` decides whether they are warnings or, under
  /// `--strict-config`, errors.
  final List<String> issues;

  const TidyConfig({
    required this.emojis,
    required this.noComments,
    required this.noBlankLines,
    required this.sortPubspec,
    required this.groupProjectByFolder,
    required this.ignoredFiles,
    required this.customTiers,
    this.separateRelativeImports = true,
    this.testImports = false,
    this.testImportPrefixes = defaultTestImportPrefixes,
    this.sortExports = false,
    this.groupProjectByFolderDepth = 0,
    this.removeDuplicates = false,
    this.removeUnused = false,
    this.flat = false,
    this.relativeImports = false,
    this.reportRoots = const [],
    this.attachComments = false,
    this.issues = const [],
  });

  /// Loads configuration, preferring `tidy_imports.yaml` over the
  /// `tidy_imports:` block in `pubspec.yaml`.
  ///
  /// A standalone file that does not parse — or cannot be read — is an issue
  /// like any other, not an exception. Everything else about a broken config
  /// is reported as a sentence and then survived; the one shape that threw
  /// instead was the loudest of them, a five-line YAML stack trace for a
  /// missing colon.
  factory TidyConfig.load(String currentPath, YamlMap pubspecYaml) {
    final standaloneFile = File('$currentPath/tidy_imports.yaml');
    if (standaloneFile.existsSync()) {
      final dynamic parsed;
      try {
        parsed = loadYaml(standaloneFile.readAsStringSync());
      } on Object catch (error) {
        return TidyConfig.fromYaml(null, [
          'tidy_imports.yaml '
              '${error is FileSystemException ? 'could not be read' : 'is not valid YAML'}'
              ' — ${_briefly(error)}. Using the defaults.',
        ]);
      }
      return TidyConfig.fromStandalone(parsed);
    }
    return TidyConfig.fromYaml(pubspecYaml['tidy_imports']);
  }

  /// Builds a config from the parsed contents of a standalone
  /// `tidy_imports.yaml`.
  ///
  /// The two config locations take the same options but not the same shape:
  /// in `pubspec.yaml` they live under a `tidy_imports:` key, which
  /// [TidyConfig.load] unwraps by reading that key; in a standalone file they
  /// are the document. Writing the pubspec shape in the standalone file is the
  /// easy mistake, and it used to be a silent one — every option ended up one
  /// level below where it was read, so the file parsed, configured nothing,
  /// and the run fell back to defaults without a word. The envelope is
  /// accepted here, and reported.
  factory TidyConfig.fromStandalone(dynamic yaml) {
    if (yaml is YamlMap &&
        yaml.length == 1 &&
        yaml['tidy_imports'] is YamlMap) {
      return TidyConfig.fromYaml(yaml['tidy_imports'], [
        'tidy_imports.yaml wraps its options in a `tidy_imports:` key. That '
            'shape belongs in pubspec.yaml — in a standalone file the options '
            'are the document. Reading them from inside the key; move them to '
            'the top level to silence this.',
      ]);
    }
    return TidyConfig.fromYaml(yaml);
  }

  /// Builds a config from a parsed YAML node, applying defaults for anything
  /// missing. A `null` node yields all defaults.
  ///
  /// [priorIssues] carries anything the caller already found about the file
  /// as a whole, so a single config produces a single list.
  factory TidyConfig.fromYaml(dynamic config, [List<String>? priorIssues]) {
    final issues = [...?priorIssues];

    if (config == null) {
      return TidyConfig(
        emojis: false,
        noComments: false,
        noBlankLines: false,
        sortPubspec: false,
        groupProjectByFolder: false,
        ignoredFiles: const [],
        customTiers: const [],
        issues: issues,
      );
    }

    if (config is! YamlMap) {
      issues.add(
        'the tidy_imports configuration is not a map of options — it reads as '
        '${config.runtimeType}. Ignoring it and using the defaults.',
      );
      return TidyConfig(
        emojis: false,
        noComments: false,
        noBlankLines: false,
        sortPubspec: false,
        groupProjectByFolder: false,
        ignoredFiles: const [],
        customTiers: const [],
        issues: issues,
      );
    }

    for (final key in config.keys) {
      final name = '$key';
      if (_knownKeys.contains(name)) continue;
      final closest = _closestKey(name);
      issues.add(
        closest == null
            ? 'unknown option `$name` in the tidy_imports configuration. It is '
                'being ignored.'
            : 'unknown option `$name` in the tidy_imports configuration. Did '
                'you mean `$closest`? It is being ignored.',
      );
    }

    final comments = _readBool(config, 'comments', issues);
    final blankLines = _readBool(config, 'blank_lines', issues);
    final testPrefixes = _readStrings(config, 'test_import_prefixes', issues);

    return TidyConfig(
      emojis: _readBool(config, 'emojis', issues) ?? false,
      noComments: comments == null ? false : !comments,
      noBlankLines: blankLines == null ? false : !blankLines,
      sortPubspec: _readBool(config, 'sort_pubspec', issues) ?? false,
      groupProjectByFolder:
          _readBool(config, 'group_project_by_folder', issues) ?? false,
      separateRelativeImports:
          _readBool(config, 'separate_relative_imports', issues) ?? true,
      testImports: _readBool(config, 'test_imports', issues) ?? false,
      testImportPrefixes:
          testPrefixes.isEmpty ? defaultTestImportPrefixes : testPrefixes,
      ignoredFiles: _readStrings(config, 'ignored_files', issues),
      customTiers: _readTiers(config, issues),
      sortExports: _readBool(config, 'sort_exports', issues) ?? false,
      removeDuplicates: _readBool(config, 'remove_duplicates', issues) ?? false,
      removeUnused: _readBool(config, 'remove_unused', issues) ?? false,
      flat: _readBool(config, 'flat', issues) ?? false,
      relativeImports: _readBool(config, 'relative_imports', issues) ?? false,
      attachComments: _readBool(config, 'attach_comments', issues) ?? false,
      reportRoots: _readStrings(config, 'report_roots', issues),
      groupProjectByFolderDepth:
          _readInt(config, 'group_project_by_folder_depth', issues) ?? 0,
      issues: issues,
    );
  }
}

/// [error] as one line.
///
/// `YamlException.toString()` opens with the line and column and then draws
/// the offending snippet over four more lines, which is a lot of shape for
/// something printed as a single sentence — but the position is the useful
/// half, so the first line is kept whole rather than reduced to `.message`.
String _briefly(Object error) {
  if (error is FileSystemException) {
    return error.osError?.message ?? error.message;
  }
  return '$error'.split('\n').first.replaceFirst(RegExp('^Error on '), '');
}

/// Reads [key] as a [T], recording an issue instead of throwing when the value
/// is something else.
///
/// The casts these replace threw a bare `TypeError` naming only the two types
/// — `type 'String' is not a subtype of type 'bool?' in type cast` — which is
/// the one thing the user could not act on: it never said which key.
T? _readTyped<T>(
  final YamlMap config,
  final String key,
  final String expected,
  final List<String> issues,
) {
  final value = config[key];
  if (value == null) return null;
  if (value is T) return value;
  issues.add(
    'option `$key` expects $expected, but the value is a '
    '${value.runtimeType}. Using the default.',
  );
  return null;
}

bool? _readBool(
  final YamlMap config,
  final String key,
  final List<String> issues,
) =>
    _readTyped<bool>(config, key, 'a boolean (true or false)', issues);

int? _readInt(
  final YamlMap config,
  final String key,
  final List<String> issues,
) =>
    _readTyped<int>(config, key, 'a whole number', issues);

/// Reads [key] as a list of strings, reporting both a value that is not a list
/// and an entry inside it that is not text. A bad entry costs its own line,
/// not the whole list.
List<String> _readStrings(
  final YamlMap config,
  final String key,
  final List<String> issues,
) {
  final value = _readTyped<YamlList>(config, key, 'a list', issues);
  if (value == null) return const [];

  final strings = <String>[];
  for (final entry in value) {
    if (entry is String) {
      strings.add(entry);
      continue;
    }
    issues.add(
      'option `$key` expects a list of text, but one entry is a '
      '${entry.runtimeType}. Skipping that entry.',
    );
  }
  return strings;
}

/// Reads the `tiers` list, where each entry needs a `name` and a `pattern`.
///
/// An entry missing either used to be dropped in silence, which is the same
/// failure as the rest of this file: the tier the user wrote simply never
/// existed at runtime, and nothing said so.
List<CustomTier> _readTiers(final YamlMap config, final List<String> issues) {
  final value = _readTyped<YamlList>(
    config,
    'tiers',
    'a list of entries with `name` and `pattern`',
    issues,
  );
  if (value == null) return const [];

  final tiers = <CustomTier>[];
  for (final entry in value) {
    if (entry is! YamlMap) {
      issues.add(
        'each `tiers` entry needs `name` and `pattern`, but one entry is a '
        '${entry.runtimeType}. Skipping that entry.',
      );
      continue;
    }
    final name = entry['name'];
    final pattern = entry['pattern'];
    if (name is String && pattern is String) {
      tiers.add(CustomTier(name, pattern));
      continue;
    }
    issues.add(
      'each `tiers` entry needs `name` and `pattern`, both text. Skipping the '
      'entry ${name is String ? 'named `$name`' : 'at position '
          '${value.indexOf(entry) + 1}'}.',
    );
  }
  return tiers;
}
