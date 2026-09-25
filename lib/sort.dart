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
/// treats the opening line as ordinary source.
///
/// The bound exists only so malformed input cannot swallow a file. It has to
/// sit far above anything `dart format` writes: since Dart 3.7 the tall style
/// puts every `show`/`hide` name on its own line, so a barrel re-exporting 23
/// symbols is already 25 lines — the old bound of 24 silently dropped it.
const _maxDirectiveLines = 512;

/// Sort the imports of a dart file.
///
/// Returns [ImportSortData] containing the sorted file content and whether
/// any changes were made. Pure: it reads nothing, writes nothing, and never
/// terminates the process — what an unsorted file means is the caller's call.
///
/// [removeDuplicates] drops a directive that repeats one already kept, keeping
/// the first occurrence. It compares text, not meaning, so it only ever folds
/// away a directive written identically twice — the shape a merge or a
/// double auto-import produces. Removing an import that is merely *unused*
/// is a different question, one that needs a resolved element model;
/// `dart fix --apply --code=unused_import` answers it, and the CLI's
/// `--remove-unused` runs exactly that before sorting.
///
/// [flat] drops the groups entirely and emits one alphabetical run per
/// section — `dart:`, then `package:`, then relative — which is the order the
/// `directives_ordering` lint expects. Grouping options are ignored under it,
/// since there are no groups left to shape (import_sorter#58, #28).
///
/// [attachComments] keeps a `//` comment written directly above a directive
/// with that directive. Off by default: without it such a comment is not part
/// of the directive, so once the block has been rebuilt it ends up below the
/// sorted imports, explaining whatever now follows it. A comment above the
/// *first* directive is the file's own header either way and stays on top.
///
/// [relativeImports] rewrites `package:<packageName>/…` URIs as paths relative
/// to [libRelativePath], the file's own location under `lib/`. Without that
/// path there is nothing to be relative *to*, so the rewrite is skipped — as
/// it is for files outside `lib/`, which cannot reach it with a relative URI
/// at all (import_sorter#59).
///
/// [packageImports] is the other direction, for `always_use_package_imports`:
/// a relative URI that stays inside `lib/` becomes `package:<packageName>/…`.
/// One that climbs out of `lib/`, is root-relative (`/x.dart`) or carries a
/// scheme is left as written. The two are opposites, so asking for both is an
/// [ArgumentError].
ImportSortData sortImports(
  List<String> lines,
  String packageName,
  bool emojis,
  @Deprecated(
    'Has no effect since 1.4.2: lib/ no longer calls exit(). bin/ checks the '
    'whole project and fails once, so every unsorted file gets reported '
    '(import_sorter#87). Kept through 2.0.0 so the upgrade is one change, not '
    'two; removed in 3.0.0.',
  )
  bool exitIfChanged,
  bool noComments, {
  @Deprecated(
    'Has no effect since 1.4.2; it only ever fed the message the removed '
    'exit() printed. Kept through 2.0.0; removed in 3.0.0.',
  )
  String? filePath,
  bool noBlankLines = false,
  List<CustomTier> customTiers = const [],
  bool groupProjectByFolder = false,
  bool testImports = false,
  List<String> testImportPrefixes = TidyConfig.defaultTestImportPrefixes,
  bool separateRelativeImports = false,
  bool sortExports = false,
  int groupProjectByFolderDepth = 0,
  bool removeDuplicates = false,
  bool flat = false,
  bool relativeImports = false,
  bool packageImports = false,
  String? libRelativePath,
  bool attachComments = false,
}) {
  if (relativeImports && packageImports) {
    throw ArgumentError(
      'relativeImports and packageImports rewrite in opposite directions; '
      'pass at most one of them.',
    );
  }

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

  // Under [flat] there are no groups, so the buckets stay empty and everything
  // lands in one run per directive kind.
  final flatImports = <_Directive>[];
  final flatExports = <_Directive>[];

  bool startsDirective(String line) =>
      _opensImport.hasMatch(line) ||
      (sortExports && _opensExport.hasMatch(line));

  // Whether a directive begins at [index], looking past the comment lines
  // that belong to it. Decides whether a header line above is ours — and a
  // header followed by a note about the import below it is still ours.
  //
  // The lookahead deliberately ignores [attachComments]. A plain `//` comment
  // sitting between one of our own headers and a directive is a shape only a
  // previous `attachComments: true` run writes, so refusing to look past it
  // when the option is off cost that block its header: the old one stayed
  // behind as body text, a second copy was regenerated above the import, and
  // the comment was orphaned under the duplicate. The next run read that as
  // already sorted, so the file never healed — switching the option off once
  // corrupted the block permanently.
  bool directiveFollows(int index) {
    var i = index;
    while (i < lines.length &&
        (_isIgnorePragma(lines[i]) || _isAttachedComment(lines[i]))) {
      i++;
    }
    return i < lines.length && startsDirective(lines[i]);
  }

  bool noDirectives() =>
      imports.isEmpty &&
      exports.isEmpty &&
      flatImports.isEmpty &&
      flatExports.isEmpty;

  void classify(_Directive directive, {required bool isExport}) {
    if (flat) {
      (isExport ? flatExports : flatImports).add(directive);
      return;
    }
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

  // `package:<self>/…` and a path relative to this file name the same library,
  // and the two lints disagree on which to write: [relativeImports] turns the
  // first into the second, [packageImports] the second into the first. Left
  // alone when both are off, when the file's own location is unknown, or when
  // the URI points anywhere else — another package's `package:` URI has no
  // relative form from here, and a relative one that leaves `lib/` has no
  // `package:` form.
  //
  // Every URI of the directive is rewritten, wherever its line breaks. This
  // used to replace the first URI on the first line only: an `import` whose
  // URI sat on the next line kept its text but took the new URI as its sort
  // key, so a `package:` import was filed among the relative ones; and a
  // conditional import came out half-rewritten.
  _Directive rewrite(_Directive directive) {
    final from = libRelativePath;
    if (from == null) return directive;

    final prefix = 'package:$packageName/';
    if (relativeImports) {
      return _rewriteUris(
        directive,
        (uri) => uri.startsWith(prefix)
            ? _relativePath(from, uri.substring(prefix.length))
            : null,
      );
    }
    if (packageImports) {
      return _rewriteUris(directive, (uri) {
        final path = _resolveInLib(from, uri);
        return path == null ? null : '$prefix$path';
      });
    }
    return directive;
  }

  // Signatures of the directives kept so far, for [removeDuplicates].
  final seen = <String>{};
  var duplicatesRemoved = 0;

  final scanner = _SourceScanner();
  var order = 0;
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];

    // Only a line that *begins* in executable code can be a directive or a
    // header of ours. Inside a string literal or a `/* */` block it is text,
    // and moving it would change what the file means.
    if (scanner.startsInCode) {
      // A header we wrote on an earlier run: drop it, the emitter re-adds it.
      if (strippable.contains(line) && directiveFollows(index + 1)) {
        scanner.consume(line);
        index++;
        continue;
      }

      // A comment written directly above a directive explains it, so it moves
      // with it. `// ignore:` has to, or the suppression is switched off; a
      // plain note has to as well, or it ends up below the sorted block,
      // explaining whatever now follows it.
      //
      // Only once the block has started: a comment above the *first* directive
      // is the file's own header — a licence, a `// Dart imports:` of ours —
      // and belongs at the top, where it was.
      // A comment above the *first* directive is the file's own header — a
      // licence, a `// Dart imports:` of ours — so it is never attached.
      final attaching = attachComments && !noDirectives();
      var start = index;
      while (start < lines.length &&
          (_isIgnorePragma(lines[start]) ||
              (attaching && _isAttachedComment(lines[start])))) {
        start++;
      }

      if (start < lines.length && startsDirective(lines[start])) {
        final span = _scanDirective(lines, start);
        if (span > 0) {
          final body = lines.sublist(start, start + span);
          // The first URI anywhere in the body, not on the first line only:
          // `import` followed by the URI on the next line is legal Dart.
          final uri = _directiveTargets(body).firstOrNull;
          if (uri != null) {
            // Rewrite first: a `package:` URI and its relative form are the
            // same import, and only look like duplicates once both are
            // written the same way.
            final directive = rewrite(
              _Directive(lines.sublist(index, start), body, uri, order++),
            );
            if (removeDuplicates && !seen.add(directive.signature)) {
              duplicatesRemoved++;
            } else {
              classify(directive, isExport: _opensExport.hasMatch(body.first));
            }
            // A directive can carry a `/*` or a string of its own, so the
            // scanner has to walk the lines the loop skips over.
            for (var i = index; i < start + span; i++) {
              scanner.consume(lines[i]);
            }
            index = start + span;
            continue;
          }
        }
      }
    }

    (noDirectives() ? beforeLines : afterLines).add(line);
    scanner.consume(line);
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

  // One run per section, with a blank line where the section changes — which
  // is exactly where `dart format` 3.13+ puts one. Emitting none left the
  // formatter adding all three and the next run taking them away again, so
  // `--flat` fought the formatter on every single run (issue #1, in the one
  // mode that had no separator at all). `--no-blank-lines` still gives the
  // tight run: the lint reads order, not spacing.
  void emitBySection(List<_Directive> directives) {
    int? previous;
    for (final directive in directives) {
      final section = _section(directive.uri);
      if (previous != null && section != previous && !noBlankLines) {
        sortedLines.add('');
      }
      sortedLines
        ..addAll(directive.leading)
        ..addAll(directive.lines);
      previous = section;
    }
  }

  if (flat) {
    // `directives_ordering` wants one alphabetical run per section, exports
    // in their own block below the imports. No headers: a comment between two
    // runs the lint considers one section would be a lie about the structure.
    _sortFlatly(flatImports);
    _sortFlatly(flatExports);
    emitBySection(flatImports);
    if (flatImports.isNotEmpty && flatExports.isNotEmpty && !noBlankLines) {
      sortedLines.add('');
    }
    emitBySection(flatExports);
  } else {
    emitBlock(imports, 'imports');
    emitBlock(exports, 'exports');
  }

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

  if (original == sortedFile) {
    return ImportSortData(original, false);
  }

  return ImportSortData(sortedFile, true, duplicatesRemoved: duplicatesRemoved);
}

/// Every `import`, `export` and `part` URI in [lines], in source order.
///
/// Shares the sorter's scanner, so a directive inside a `/* */` block or a
/// string literal is text here too — the import graph should not grow an edge
/// from code that was commented out.
///
/// `part` counts: a part file is never imported, only parted, and leaving the
/// directive out would make every generated `.g.dart` look unreferenced.
List<String> directiveUris(List<String> lines) {
  final uris = <String>[];
  final scanner = _SourceScanner();

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (scanner.startsInCode) {
      var start = index;
      while (start < lines.length && _isIgnorePragma(lines[start])) {
        start++;
      }
      if (start < lines.length && _opensDirective(lines[start])) {
        final span = _scanDirective(lines, start);
        if (span > 0) {
          final targets = _directiveTargets(lines.sublist(start, start + span));
          if (targets.isNotEmpty) {
            uris.addAll(targets);
            for (var i = index; i < start + span; i++) {
              scanner.consume(lines[i]);
            }
            index = start + span;
            continue;
          }
        }
      }
    }
    scanner.consume(line);
    index++;
  }
  return uris;
}

/// Whether [lines] declare a top-level `main` — the mark of an entry point.
///
/// Matched at column 0 on lines that begin in executable code, so a `main(`
/// inside a comment, a string, or a class body does not count. `void main()`,
/// `Future<void> main() async`, `dynamic main(List<String> args)` and a bare
/// `main()` all do.
bool declaresMain(List<String> lines) {
  final scanner = _SourceScanner();
  for (final line in lines) {
    if (scanner.startsInCode && _mainDeclaration.hasMatch(line)) return true;
    scanner.consume(line);
  }
  return false;
}

final _mainDeclaration = RegExp(
  r'^(?:(?:Future<[^>]*>|FutureOr<[^>]*>|void|dynamic)\s+)?main\s*\(',
);

/// Matches the quoted URI of a directive.
final _uriPattern = RegExp('''['"]([^'"]+)['"]''');

/// Whether a line opens an `import` / an `export`.
///
/// The keyword may *end* the line — `import` with its URI on the next one is
/// legal Dart, and [_directiveTargets] reads the URI from anywhere in the body
/// precisely so that shape works — so it is matched up to whitespace or end of
/// line. `startsWith('import ')` missed it, and the directive slid out of the
/// sorted block: the failure the multi-line scanner exists to prevent.
final _opensImport = RegExp(r'^import(?:\s|$)');
final _opensExport = RegExp(r'^export(?:\s|$)');

/// Whether [line] is a comment that belongs to the directive below it.
bool _isAttachedComment(String line) {
  final trimmed = line.trimLeft();
  // A doc comment documents a declaration, never a directive, so it is left
  // where it is rather than dragged into the block.
  return trimmed.startsWith('//') && !trimmed.startsWith('///');
}

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
    // A directive never contains the start of another one. Meeting one means
    // the first never terminated, and it is better to give that one up than
    // to swallow the second into it.
    if (i > start && _startsDirectiveKeyword(lines[i])) return 0;
    if (_stripTrailingComment(lines[i]).endsWith(';')) {
      return i - start + 1;
    }
  }
  return 0;
}

/// Whether [line] opens any directive kind, `part of` and `library` included.
///
/// The keyword may end the line — `import` with its URI on the next line is
/// legal Dart — so it is matched up to whitespace or end of line, not up to a
/// trailing space.
bool _startsDirectiveKeyword(String line) => _anyDirective.hasMatch(line);

final _anyDirective = RegExp(r'^(?:import|export|part|library)(?:\s|$)');

/// Whether [line] opens an `import`, `export` or `part` directive — the kinds
/// that name another file. `part of` points the other way and is excluded.
bool _opensDirective(String line) =>
    _fileDirective.hasMatch(line) && !line.startsWith('part of');

final _fileDirective = RegExp(r'^(?:import|export|part)(?:\s|$)');

/// Every URI a directive [body] names, in source order.
///
/// That is the default one plus each `if (dart.library.x) 'uri'` target of a
/// conditional import or export. `show`, `hide`, `as` and `deferred` take bare
/// identifiers, so every quoted string in a directive is a URI — once trailing
/// comments are stripped, so a `// see 'other.dart'` is not read as one.
List<String> _directiveTargets(List<String> body) => [
      for (final line in body)
        for (final match in _uriPattern.allMatches(_stripTrailingComment(line)))
          match.group(1)!,
    ];

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

/// Sorts the way `directives_ordering` reads a file: `dart:` first, then
/// `package:`, then relative, alphabetical inside each.
void _sortFlatly(List<_Directive> directives) {
  directives.sort((a, b) {
    final bySection = _section(a.uri).compareTo(_section(b.uri));
    if (bySection != 0) return bySection;
    final byUri = a.uri.compareTo(b.uri);
    return byUri != 0 ? byUri : a.order.compareTo(b.order);
  });
}

/// Which of the lint's three sections [uri] belongs to. `package:flutter/` is
/// deliberately not special here — singling it out is exactly what makes the
/// grouped output violate the lint.
int _section(String uri) {
  if (uri.startsWith('dart:')) return 0;
  if (uri.startsWith('package:')) return 1;
  return 2;
}

/// The path from the directory holding [from] to [to], both written with `/`
/// and relative to `lib/`. Null when there is nothing left to point at.
///
/// `src/p2/bar.dart` importing `src/foo.dart` gets `../foo.dart`;
/// `src/foo.dart` importing `src/p1/foo.dart` gets `p1/foo.dart`.
String? _relativePath(String from, String to) {
  final fromDir = from.split('/')..removeLast();
  final toParts = to.split('/');

  var common = 0;
  while (common < fromDir.length &&
      common < toParts.length - 1 &&
      fromDir[common] == toParts[common]) {
    common++;
  }

  final parts = [
    ...List.filled(fromDir.length - common, '..'),
    ...toParts.sublist(common),
  ];
  return parts.isEmpty ? null : parts.join('/');
}

/// The path, relative to `lib/`, that the relative [uri] written in [from]
/// points at — or null when [uri] is not a relative path to a Dart file that
/// stays inside `lib/`.
///
/// A scheme (`dart:`, `package:`, `http:`) or a leading `/` means the URI is
/// not relative to [from] at all. Only `.dart` targets count: a conditional
/// import's `== 'true'` value is quoted too, and is not a path.
String? _resolveInLib(String from, String uri) {
  if (!uri.endsWith('.dart') || uri.startsWith('/') || _scheme.hasMatch(uri)) {
    return null;
  }

  final parts = from.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

/// [directive] with each of its URIs passed through [rewrite], which returns
/// the replacement or null to keep the URI as written.
///
/// Every quoted URI in the directive's code is a candidate — the default one
/// and each conditional target, on whichever line it sits — and nothing in a
/// trailing comment is. The rest of each line is kept byte for byte, so a
/// prefix, a `show` clause or a comment survives the rewrite.
_Directive _rewriteUris(
  _Directive directive,
  String? Function(String uri) rewrite,
) {
  var changed = false;
  final lines = [
    for (final line in directive.lines)
      () {
        // The trailing comment is cut off the end, so every index into the
        // code is an index into the line as well.
        final code = _stripTrailingComment(line);
        final out = StringBuffer();
        var last = 0;
        for (final match in _uriPattern.allMatches(code)) {
          final replacement = rewrite(match.group(1)!);
          if (replacement == null) continue;
          changed = true;
          out
            ..write(line.substring(last, match.start + 1))
            ..write(replacement);
          last = match.end - 1;
        }
        return (out..write(line.substring(last))).toString();
      }(),
  ];
  if (!changed) return directive;

  return _Directive(
    directive.leading,
    lines,
    rewrite(directive.uri) ?? directive.uri,
    directive.order,
  );
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

/// Tracks, line by line, whether the source has left executable code.
///
/// A line is only a directive — or a group header of ours — when it *begins*
/// in code. Anything inside a string literal or a `/* */` block is text, and
/// hoisting it out of there rewrites what the file means: a commented-out
/// import used to come back to life, and a group comment inside a string used
/// to be stripped.
///
/// Known limit: a quote nested inside a `${...}` interpolation can end the
/// string early here. It costs nothing unless that line also opens a block
/// comment that never closes, and it is strictly less wrong than the single
/// toggle this replaced.
class _SourceScanner {
  /// Delimiter of a triple-quoted string an earlier line left open.
  String? _openString;

  /// Nesting depth of `/* … */`. Dart block comments nest, so a plain
  /// "look for the next `*/`" closes one level too early.
  int _commentDepth = 0;

  /// Whether the next line to be consumed begins in executable code.
  bool get startsInCode => _openString == null && _commentDepth == 0;

  /// Advances the state past [line].
  void consume(String line) {
    var i = 0;
    while (i < line.length) {
      final open = _openString;
      if (open != null) {
        final end = line.indexOf(open, i);
        if (end < 0) return; // The string runs on into the next line.
        i = end + open.length;
        _openString = null;
        continue;
      }

      if (_commentDepth > 0) {
        final close = line.indexOf('*/', i);
        final nested = line.indexOf('/*', i);
        if (nested >= 0 && (close < 0 || nested < close)) {
          _commentDepth++;
          i = nested + 2;
          continue;
        }
        if (close < 0) return; // The comment runs on into the next line.
        _commentDepth--;
        i = close + 2;
        continue;
      }

      final char = line[i];
      if (char == '/' && i + 1 < line.length) {
        final next = line[i + 1];
        if (next == '/') return; // Rest of the line is a comment.
        if (next == '*') {
          _commentDepth++;
          i += 2;
          continue;
        }
      }

      if (char == "'" || char == '"') {
        final triple = char * 3;
        if (line.startsWith(triple, i)) {
          _openString = triple;
          i += 3;
          continue;
        }
        i = _skipString(line, i, char, raw: _isRawPrefix(line, i));
        continue;
      }

      i++;
    }
  }
}

/// Whether the quote at [quoteIndex] is preceded by the `r` of a raw string,
/// rather than by an identifier that merely ends in `r`.
bool _isRawPrefix(String line, int quoteIndex) {
  if (quoteIndex == 0 || line[quoteIndex - 1] != 'r') return false;
  if (quoteIndex == 1) return true;
  final before = line[quoteIndex - 2];
  return !RegExp(r'[A-Za-z0-9_$]').hasMatch(before);
}

/// The index just past the single-line string opening at [start], or the end
/// of the line when it never closes — which only happens in malformed source.
int _skipString(String line, int start, String quote, {required bool raw}) {
  var i = start + 1;
  while (i < line.length) {
    final char = line[i];
    // A backslash escapes the next character, except in a raw string, where
    // it is just a backslash.
    if (!raw && char == r'\') {
      i += 2;
      continue;
    }
    if (char == quote) return i + 1;
    i++;
  }
  return i;
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

  /// Identity for duplicate detection: the whole directive, `// ignore:` lines
  /// included, with runs of whitespace collapsed.
  ///
  /// Collapsing whitespace makes a directive `dart format` wrapped over two
  /// lines match the same one written on a single line. Trailing comments are
  /// deliberately *kept*: two imports of the same library whose comments differ
  /// are not folded together, because dropping one would drop what it says.
  /// Deciding that a differently-written import is redundant needs a resolved
  /// element model — that is `dart fix`'s job, not this one's.
  String get signature =>
      [...leading, ...lines].join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
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

  /// How many directives `removeDuplicates` dropped. Always 0 when the option
  /// is off, so a caller can report it without checking the flag.
  final int duplicatesRemoved;

  const ImportSortData(
    this.sortedFile,
    this.updated, {
    this.duplicatesRemoved = 0,
  });
}
