// tidy_imports by example — every option, in one run.
//
// From the command line, in any Dart or Flutter project:
//
//   dart run tidy_imports                # sort the project
//   dart run tidy_imports --dry-run      # preview, write nothing
//   dart run tidy_imports --report       # the import graph: cycles, dead files
//   dart run tidy_imports --help         # every option, with its default
//
// Each option below is also a key in `tidy_imports.yaml` (or in the
// `tidy_imports:` block of pubspec.yaml), and each flag is negatable —
// `--no-emojis` overrides `emojis: true` for a single run.
//
// This file tours the library API the CLI is built on. Every function here is
// pure: it takes values and returns values, reads no file, writes no file and
// never exits. That is the whole reason the tour can run as one program.
//
//   dart run example/example.dart

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:tidy_imports/tidy_imports.dart';
import 'package:yaml/yaml.dart';

void main() {
  stdout.writeln('$packageName $packageVersion — every option, one run');

  _sorting();
  _pubspec();
  _graph();
  _paths();
  _configuration();

  stdout.writeln(
    '\nOne option is deliberately not here: `--remove-unused`. Whether an '
    'import is\nunused needs a resolved element model, not text, so the CLI '
    'hands that one to\nthe SDK (`dart fix --code=unused_import`) before it '
    'starts sorting.',
  );
}

// ---------------------------------------------------------------------------
// sortImports: the twelve ways to shape a block of directives
// ---------------------------------------------------------------------------

void _sorting() {
  _heading('sortImports');

  _demo(
    'The default: grouped by origin, alphabetical inside each group',
    [
      "import 'package:flutter/material.dart';",
      "import 'dart:async';",
      "import 'package:provider/provider.dart';",
      "import 'package:my_app/home.dart';",
      "import 'dart:io';",
      '',
      'void main() {}',
    ],
  );

  _demo(
    '--emojis: the same groups, each with an icon',
    [
      "import 'package:my_app/home.dart';",
      "import 'dart:io';",
      '',
      'void main() {}',
    ],
    emojis: true,
  );

  _demo(
    '--no-comments --no-blank-lines: the order without the furniture',
    [
      "import 'package:my_app/home.dart';",
      "import 'package:http/http.dart';",
      "import 'dart:io';",
      '',
      'void main() {}',
    ],
    noComments: true,
    noBlankLines: true,
  );

  _demo(
    '--flat: one run per section — the shape `directives_ordering` wants',
    [
      "import 'package:flutter/material.dart';",
      "import 'package:my_app/home.dart';",
      "import 'dart:io';",
      "import 'package:http/http.dart';",
      '',
      'void main() {}',
    ],
    flat: true,
    note: 'package:flutter/ is not singled out here. Doing that is precisely '
        'what makes the grouped output trip the lint.',
  );

  _demo(
    'Custom tiers: your own packages, between package and project',
    [
      "import 'package:acme_shared/utils.dart';",
      "import 'package:provider/provider.dart';",
      "import 'package:my_app/home.dart';",
      '',
      'void main() {}',
    ],
    customTiers: const [CustomTier('Shared imports:', 'package:acme_shared')],
  );

  _demo(
    '--group-by-folder-depth=1: project imports split by top folder',
    [
      "import 'package:my_app/features/cart/cart.dart';",
      "import 'package:my_app/core/theme.dart';",
      "import 'package:my_app/features/home/home.dart';",
      "import 'package:my_app/core/router.dart';",
      '',
      'void main() {}',
    ],
    groupProjectByFolderDepth: 1,
    note: 'Setting a depth switches the grouping on by itself — requiring both '
        'options would only create a way to set a depth and see nothing '
        'happen.',
  );

  _demo(
    '--separate-relative-imports: the blank line `dart format` 3.13+ writes',
    [
      "import 'package:my_app/home.dart';",
      "import 'widgets/button.dart';",
      "import 'package:my_app/api.dart';",
      '',
      'void main() {}',
    ],
    separateRelativeImports: true,
    note: 'This is the one option that ships ON. Without it the formatter adds '
        'that line and the sorter takes it away, once per run, forever.',
  );

  _demo(
    '--sort-exports: exports get their own block, after the imports',
    [
      "export 'package:my_app/models.dart';",
      "import 'dart:convert';",
      "export 'package:my_app/api.dart';",
      '',
      'void main() {}',
    ],
    sortExports: true,
  );

  _demo(
    '--remove-duplicates: an identical line folds, an aliased one does not',
    [
      "import 'dart:math';",
      "import 'package:http/http.dart';",
      "import 'dart:math';",
      "import 'package:http/http.dart' as http;",
      '',
      'void main() {}',
    ],
    removeDuplicates: true,
  );

  _demo(
    '--test-imports: test doubles last, and only the project ones',
    [
      "import 'package:my_app/repo.dart';",
      "import 'stub_repo.dart';",
      "import 'package:mockito/mockito.dart';",
      '',
      'void main() {}',
    ],
    testImports: true,
    testImportPrefixes: const ['stub_'],
    note: 'package:mockito keeps its place: a third-party package whose name '
        'starts with a prefix is not a file of yours.',
  );

  _demo(
    '--relative-imports: your own package: URIs rewritten as paths',
    [
      "import 'package:my_app/core/theme.dart';",
      "import 'package:http/http.dart';",
      '',
      'void main() {}',
    ],
    relativeImports: true,
    libRelativePath: 'features/home/view.dart',
    note: 'Only inside lib/, and only your own package — `package:http` has no '
        'relative form from here. This is what `prefer_relative_imports` '
        'wants; `always_use_package_imports` wants the opposite, so the '
        'choice has to be yours.',
  );

  _demo(
    '--attach-comments: a note travels with the import it explains',
    [
      "import 'dart:io';",
      '// Pinned to 0.13 until #412 lands upstream.',
      "import 'package:http/http.dart';",
      "import 'package:my_app/home.dart';",
      '',
      'void main() {}',
    ],
    attachComments: true,
    note: 'Without it the note stays put while the import moves, and ends up '
        'explaining whatever landed under it. The note above the FIRST '
        'directive is a file header either way, and is never attached.',
  );
}

// ---------------------------------------------------------------------------
// sortPubspec: the dependency lists, alphabetised
// ---------------------------------------------------------------------------

void _pubspec() {
  _heading('sortPubspec');

  const pubspec = '''
name: my_app

dependencies:
  provider: ^6.0.0
  flutter:
    sdk: flutter
  http: ^1.2.0
''';

  stdout.writeln('\n── Dependencies sorted, block values kept whole');
  _block('before', pubspec.trimRight().split('\n'));
  _block('after', sortPubspec(pubspec).trimRight().split('\n'));
  stdout.writeln(
    '   `flutter:` keeps its `sdk:` line: the sort moves entries, not lines.',
  );
}

// ---------------------------------------------------------------------------
// directiveUris + ImportGraph: what `--report` is made of
// ---------------------------------------------------------------------------

void _graph() {
  _heading('directiveUris and ImportGraph');

  final uris = directiveUris([
    "import 'dart:io';",
    "export 'src/api.dart';",
    "part 'model.g.dart';",
    "import 'stub.dart' if (dart.library.js_interop) 'web.dart';",
    "// import 'deleted_last_year.dart';",
  ]);

  stdout.writeln('\n── Every URI a file declares');
  _block('found', uris);
  stdout.writeln(
    '   `part` counts (a part file is never imported, only parted), a '
    'conditional\n   import names every branch, and a commented-out import is '
    'not an edge.',
  );

  final graph = ImportGraph.build(
    {
      'lib/main.dart': ['package:my_app/api.dart'],
      'lib/api.dart': ['package:my_app/db.dart'],
      'lib/db.dart': ['package:my_app/api.dart'],
      'lib/legacy_cart.dart': ['package:my_app/db.dart'],
    },
    'my_app',
  );
  const roots = {'lib/main.dart'};

  stdout.writeln('\n── Files that import each other');
  for (final group in graph.cycles()) {
    // `cycleWalk` returns the way in; the arrow back to the start is what
    // makes it a cycle, and closing it is the caller's line to draw — which
    // is exactly what `--report` prints.
    final walk = graph.cycleWalk(group);
    _block('walk', ['${walk.join(' → ')} → ${walk.first}']);
  }
  stdout.writeln(
    '   Every arrow is an import some file really declares. Sorting the group '
    'and\n   drawing arrows between neighbours would be easier and would '
    'invent edges —\n   and someone following an invented one opens the wrong '
    'file.',
  );

  stdout.writeln('\n── Files no entry point reaches');
  _block('unreachable', graph.unreachable(roots: roots));
  stdout.writeln(
    '   `legacy_cart.dart` imports something alive, so nothing is missing from '
    'it —\n   nothing reaches IT. That is what separates a dead file from an '
    'unused import.',
  );
}

// ---------------------------------------------------------------------------
// The path helpers the scan is built on
// ---------------------------------------------------------------------------

void _paths() {
  _heading('resolveUri, toPosix and compilePatterns');

  String resolved(String uri, String from) =>
      '${uri.padRight(32)}->  ${resolveUri(
        uri,
        from: from,
        packageName: 'my_app',
      )}';

  stdout.writeln('\n── A URI resolved to a file in the project');
  _block('resolved', [
    resolved('package:my_app/api.dart', 'lib/main.dart'),
    resolved('widgets/button.dart', 'lib/features/home.dart'),
    resolved('dart:io', 'lib/main.dart'),
  ]);
  stdout.writeln(
    '   `dart:`, another package and anything above the root resolve to null: '
    'real\n   imports, just not nodes of this project.',
  );

  stdout.writeln('\n── Patterns are regular expressions, and paths are POSIX');
  _block('toPosix',
      ['${r'lib\src\foo.dart'}  ->  ${toPosix(r'lib\src\foo.dart')}']);
  stdout.writeln(
    '   The path is normalised, not the pattern, so one `lib/src/` written in '
    'a\n   config file works on every platform.',
  );

  try {
    compilePatterns(['lib/[a-z.dart'], 'file pattern');
  } on FormatException catch (e) {
    _block('a bad pattern', [e.message]);
  }
  stdout.writeln(
    '   Compiled up front, so a malformed pattern is one line naming it — not '
    'a\n   RegExp error thrown halfway through the scan.',
  );
}

// ---------------------------------------------------------------------------
// TidyConfig: reading a config, and saying what is wrong with it
// ---------------------------------------------------------------------------

void _configuration() {
  _heading('TidyConfig');

  final wrapped = TidyConfig.fromStandalone(
    loadYaml('tidy_imports:\n  emojis: true\n'),
  );
  stdout.writeln('\n── A standalone file written in the pubspec shape');
  _block('emojis', ['${wrapped.emojis}']);
  _block('issues', wrapped.issues);
  stdout.writeln(
    '   The envelope belongs in pubspec.yaml, where the block shares the file '
    'with\n   everything else. In a standalone file the options ARE the '
    'document — written\n   this way, every one of them used to sit one level '
    'below where it was read,\n   so the file configured nothing and said so '
    'nowhere.',
  );

  final typo = TidyConfig.fromYaml(loadYaml('sort_export: true'));
  stdout.writeln('\n── An option that is almost an option');
  _block('issues', typo.issues);

  final wrongType = TidyConfig.fromYaml(loadYaml('emojis: "yes"'));
  stdout.writeln('\n── A value of the wrong kind');
  _block('issues', wrongType.issues);
  stdout.writeln(
    "   This used to be `type 'String' is not a subtype of type 'bool?' in "
    'type\n   cast` — loud, and naming no key.',
  );

  stdout.writeln(
    '\n   Each of these keeps the run going, on the defaults it fell back to. '
    'Pass\n   `--strict-config` to exit 1 on any of them instead, before the '
    'first file is\n   touched — for CI, where a warning nobody reads is the '
    'same as no warning.',
  );
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

/// Runs one demonstration and prints the lines before and after.
///
/// Every parameter here is a flag on the command line and a key in the config
/// file: this one signature is the whole surface.
void _demo(
  String title,
  List<String> lines, {
  bool emojis = false,
  bool noComments = false,
  bool noBlankLines = false,
  List<CustomTier> customTiers = const [],
  bool groupProjectByFolder = false,
  int groupProjectByFolderDepth = 0,
  bool separateRelativeImports = false,
  bool sortExports = false,
  bool removeDuplicates = false,
  bool testImports = false,
  List<String> testImportPrefixes = TidyConfig.defaultTestImportPrefixes,
  bool flat = false,
  bool relativeImports = false,
  String? libRelativePath,
  bool attachComments = false,
  String? note,
}) {
  final result = sortImports(
    lines,
    'my_app',
    emojis,
    // The fourth positional is `exitIfChanged`: deprecated, inert since 1.4.2,
    // and gone in 3.0.0. Passed once, here, so the demos stay readable.
    // ignore: deprecated_member_use_from_same_package
    false,
    noComments,
    noBlankLines: noBlankLines,
    customTiers: customTiers,
    groupProjectByFolder: groupProjectByFolder,
    groupProjectByFolderDepth: groupProjectByFolderDepth,
    separateRelativeImports: separateRelativeImports,
    sortExports: sortExports,
    removeDuplicates: removeDuplicates,
    testImports: testImports,
    testImportPrefixes: testImportPrefixes,
    flat: flat,
    relativeImports: relativeImports,
    libRelativePath: libRelativePath,
    attachComments: attachComments,
  );

  stdout.writeln('\n── $title');
  _block('before', lines);
  _block('after', result.sortedFile.trimRight().split('\n'));

  if (result.duplicatesRemoved > 0) {
    stdout.writeln('   (${result.duplicatesRemoved} duplicate dropped)');
  }
  if (note != null) stdout.writeln('   $note');
}

void _heading(String name) {
  stdout.writeln('\n${'=' * 74}\n$name\n${'=' * 74}');
}

void _block(String label, List<String> lines) {
  stdout.writeln('  $label:');
  for (final line in lines) {
    stdout.writeln(line.isEmpty ? '' : '    $line');
  }
}
