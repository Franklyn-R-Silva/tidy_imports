// Dart imports:
import 'dart:io';

// Project imports:
import 'package:tidy_imports/config.dart';

/// Built-in group labels, in emission order, paired with their emoji.
const _groupLabels = <List<String>>[
  ['Dart', '🎯'],
  ['Flutter', '🐦'],
  ['Package', '📦'],
  ['Project', '🌎'],
  ['Test', '🧪'],
];

/// How many lines a single directive may span before the scanner gives up and
/// treats the opening line as ordinary source. A directive that never closes
/// means malformed input; without a bound the scanner would swallow the file.
const _maxDirectiveLines = 24;

/// Sort the imports of a dart file.
///
/// Returns [ImportSortData] containing the sorted file content and whether
/// any changes were made.
ImportSortData sortImports(
  List<String> lines,
  String packageName,
  bool emojis,
  bool exitIfChanged,
  bool noComments, {
  String? filePath,
  bool noBlankLines = false,
  List<CustomTier> customTiers = const [],
  bool groupProjectByFolder = false,
  bool testImports = false,
  List<String> testImportPrefixes = TidyConfig.defaultTestImportPrefixes,
  bool separateRelativeImports = false,
  bool sortExports = false,
  int groupProjectByFolderDepth = 0,
}) {
  // Asking for a folder depth is asking for folder grouping; requiring both
  // options only creates a way to set the depth and see nothing happen.
  final groupByFolder = groupProjectByFolder || groupProjectByFolderDepth > 0;

  String groupComment(String name, String emoji, String noun) =>
      '//${emojis ? ' $emoji ' : ' '}$name $noun:';

  String tierComment(CustomTier tier) =>
      '//${emojis ? ' 🧩 ' : ' '}${tier.name}';

  // Every header we have ever emitted, so a re-run strips it instead of
  // stacking a second one on top.
  final strippable = <String>{'// 📱 Flutter imports:'};
  for (final noun in const ['imports', 'exports']) {
    for (final label in _groupLabels) {
      strippable
        ..add('// ${label[0]} $noun:')
        ..add('// ${label[1]} ${label[0]} $noun:');
    }
  }
  for (final tier in customTiers) {
    strippable
      ..add('// ${tier.name}')
      ..add('// 🧩 ${tier.name}');
  }

  final beforeLines = <String>[];
  final afterLines = <String>[];

  final imports = _Buckets(customTiers);
  final exports = _Buckets(customTiers);

  bool startsDirective(String line) =>
      line.startsWith('import ') || (sortExports && line.startsWith('export '));

  // Whether a directive begins at [index], looking past any `// ignore:`
  // pragmas that belong to it. Decides whether a header line above is ours.
  bool directiveFollows(int index) {
    var i = index;
    while (i < lines.length && _isIgnorePragma(lines[i])) {
      i++;
    }
    return i < lines.length && startsDirective(lines[i]);
  }

  bool noDirectives() => imports.isEmpty && exports.isEmpty;

  void classify(_Directive directive, {required bool isExport}) {
    final bucket = isExport ? exports : imports;
    final uri = directive.uri;
    if (uri.startsWith('dart:')) {
      bucket.dart.add(directive);
    } else if (uri.startsWith('package:flutter/')) {
      bucket.flutter.add(directive);
    } else if (uri.startsWith('package:$packageName/')) {
      if (testImports && _isTestDouble(uri, testImportPrefixes)) {
        bucket.testDoublePackageForm.add(directive);
      } else {
        bucket.projectPackageForm.add(directive);
      }
    } else if (uri.startsWith('package:')) {
      final tier = _matchTier(directive.code, customTiers);
      if (tier != null) {
        bucket.tiers[tier]!.add(directive);
      } else {
        bucket.package.add(directive);
      }
    } else if (testImports && _isTestDouble(uri, testImportPrefixes)) {
      bucket.testDoubleRelative.add(directive);
    } else {
      bucket.projectRelative.add(directive);
    }
  }

  var isMultiLineString = false;
  var order = 0;
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];

    if (_timesContained(line, "'''") == 1 ||
        _timesContained(line, '"""') == 1) {
      isMultiLineString = !isMultiLineString;
    }

    if (!isMultiLineString) {
      // A header we wrote on an earlier run: drop it, the emitter re-adds it.
      if (strippable.contains(line) && directiveFollows(index + 1)) {
        index++;
        continue;
      }

      // `// ignore:` suppresses a lint on the line below it, so it is part of
      // the directive that follows — when one actually follows.
      var start = index;
      while (start < lines.length && _isIgnorePragma(lines[start])) {
        start++;
      }

      if (start < lines.length && startsDirective(lines[start])) {
        final span = _scanDirective(lines, start);
        if (span > 0) {
          final body = lines.sublist(start, start + span);
          final uri = _directiveUri(body.first);
          if (uri != null) {
            classify(
              _Directive(lines.sublist(index, start), body, uri, order++),
              isExport: body.first.startsWith('export '),
            );
            index = start + span;
            continue;
          }
        }
      }
    }

    (noDirectives() ? beforeLines : afterLines).add(line);
    index++;
  }

  if (noDirectives()) {
    var joinedLines = lines.join('\n');
    if (!joinedLines.endsWith('\n')) {
      joinedLines += '\n';
    }
    return ImportSortData(joinedLines, false);
  }

  if (beforeLines.isNotEmpty && beforeLines.last.trim().isEmpty) {
    beforeLines.removeLast();
  }

  final sortedLines = <String>[...beforeLines];
  if (beforeLines.isNotEmpty) {
    sortedLines.add('');
  }

  var hasPrevious = false;

  void addSeparator() {
    if (!noBlankLines && hasPrevious) sortedLines.add('');
  }

  void emit(List<_Directive> directives) {
    for (final directive in directives) {
      sortedLines
        ..addAll(directive.leading)
        ..addAll(directive.lines);
    }
  }

  void emitGroup(List<_Directive> directives, String comment) {
    if (directives.isEmpty) return;
    addSeparator();
    if (!noComments) sortedLines.add(comment);
    _sortByUri(directives);
    emit(directives);
    hasPrevious = true;
  }

  // Since Dart 3.13 `dart format` puts a blank line between the `package:` and
  // relative sections. Without one, the two tools undo each other on every run
  // (issue #1), so [separateRelativeImports] emits it up front. Never fires
  // when blank lines are switched off.
  bool separateBefore(
    List<_Directive> packageForm,
    List<_Directive> relative,
  ) =>
      separateRelativeImports &&
      !noBlankLines &&
      packageForm.isNotEmpty &&
      relative.isNotEmpty;

  // Emits one group split into a package-form and a relative-form half that
  // share a single header: the project group, and the test-double group that
  // mirrors it.
  void emitSplitGroup(
    List<_Directive> packageForm,
    List<_Directive> relative,
    String comment, {
    required bool byFolder,
  }) {
    if (packageForm.isEmpty && relative.isEmpty) return;
    addSeparator();
    if (!noComments) sortedLines.add(comment);
    _sortByUri(packageForm);
    _sortByUri(relative);
    if (byFolder && !noBlankLines) {
      // Folder grouping already breaks at the package-form/relative-form
      // boundary (a relative URI can never start with `package:`), so the two
      // features never stack up two blank lines.
      String? previousKey;
      for (final directive in [...packageForm, ...relative]) {
        final key = _folderKey(directive.uri, groupProjectByFolderDepth);
        if (previousKey != null && key != previousKey) sortedLines.add('');
        sortedLines
          ..addAll(directive.leading)
          ..addAll(directive.lines);
        previousKey = key;
      }
    } else {
      emit(packageForm);
      if (separateBefore(packageForm, relative)) sortedLines.add('');
      emit(relative);
    }
    hasPrevious = true;
  }

  void emitBlock(_Buckets bucket, String noun) {
    if (bucket.isEmpty) return;
    emitGroup(bucket.dart, groupComment('Dart', '🎯', noun));
    emitGroup(bucket.flutter, groupComment('Flutter', '🐦', noun));
    emitGroup(bucket.package, groupComment('Package', '📦', noun));
    for (final tier in customTiers) {
      emitGroup(bucket.tiers[tier]!, tierComment(tier));
    }
    emitSplitGroup(
      bucket.projectPackageForm,
      bucket.projectRelative,
      groupComment('Project', '🌎', noun),
      byFolder: groupByFolder,
    );
    emitSplitGroup(
      bucket.testDoublePackageForm,
      bucket.testDoubleRelative,
      groupComment('Test', '🧪', noun),
      byFolder: false,
    );
  }

  emitBlock(imports, 'imports');
  emitBlock(exports, 'exports');

  // Everything below the directive block, with the blank lines that separated
  // it from the directives dropped — the emitter re-adds exactly one.
  final trailing = <String>[];
  var addedCode = false;
  for (final line in afterLines) {
    if (line != '') {
      trailing.add(line);
      addedCode = true;
    } else if (addedCode) {
      trailing.add(line);
    }
  }

  // A barrel file ends on its last directive. Emitting the separator anyway
  // left a blank line below it, which `dart format` then strips right back
  // out — so the two tools undid each other on every run (issue #6).
  if (trailing.isNotEmpty) {
    sortedLines
      ..add('')
      ..addAll(trailing);
  }
  sortedLines.add('');

  final sortedFile = sortedLines.join('\n');
  final original = '${lines.join('\n')}\n';

  if (exitIfChanged && original != sortedFile) {
    if (filePath != null) {
      stdout
          .writeln('\n┗━━🚨 File $filePath does not have its imports sorted.');
    }
    exit(1);
  }

  if (original == sortedFile) {
    return ImportSortData(original, false);
  }

  return ImportSortData(sortedFile, true);
}

int _timesContained(String string, String looking) =>
    string.split(looking).length - 1;

/// Matches the quoted URI of a directive.
final _uriPattern = RegExp('''['"]([^'"]+)['"]''');

/// The URI of the directive opening on [firstLine], or null when the line
/// carries no quoted string — in which case it is not a directive after all.
String? _directiveUri(String firstLine) =>
    _uriPattern.firstMatch(firstLine)?.group(1);

/// Whether [line] is an `// ignore:` pragma, which suppresses a lint on the
/// line below it and therefore belongs to the directive that follows.
///
/// `// ignore_for_file:` is deliberately excluded: it applies to the whole
/// file and conventionally opens it, so gluing it to an import would drag it
/// down under a group header.
bool _isIgnorePragma(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('// ignore:') || trimmed.startsWith('//ignore:');
}

/// How many lines the directive starting at [start] spans, or 0 when it never
/// terminates — the caller then treats the line as ordinary source, which is
/// what happened to every multi-line directive before this scanner existed.
int _scanDirective(List<String> lines, int start) {
  final limit = start + _maxDirectiveLines;
  for (var i = start; i < lines.length && i < limit; i++) {
    if (_stripTrailingComment(lines[i]).endsWith(';')) {
      return i - start + 1;
    }
  }
  return 0;
}

/// [line] without its trailing `//` comment.
///
/// The scan tracks string literals, so neither a `//` inside a quoted URI nor
/// a `;` inside a comment can fool the terminator test in [_scanDirective].
String _stripTrailingComment(String line) {
  String? quote;
  var escaped = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (quote != null) {
      if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      continue;
    }
    if (char == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i).trimRight();
    }
  }
  return line.trimRight();
}

/// Sorts by URI, falling back to the original position so equal URIs keep
/// their relative order — [List.sort] is not stable.
void _sortByUri(List<_Directive> directives) {
  directives.sort((a, b) {
    final byUri = a.uri.compareTo(b.uri);
    return byUri != 0 ? byUri : a.order.compareTo(b.order);
  });
}

/// Whether [uri] points at a test double — a file whose name starts with one
/// of [prefixes] (e.g. `fake_client_repository.dart`).
///
/// Only ever called for project imports, so third-party packages whose name
/// happens to start with a prefix (`package:fake_async/fake_async.dart`,
/// `package:mock_web_server/mock_web_server.dart`) stay in the package group.
bool _isTestDouble(String uri, List<String> prefixes) {
  final fileName = uri.substring(uri.lastIndexOf('/') + 1);
  for (final prefix in prefixes) {
    if (fileName.startsWith(prefix)) return true;
  }
  return false;
}

/// The grouping key for [uri] under `--group-by-folder` (issue
/// import_sorter#69).
///
/// At [depth] 0 the whole directory is the key:
/// `package:app/a/b/foo.dart` -> `package:app/a/b`.
///
/// A [depth] above 0 counts segments *after* the package root, so depth 1 on
/// that URI yields `package:app/a`. Without the offset every project import
/// would share the single `package:app` key and grouping would do nothing.
String _folderKey(String uri, int depth) {
  final slash = uri.lastIndexOf('/');
  final dir = slash < 0 ? '' : uri.substring(0, slash);
  if (depth <= 0 || dir.isEmpty) return dir;
  final parts = dir.split('/');
  // `package:app/...` and root-absolute `/features/...` both spend their first
  // segment on the root itself, which is not a folder anyone groups by.
  final root =
      parts.first.startsWith('package:') || parts.first.isEmpty ? 1 : 0;
  return parts.take(root + depth).join('/');
}

/// Returns the first custom tier whose pattern matches [code], or null.
CustomTier? _matchTier(String code, List<CustomTier> tiers) {
  for (final tier in tiers) {
    if (code.contains(tier.pattern)) return tier;
  }
  return null;
}

/// One `import`/`export` directive, kept whole.
///
/// Sorting used to be line-based: a directive had to fit on a single line
/// ending in `;`. Anything else — a `show` clause wrapped by `dart format`, a
/// trailing `// comment`, a conditional `if (dart.library.…)` — failed that
/// test, fell through to the "not a directive" branch and was quietly dropped
/// out of the sorted block.
class _Directive {
  /// `// ignore:` lines glued directly above. They suppress a lint on the
  /// directive itself, so they travel with it; leaving them behind silently
  /// switches the suppression off.
  final List<String> leading;

  /// The directive's own source lines, trailing comment included.
  final List<String> lines;

  /// The quoted URI — the sort key, and what the group is decided from.
  /// Classifying by URI rather than by raw line text keeps a comment that
  /// mentions `dart:` from dragging a package import into the Dart group.
  final String uri;

  /// Original position, used only to break ties.
  final int order;

  const _Directive(this.leading, this.lines, this.uri, this.order);

  /// The directive's source without trailing comments — what custom tier
  /// patterns are matched against.
  String get code => lines.map(_stripTrailingComment).join(' ');
}

/// The groups one block of directives is split into.
class _Buckets {
  final dart = <_Directive>[];
  final flutter = <_Directive>[];
  final package = <_Directive>[];
  final projectPackageForm = <_Directive>[];
  final projectRelative = <_Directive>[];

  /// Test doubles (`fake_`/`mock_` files) split out of the project group when
  /// `testImports` is on. Mirrors the project group's package/relative split
  /// so both halves keep the same relative ordering.
  final testDoublePackageForm = <_Directive>[];
  final testDoubleRelative = <_Directive>[];

  /// One bucket per configured tier (issue import_sorter#81).
  final Map<CustomTier, List<_Directive>> tiers;

  _Buckets(List<CustomTier> customTiers)
      : tiers = {for (final tier in customTiers) tier: <_Directive>[]};

  bool get isEmpty =>
      dart.isEmpty &&
      flutter.isEmpty &&
      package.isEmpty &&
      projectPackageForm.isEmpty &&
      projectRelative.isEmpty &&
      testDoublePackageForm.isEmpty &&
      testDoubleRelative.isEmpty &&
      tiers.values.every((list) => list.isEmpty);
}

/// Result of a sort operation.
class ImportSortData {
  final String sortedFile;
  final bool updated;

  const ImportSortData(this.sortedFile, this.updated);
}
