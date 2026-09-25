@Timeout(Duration(minutes: 2))
library;

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:test/test.dart';

/// End-to-end tests for `bin/tidy_imports.dart`.
///
/// The rest of the suite exercises the pure functions in `lib/`; these cover
/// what only the binary does: writing files, honoring read-only modes, exit
/// codes, line-ending preservation, and config discovery.
void main() {
  final cli = '${Directory.current.path}/bin/tidy_imports.dart';

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tidy_imports_cli_');
    Directory('${temp.path}/lib').createSync(recursive: true);
    File('${temp.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  ProcessResult run([List<String> args = const []]) => Process.runSync(
        Platform.resolvedExecutable,
        ['run', cli, ...args],
        workingDirectory: temp.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  File libFile(String name) => File('${temp.path}/lib/$name');

  const unsorted = "import 'package:demo/z.dart';\n"
      "import 'dart:io';\n"
      '\n'
      'void main() {}\n';

  const sorted = '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/z.dart';

void main() {}
''';

  test('sorts and writes a dart file', () {
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    final result = run();

    expect(result.exitCode, 0);
    expect(file.readAsStringSync(), sorted);
  });

  test('runs without a pubspec.lock (pub workspace)', () {
    libFile('main.dart').writeAsStringSync(unsorted);

    expect(File('${temp.path}/pubspec.lock').existsSync(), isFalse);
    expect(run().exitCode, 0);
  });

  test('--dry-run reports without writing', () {
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    final result = run(['--dry-run']);

    expect(result.exitCode, 0);
    expect(file.readAsStringSync(), unsorted);
    expect(result.stdout, contains('Would sort'));
  });

  test('--exit-if-changed fails and names every unsorted file', () {
    libFile('a.dart').writeAsStringSync(unsorted);
    libFile('b.dart').writeAsStringSync(unsorted);

    final result = run(['--exit-if-changed']);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('a.dart'));
    expect(result.stdout, contains('b.dart'));
    expect(libFile('a.dart').readAsStringSync(), unsorted);
  });

  test('preserves CRLF line endings', () {
    final file = libFile('main.dart')
      ..writeAsStringSync(unsorted.replaceAll('\n', '\r\n'));

    expect(run().exitCode, 0);
    expect(file.readAsStringSync(), sorted.replaceAll('\n', '\r\n'));
  });

  test('honors ignored_files from the pubspec config block', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  ignored_files:
    - \\.g\\.dart\$
''');
    final generated = libFile('model.g.dart')..writeAsStringSync(unsorted);
    final normal = libFile('main.dart')..writeAsStringSync(unsorted);

    expect(run().exitCode, 0);
    expect(generated.readAsStringSync(), unsorted);
    expect(normal.readAsStringSync(), sorted);
  });

  test('--test-imports splits project test doubles out', () {
    final file = libFile('main.dart')
      ..writeAsStringSync("import 'fake_repo.dart';\n"
          "import 'package:demo/z.dart';\n"
          '\n'
          'void main() {}\n');

    expect(run(['--test-imports']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      '''
// Project imports:
import 'package:demo/z.dart';

// Test imports:
import 'fake_repo.dart';

void main() {}
''',
    );
  });

  test('--separate-relative-imports splits the project group', () {
    final file = libFile('main.dart')
      ..writeAsStringSync("import 'another_file.dart';\n"
          "import 'package:demo/z.dart';\n"
          '\n'
          'void main() {}\n');

    expect(run(['--separate-relative-imports']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      '''
// Project imports:
import 'package:demo/z.dart';

import 'another_file.dart';

void main() {}
''',
    );
  });

  test('--sort-exports leaves no blank line below a barrel file', () {
    final file = libFile('barrel.dart')
      ..writeAsStringSync("export 'package:demo/z.dart';\n"
          "export 'package:demo/a.dart';\n");

    expect(run(['--sort-exports']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      '''
// Project exports:
export 'package:demo/a.dart';
export 'package:demo/z.dart';
''',
    );

    // A second pass must find nothing left to do (issue #6).
    expect(run(['--sort-exports', '--exit-if-changed']).exitCode, 0);
  });

  test('a positional pattern with no .dart suffix still filters', () {
    Directory('${temp.path}/lib/sub').createSync(recursive: true);
    final outside = libFile('main.dart')..writeAsStringSync(unsorted);
    final inside = File('${temp.path}/lib/sub/nested.dart')
      ..writeAsStringSync(unsorted);

    // Forward slashes, on every platform: the pattern is matched against a
    // path normalised to `/`, so this works on Windows too.
    expect(run(['lib/sub/']).exitCode, 0);

    expect(inside.readAsStringSync(), sorted);
    expect(
      outside.readAsStringSync(),
      unsorted,
      reason: 'a filtered run must not touch files outside the pattern',
    );
  });

  test('never walks into hidden directories or a package build/', () {
    // A sub-package's `.dart_tool/` and `build/` hold generated Dart, and a
    // Flutter app's `.plugin_symlinks/` lead into the pub cache. None of it is
    // the project's to rewrite. `lib/src/build/` is ordinary source.
    final hidden = File(
      '${temp.path}/packages/app/.dart_tool/build/entrypoint/build.dart',
    )
      ..createSync(recursive: true)
      ..writeAsStringSync(unsorted);
    final output = File('${temp.path}/packages/app/build/gen/x.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(unsorted);
    File('${temp.path}/packages/app/pubspec.yaml')
        .writeAsStringSync('name: app\n');
    final source = File('${temp.path}/lib/src/build/y.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(unsorted);

    expect(run().exitCode, 0);

    expect(hidden.readAsStringSync(), unsorted);
    expect(output.readAsStringSync(), unsorted);
    expect(source.readAsStringSync(), sorted);
  });

  test('never follows a link out of the project', () {
    final outside = Directory.systemTemp.createTempSync('tidy_imports_link_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final foreign = File('${outside.path}/plugin.dart')
      ..writeAsStringSync(unsorted);

    try {
      Link('${temp.path}/lib/plugin').createSync(outside.path);
    } on FileSystemException {
      // Windows only lets an elevated or developer-mode shell make a link.
      markTestSkipped('this platform does not allow creating a link here');
      return;
    }

    expect(run().exitCode, 0);
    expect(foreign.readAsStringSync(), unsorted);
  });

  test('reports an invalid ignored_files pattern instead of crashing', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  ignored_files:
    - lib/[a-z.dart
''');
    libFile('main.dart').writeAsStringSync(unsorted);

    final result = run();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('invalid ignored_files entry'));
    expect(result.stderr, isNot(contains('#0 ')), reason: 'no stack trace');
  });

  test('--no-emojis overrides emojis: true in the config', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  emojis: true
''');
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    expect(run(['--no-emojis']).exitCode, 0);
    expect(file.readAsStringSync(), sorted);
  });

  test('a config flag still applies when nothing is passed', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  emojis: true
''');
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    expect(run().exitCode, 0);
    expect(file.readAsStringSync(), contains('// 🎯 Dart imports:'));
  });

  test('--comments overrides comments: false in the config', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  comments: false
''');
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    expect(run(['--comments']).exitCode, 0);
    expect(file.readAsStringSync(), sorted);
  });

  test('--no-comments still works as the negated form', () {
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    expect(run(['--no-comments']).exitCode, 0);
    expect(file.readAsStringSync(), isNot(contains('// Dart imports:')));
    expect(file.readAsStringSync(), contains("import 'dart:io';"));
  });

  test('--remove-duplicates folds repeated imports and reports the count', () {
    final file = libFile('main.dart')
      ..writeAsStringSync("import 'package:demo/z.dart';\n"
          "import 'dart:io';\n"
          "import 'package:demo/z.dart';\n"
          '\n'
          'void main() {}\n');

    final result = run(['--remove-duplicates']);

    expect(result.exitCode, 0);
    expect(file.readAsStringSync(), sorted);
    expect(result.stdout, contains('dropped 1 duplicate import'));
  });

  test('duplicates are kept unless the flag is passed', () {
    const withDuplicate = "import 'dart:io';\n"
        "import 'dart:io';\n"
        '\n'
        'void main() {}\n';
    final file = libFile('main.dart')..writeAsStringSync(withDuplicate);

    expect(run().exitCode, 0);
    expect(
      file.readAsStringSync(),
      '''
// Dart imports:
import 'dart:io';
import 'dart:io';

void main() {}
''',
    );
  });

  test('--dry-run with --remove-duplicates writes nothing', () {
    const withDuplicate = "import 'dart:io';\n"
        "import 'dart:io';\n"
        '\n'
        'void main() {}\n';
    final file = libFile('main.dart')..writeAsStringSync(withDuplicate);

    final result = run(['--dry-run', '--remove-duplicates']);

    expect(result.exitCode, 0);
    expect(file.readAsStringSync(), withDuplicate);
    expect(result.stdout, contains('found 1 duplicate import'));
  });

  test('--flat emits one alphabetical run, flutter included', () {
    final file = libFile('main.dart')
      ..writeAsStringSync("import 'package:flutter/material.dart';\n"
          "import 'package:args/args.dart';\n"
          "import 'dart:io';\n"
          '\n'
          'void main() {}\n');

    expect(run(['--flat']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      '''
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter/material.dart';

void main() {}
''',
    );
  });

  test('--flat output is what dart format would already have written', () {
    final file = libFile('main.dart')
      ..writeAsStringSync("import 'package:args/args.dart';\n"
          "import 'dart:io';\n"
          "import 'helper.dart';\n"
          '\n'
          'void main() {}\n');

    expect(run(['--flat']).exitCode, 0);
    final flat = file.readAsStringSync();

    final formatted = Process.runSync(
      Platform.resolvedExecutable,
      ['format', file.path],
      workingDirectory: temp.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(formatted.exitCode, 0);
    expect(
      file.readAsStringSync(),
      flat,
      reason: 'dart format 3.13+ writes a blank line at each section '
          'boundary. Emitting none left the formatter adding them and the '
          'next --flat run taking them away, forever (issue #1)',
    );
  });

  test('--relative-imports rewrites own-package uris under lib/', () {
    Directory('${temp.path}/lib/src').createSync(recursive: true);
    final file = File('${temp.path}/lib/src/a.dart')
      ..writeAsStringSync("import 'package:demo/src/b.dart';\n"
          '\n'
          'void main() {}\n');

    expect(run(['--relative-imports']).exitCode, 0);
    expect(file.readAsStringSync(), contains("import 'b.dart';"));
  });

  test('--relative-imports leaves files outside lib/ alone', () {
    Directory('${temp.path}/test').createSync(recursive: true);
    const original = "import 'package:demo/src/b.dart';\n"
        '\n'
        'void main() {}\n';
    final file = File('${temp.path}/test/a_test.dart')
      ..writeAsStringSync(original);

    expect(run(['--relative-imports']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      contains("import 'package:demo/src/b.dart';"),
      reason: 'a test cannot reach lib/ with a relative uri',
    );
  });

  test('--package-imports rewrites relative uris under lib/', () {
    Directory('${temp.path}/lib/src/p2').createSync(recursive: true);
    final file = File('${temp.path}/lib/src/p2/bar.dart')
      ..writeAsStringSync("import '../foo.dart';\n\nvoid main() {}\n");

    expect(run(['--package-imports', '--no-comments']).exitCode, 0);
    expect(
      file.readAsStringSync(),
      "import 'package:demo/src/foo.dart';\n\nvoid main() {}\n",
    );
  });

  test('package_imports from the config is overridden by --relative-imports',
      () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: demo
tidy_imports:
  package_imports: true
''');
    final file = libFile('a.dart')
      ..writeAsStringSync(
        "import 'package:demo/src/b.dart';\n\nvoid main() {}\n",
      );

    final result = run(['--relative-imports', '--no-comments']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(file.readAsStringSync(), startsWith("import 'src/b.dart';"));
  });

  test('--relative-imports with --package-imports is an error', () {
    libFile('a.dart').writeAsStringSync(unsorted);

    final result = run(['--relative-imports', '--package-imports']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('opposite directions'));
    expect(libFile('a.dart').readAsStringSync(), unsorted);
  });

  group('--doctor', () {
    void lints(List<String> rules) =>
        File('${temp.path}/analysis_options.yaml').writeAsStringSync(
          'linter:\n  rules:\n${rules.map((r) => '    - $r\n').join()}',
        );

    test('with no lint that reads imports, has nothing to change', () {
      lints(['avoid_print']);

      final result = run(['--doctor']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Nothing to change'));
    });

    test('says which flag agrees with directives_ordering', () {
      lints(['directives_ordering']);
      libFile('a.dart').writeAsStringSync(unsorted);

      final result = run(['--doctor']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('flat: true'));
      expect(result.stdout, contains('--apply'));
      expect(
        libFile('a.dart').readAsStringSync(),
        unsorted,
        reason: '--doctor reads the configuration; it sorts nothing',
      );
      expect(
          File('${temp.path}/pubspec.yaml').readAsStringSync(), 'name: demo\n');
    });

    test('--apply writes the keys, and a second look finds nothing', () {
      lints(['directives_ordering', 'always_use_package_imports']);

      final applied = run(['--doctor', '--apply']);

      expect(applied.exitCode, 0, reason: '${applied.stderr}');
      expect(
        File('${temp.path}/pubspec.yaml').readAsStringSync(),
        'name: demo\n\ntidy_imports:\n'
        '  flat: true\n  sort_exports: true\n  package_imports: true\n',
      );

      final again = run(['--doctor', '--exit-if-changed']);
      expect(again.exitCode, 0, reason: '${again.stdout}');
      expect(again.stdout, contains('Nothing to change'));
    });

    test('--apply edits a standalone tidy_imports.yaml when there is one', () {
      lints(['always_use_package_imports']);
      final standalone = File('${temp.path}/tidy_imports.yaml')
        ..writeAsStringSync('emojis: true\n');

      expect(run(['--doctor', '--apply']).exitCode, 0);

      expect(
        standalone.readAsStringSync(),
        'emojis: true\npackage_imports: true\n',
      );
      expect(
          File('${temp.path}/pubspec.yaml').readAsStringSync(), 'name: demo\n');
    });

    test('--apply with --dry-run writes nothing', () {
      lints(['directives_ordering']);

      final result = run(['--doctor', '--apply', '--dry-run']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Would write'));
      expect(
          File('${temp.path}/pubspec.yaml').readAsStringSync(), 'name: demo\n');
    });

    test('--exit-if-changed fails on a fight', () {
      lints(['directives_ordering']);

      final result = run(['--doctor', '--exit-if-changed']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('--exit-if-changed'));
    });

    test('--exit-if-changed passes on a suggestion alone', () {
      lints(['always_use_package_imports']);

      expect(run(['--doctor', '--exit-if-changed']).exitCode, 0);
    });

    test('two contradicting lints are a conflict --apply cannot settle', () {
      lints(['prefer_relative_imports', 'always_use_package_imports']);

      final result = run(['--doctor', '--apply', '--exit-if-changed']);

      expect(result.exitCode, 1);
      expect(result.stdout, contains('contradict'));
      expect(
          File('${temp.path}/pubspec.yaml').readAsStringSync(), 'name: demo\n');
    });

    test('an include that does not resolve is reported, not fatal', () {
      File('${temp.path}/analysis_options.yaml').writeAsStringSync(
        'include: package:not_resolved/options.yaml\n',
      );

      final result = run(['--doctor']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('dart pub get'));
    });

    test('--apply without --doctor is an error', () {
      final result = run(['--apply']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('--doctor'));
    });

    test('--doctor with --report is an error', () {
      final result = run(['--doctor', '--report']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('separate run modes'));
    });
  });

  group('--report', () {
    String out(List<String> args) => run(args).stdout as String;

    File at(String relative) =>
        File('${temp.path}/$relative')..parent.createSync(recursive: true);

    void writeProject() {
      libFile('main.dart')
          .writeAsStringSync("import 'a.dart';\nvoid main() {}\n");
      libFile('a.dart').writeAsStringSync("import 'c.dart';\n");
      libFile('b.dart').writeAsStringSync("import 'a.dart';\n");
      libFile('c.dart').writeAsStringSync("import 'b.dart';\n");
      libFile('dead.dart').writeAsStringSync('class Dead {}\n');
      libFile('model.dart').writeAsStringSync("part 'model.g.dart';\n");
      libFile('model.g.dart').writeAsStringSync("part of 'model.dart';\n");
    }

    test('draws the cycle along edges that exist, not alphabetically', () {
      writeProject();

      final text = out(['--report']);

      // a imports c, c imports b, b imports a. Alphabetical order would have
      // claimed a → b, which no file declares.
      expect(text, contains('1 group of files that import each other'));
      expect(
        text,
        contains('lib/a.dart → lib/c.dart → lib/b.dart → lib/a.dart'),
      );
    });

    test('names the rest of a group the walk does not pass through', () {
      libFile('main.dart')
          .writeAsStringSync("import 'x.dart';\nvoid main() {}\n");
      libFile('x.dart')
          .writeAsStringSync("import 'y.dart';\nimport 'z.dart';\n");
      libFile('y.dart').writeAsStringSync("import 'x.dart';\n");
      libFile('z.dart').writeAsStringSync("import 'x.dart';\n");

      expect(
        out(['--report']),
        contains(
            'lib/x.dart → lib/y.dart → lib/x.dart  (+1 more in this group)'),
      );
    });

    test('names every file no entry point reaches, parts included', () {
      writeProject();

      final text = out(['--report']);

      // Nothing reaches dead.dart or model.dart, and model.g.dart is only
      // reached from model.dart — so all three are dead, and all three are
      // named: the list is what to delete, and a part goes with its owner.
      expect(text, contains('3 files no entry point reaches'));
      expect(text, contains('lib/dead.dart'));
      expect(text, contains('lib/model.dart'));
      expect(text, contains('lib/model.g.dart'));
    });

    test('spares a part whose owner is reachable', () {
      libFile('main.dart')
          .writeAsStringSync("import 'model.dart';\nvoid main() {}\n");
      libFile('model.dart').writeAsStringSync("part 'model.g.dart';\n");
      libFile('model.g.dart').writeAsStringSync("part of 'model.dart';\n");

      expect(out(['--report']), contains('0 findings'),
          reason: 'a part is referenced by the file that parts it');
    });

    test('sees through a dead barrel to what it exports', () {
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      libFile('barrel.dart').writeAsStringSync("export 'inner.dart';\n");
      libFile('inner.dart').writeAsStringSync('class Inner {}\n');

      final text = out(['--report']);

      expect(text, contains('2 files no entry point reaches'));
      expect(text, contains('lib/barrel.dart'));
      expect(text, contains('lib/inner.dart'));
    });

    test('always prints the caveat under the list', () {
      writeProject();

      expect(out(['--report']), contains('read before deleting'));
    });

    test('spares lib/main.dart and flavour mains', () {
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      libFile('main_dev.dart').writeAsStringSync('void main() {}\n');
      libFile('main_production.dart').writeAsStringSync('void main() {}\n');

      final text = out(['--report']);

      expect(text, contains('0 findings'));
      expect(text, isNot(contains('main_dev')));
    });

    test('spares any lib/ file that declares main()', () {
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      libFile('migrate.dart')
          .writeAsStringSync('Future<void> main() async {}\n');
      libFile('note.dart').writeAsStringSync('// void main() {}\nclass N {}\n');

      final text = out(['--report']);

      expect(text, isNot(contains('lib/migrate.dart')));
      expect(text, contains('lib/note.dart'),
          reason: 'a main() in a comment is not an entry point');
    });

    test('spares roots declared in report_roots', () {
      File('${temp.path}/pubspec.yaml').writeAsStringSync(
        'name: demo\ntidy_imports:\n  report_roots:\n    - /lib/app/bootstrap\n',
      );
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      at('lib/app/bootstrap.dart').writeAsStringSync('void boot() {}\n');

      expect(out(['--report']), contains('0 findings'));
    });

    test('treats every non-src file of a library as public api', () {
      File('${temp.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
      libFile('demo.dart').writeAsStringSync("export 'src/impl.dart';\n");
      libFile('testing.dart').writeAsStringSync('class Testing {}\n');
      at('lib/src/impl.dart').writeAsStringSync('class Impl {}\n');
      at('lib/src/old.dart').writeAsStringSync('class Old {}\n');

      final text = out(['--report']);

      expect(text, isNot(contains('lib/testing.dart')));
      expect(text, contains('lib/src/old.dart'));
    });

    test('an app (publish_to: none) reports a dead top-level file', () {
      File('${temp.path}/pubspec.yaml')
          .writeAsStringSync("name: demo\npublish_to: 'none'\n");
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      libFile('old_screen.dart').writeAsStringSync('class Old {}\n');

      expect(out(['--report']), contains('lib/old_screen.dart'));
    });

    test('ignored_files narrows what is printed, not what is read', () {
      File('${temp.path}/pubspec.yaml').writeAsStringSync(
        'name: demo\ntidy_imports:\n  ignored_files:\n    - \\.config\\.dart\$\n',
      );
      libFile('main.dart').writeAsStringSync(
          "import 'injection.config.dart';\nvoid main() {}\n");
      libFile('injection.config.dart')
          .writeAsStringSync("import 'package:demo/services/foo.dart';\n");
      at('lib/services/foo.dart').writeAsStringSync('class Foo {}\n');

      expect(out(['--report']), contains('0 findings'),
          reason: 'the ignored importer still keeps foo.dart alive');
    });

    test('a generated cycle can be hidden without losing its edges', () {
      File('${temp.path}/pubspec.yaml').writeAsStringSync(
        'name: demo\ntidy_imports:\n  ignored_files:\n    - /lib/l10n/\n',
      );
      libFile('main.dart').writeAsStringSync(
          "import 'l10n/app_localizations.dart';\nvoid main() {}\n");
      at('lib/l10n/app_localizations.dart').writeAsStringSync(
          "import 'app_localizations_en.dart';\nimport 'strings.dart';\n");
      at('lib/l10n/app_localizations_en.dart')
          .writeAsStringSync("import 'app_localizations.dart';\n");
      at('lib/l10n/strings.dart').writeAsStringSync('class S {}\n');

      expect(out(['--report']), contains('0 findings'));
    });

    test(
        'a positional pattern narrows the report, and keeps a cycle that '
        'crosses it', () {
      libFile('main.dart').writeAsStringSync(
          "import 'features/y.dart';\nimport 'core/a.dart';\nvoid main() {}\n");
      at('lib/features/y.dart').writeAsStringSync('class Y {}\n');
      at('lib/features/z.dart').writeAsStringSync("import '../core/a.dart';\n");
      at('lib/core/a.dart').writeAsStringSync("import '../features/z.dart';\n");

      final text = out(['--report', 'lib/features/']);

      expect(text, contains('1 group of files that import each other'));
      expect(text, contains('Every file under lib/ is reachable'),
          reason: 'main.dart is outside the pattern but still in the graph, '
              'so y.dart is not dead');
    });

    test('an importer under example/ keeps a lib/ file alive', () {
      File('${temp.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
      libFile('demo.dart').writeAsStringSync('class Demo {}\n');
      at('lib/src/only_example.dart').writeAsStringSync('class E {}\n');
      at('example/main.dart').writeAsStringSync(
          "import 'package:demo/src/only_example.dart';\nvoid main() {}\n");

      expect(out(['--report']), contains('0 findings'));
    });

    test('every target of a conditional import is an edge', () {
      libFile('main.dart').writeAsStringSync(
        "import 'stub.dart'\n"
        "    if (dart.library.io) 'io_impl.dart'\n"
        "    if (dart.library.html) 'web_impl.dart';\n"
        'void main() {}\n',
      );
      for (final name in ['stub', 'io_impl', 'web_impl']) {
        libFile('$name.dart').writeAsStringSync('class Impl {}\n');
      }

      expect(out(['--report']), contains('0 findings'));
    });

    test('the plugin registrant is neither sorted nor reported', () {
      File('${temp.path}/pubspec.lock')
          .writeAsStringSync('packages:\n  flutter:\n    version: "0.0.0"\n');
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      final registrant = libFile('generated_plugin_registrant.dart')
        ..writeAsStringSync("import 'dart:io';\nimport 'dart:async';\n");

      expect(out(['--report']), contains('0 findings'));
      expect(run(['--dry-run']).stdout, isNot(contains('registrant')));
      expect(registrant.readAsStringSync(), startsWith("import 'dart:io';"));
    });

    test('resolves package: uris of a sub-package under packages/', () {
      libFile('main.dart').writeAsStringSync('void main() {}\n');
      at('packages/core/pubspec.yaml').writeAsStringSync('name: core\n');
      at('packages/core/lib/core.dart')
          .writeAsStringSync("export 'package:core/b.dart';\n");
      at('packages/core/lib/a.dart')
          .writeAsStringSync("import 'package:core/b.dart';\n");
      at('packages/core/lib/b.dart')
          .writeAsStringSync("import 'package:core/a.dart';\n");
      at('packages/core/lib/src/dead.dart').writeAsStringSync('class D {}\n');

      final text = out(['--report']);

      expect(text,
          contains('packages/core/lib/a.dart → packages/core/lib/b.dart'));
      expect(text, contains('packages/core/lib/src/dead.dart'));
    });

    test('a file with invalid utf-8 still takes its place in the graph', () {
      libFile('main.dart')
          .writeAsStringSync("import 'latin.dart';\nvoid main() {}\n");
      libFile('latin.dart').writeAsBytesSync(
          [...utf8.encode('// caf'), 0xE9, ...utf8.encode('\nclass L {}\n')]);

      final result = run(['--report']);

      expect(result.stderr, isNot(contains('Unhandled')));
      expect(result.stdout, contains('0 findings'));
    });

    test('says so when there is nothing to read', () {
      Directory('${temp.path}/lib').deleteSync(recursive: true);

      final result = run(['--report']);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('nothing to report'));
      expect(run(['--report', '--exit-if-changed']).exitCode, 1,
          reason: 'a gate that inspected nothing must not pass');
    });

    test('writes nothing', () {
      const unsortedFile = "import 'package:demo/z.dart';\n"
          "import 'dart:io';\n"
          '\n'
          'void main() {}\n';
      final file = libFile('main.dart')..writeAsStringSync(unsortedFile);

      expect(run(['--report']).exitCode, 0);
      expect(file.readAsStringSync(), unsortedFile);
    });

    test('with --exit-if-changed it fails on a finding and says why', () {
      writeProject();

      final result = run(['--report', '--exit-if-changed']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Failing because --exit-if-changed'));
    });

    test('with --exit-if-changed a clean project passes', () {
      libFile('main.dart').writeAsStringSync("import 'a.dart';\n");
      libFile('a.dart').writeAsStringSync('class A {}\n');

      expect(run(['--report', '--exit-if-changed']).exitCode, 0);
    });

    test('names the most imported files and the features', () {
      at('lib/core/theme.dart').writeAsStringSync('class Theme {}\n');
      at('lib/auth/login.dart')
          .writeAsStringSync("import '../core/theme.dart';\n");
      libFile('main.dart').writeAsStringSync(
        "import 'auth/login.dart';\nimport 'core/theme.dart';\n"
        'void main() {}\n',
      );

      final text = out(['--report']);

      expect(text, contains('Most imported:'));
      expect(text, contains('2  lib/core/theme.dart'));
      expect(text, contains('Strongest coupling:'));
      expect(text, contains('lib/auth → lib/core  (1 import)'));
    });

    test('--format=mermaid prints only the diagram', () {
      writeProject();

      final result = run(['--report', '--format=mermaid']);

      expect(result.exitCode, 0);
      expect(result.stdout, startsWith('flowchart LR\n'));
      expect(result.stdout, isNot(contains('┏━━')));
      expect(result.stdout, contains('linkStyle'), reason: 'the a-b-c cycle');
      expect(result.stdout, contains('class '), reason: 'dead.dart is dashed');
    });

    test('--format=dot prints a digraph', () {
      writeProject();

      final dot = out(['--report', '--format=dot']);

      expect(dot, startsWith('digraph imports {'));
      expect(dot, contains('"lib/a.dart" -> "lib/c.dart"'));
    });

    test('--format=json is a document, and keeps the exit code', () {
      writeProject();

      final result = run(['--report', '--format=json', '--exit-if-changed']);

      expect(result.exitCode, 1, reason: 'the cycle and the dead file');
      final report = jsonDecode(result.stdout as String) as Map;
      expect(report['schemaVersion'], 1);
      expect(report['unreachable'], contains('lib/dead.dart'));
      expect(report['cycles'] as List, hasLength(1));
    });

    test('--feature-depth splits features one folder deeper', () {
      at('lib/features/auth/login.dart')
          .writeAsStringSync("import '../home/home.dart';\n");
      at('lib/features/home/home.dart').writeAsStringSync('class Home {}\n');

      final report = jsonDecode(
        out(['--report', '--format=json', '--feature-depth=2']),
      ) as Map;

      expect(
        (report['metrics'] as Map)['coupling'],
        [
          {
            'from': 'lib/features/auth',
            'to': 'lib/features/home',
            'edges': 1,
          },
        ],
      );
    });

    test('an unknown --format is an error line', () {
      final result = run(['--report', '--format=svg']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('svg'));
    });

    test('--format without --report is an error', () {
      final result = run(['--format=json']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('--report'));
    });

    test('a --feature-depth below 1 is an error', () {
      final result = run(['--report', '--feature-depth=0']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('--feature-depth'));
    });
  });

  test('an unreadable file is one error line, not a stack trace', () {
    libFile('main.dart').writeAsStringSync(unsorted);
    libFile('latin.dart').writeAsBytesSync(
        [...utf8.encode('// caf'), 0xE9, ...utf8.encode('\nclass L {}\n')]);

    final result = run();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('could not read'));
    expect(result.stderr, isNot(contains('#0 ')), reason: 'no stack trace');
    expect(libFile('main.dart').readAsStringSync(), sorted,
        reason: 'the readable file is still sorted');
  });

  test('an unknown flag is one error line, not a stack trace', () {
    final file = libFile('main.dart')..writeAsStringSync(unsorted);

    final result = run(['--sort-exprots']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Could not find an option named'));
    expect(result.stderr, contains('--help'));
    expect(
      result.stderr,
      isNot(contains('package:args')),
      reason: 'it used to reach the top of main() with eight frames under it',
    );
    expect(file.readAsStringSync(), unsorted);
  });

  test('a pubspec with no name: is an error, not a TypeError', () {
    File('${temp.path}/pubspec.yaml').writeAsStringSync('description: none\n');
    libFile('main.dart').writeAsStringSync(unsorted);

    final result = run();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('declares no `name:`'));
    expect(
      result.stderr,
      isNot(contains('is not a subtype of')),
      reason: "the name is what tells the project's own imports apart, so "
          'there is no run without it — but the cast named only two types',
    );
  });

  test('a pubspec that does not parse is an error, not a YamlException', () {
    File('${temp.path}/pubspec.yaml')
        .writeAsStringSync('name: demo\n  bad_indent: nope\n');
    libFile('main.dart').writeAsStringSync(unsorted);

    final result = run();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('pubspec.yaml could not be read'));
    expect(result.stderr, isNot(contains('package:yaml')));
  });

  test('reports an invalid file pattern instead of crashing', () {
    libFile('main.dart').writeAsStringSync(unsorted);

    final result = run(['lib/[a-z.dart']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('invalid file pattern'));
    expect(result.stderr, isNot(contains('#0 ')), reason: 'no stack trace');
  });

  group('config diagnostics', () {
    File configFile() => File('${temp.path}/tidy_imports.yaml');

    test('a config wrapped in tidy_imports: takes effect, with a warning', () {
      final file = libFile('main.dart')..writeAsStringSync(unsorted);
      configFile().writeAsStringSync('tidy_imports:\n  emojis: true\n');

      final result = run();

      expect(result.exitCode, 0);
      expect(
        file.readAsStringSync(),
        contains('🎯'),
        reason: 'the point of accepting the envelope is that the options '
            'inside it are obeyed — a warning that changed nothing would be '
            'the silent failure with extra text on top',
      );
      expect(result.stderr, contains('tidy_imports:'));
    });

    test('a misspelled option warns and names the option it almost is', () {
      libFile('main.dart').writeAsStringSync(unsorted);
      configFile().writeAsStringSync('sort_export: true\n');

      final result = run();

      expect(result.exitCode, 0);
      expect(result.stderr, contains('sort_exports'));
    });

    test('--strict-config turns the warning into a refusal', () {
      final file = libFile('main.dart')..writeAsStringSync(unsorted);
      configFile().writeAsStringSync('sort_export: true\n');

      final result = run(['--strict-config']);

      expect(result.exitCode, 1);
      expect(
        file.readAsStringSync(),
        unsorted,
        reason: 'a refusal that had already rewritten the project would be a '
            'strange kind of refusal',
      );
    });

    test('a config that does not parse warns and runs on the defaults', () {
      final file = libFile('main.dart')..writeAsStringSync(unsorted);
      configFile().writeAsStringSync('emojis: true\n  bad_indent: nope\n');

      final result = run();

      expect(result.exitCode, 0);
      expect(result.stderr, contains('not valid YAML'));
      expect(result.stderr, isNot(contains('package:yaml')));
      expect(file.readAsStringSync(), sorted);
    });

    test('--strict-config refuses a config that does not parse', () {
      final file = libFile('main.dart')..writeAsStringSync(unsorted);
      configFile().writeAsStringSync('emojis: true\n  bad_indent: nope\n');

      final result = run(['--strict-config']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('not valid YAML'));
      expect(
        file.readAsStringSync(),
        unsorted,
        reason: 'it refuses before the first file is touched',
      );
    });

    test('--strict-config passes on a config it understands', () {
      libFile('main.dart').writeAsStringSync(unsorted);
      configFile().writeAsStringSync('emojis: true\n');

      expect(run(['--strict-config']).exitCode, 0);
    });

    test('--ignore-config has no config to complain about', () {
      libFile('main.dart').writeAsStringSync(unsorted);
      configFile().writeAsStringSync('sort_export: true\n');

      final result = run(['--ignore-config']);

      expect(result.exitCode, 0);
      expect(result.stderr, isNot(contains('sort_exports')));
    });
  });
}
