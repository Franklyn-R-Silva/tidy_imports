@Timeout(Duration(minutes: 2))
library;

// Dart imports:
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

  test('reports an invalid file pattern instead of crashing', () {
    libFile('main.dart').writeAsStringSync(unsorted);

    final result = run(['lib/[a-z.dart']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('invalid file pattern'));
    expect(result.stderr, isNot(contains('#0 ')), reason: 'no stack trace');
  });
}
