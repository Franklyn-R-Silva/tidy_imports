// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:tidy_imports/sort.dart';

const packageName = 'tidy_imports_test';

const dartImports = '''import 'dart:async';
import 'dart:io';
import 'dart:math';
''';

const flutterImports = '''import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
''';

const packageImports = '''import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
''';

const projectImports = '''import 'package:tidy_imports_test/another_file.dart';
import 'another_file.dart' as af;
''';

const sampleCode = '''void main() {
  print('hello');
}''';

void runSuite(bool emojis, bool noComments) {
  final dartComment =
      noComments ? '' : '// ${emojis ? '🎯 ' : ''}Dart imports:\n';
  final flutterComment =
      noComments ? '' : '// ${emojis ? '🐦 ' : ''}Flutter imports:\n';
  final packageComment =
      noComments ? '' : '// ${emojis ? '📦 ' : ''}Package imports:\n';
  final projectComment =
      noComments ? '' : '// ${emojis ? '🌎 ' : ''}Project imports:\n';

  test('empty input', () {
    expect(
      sortImports([], packageName, emojis, false, noComments).sortedFile,
      '\n',
    );
  });

  test('single code line, no imports', () {
    expect(
      sortImports(
        ['enum Event { a, b, c }', ''],
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      'enum Event { a, b, c }\n',
    );
  });

  test('no code, only imports', () {
    expect(
      sortImports(
        '$projectImports\n$packageImports\n$dartImports\n$flutterImports\n'
            .split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$dartComment$dartImports\n'
      '$flutterComment$flutterImports\n'
      '$packageComment$packageImports\n'
      '$projectComment$projectImports\n',
    );
  });

  test('no imports, code only', () {
    expect(
      sortImports(
        sampleCode.split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$sampleCode\n',
    );
  });

  test('dart imports only', () {
    expect(
      sortImports(
        '$dartImports\n$sampleCode'.split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$dartComment$dartImports\n$sampleCode\n',
    );
  });

  test('flutter imports only', () {
    expect(
      sortImports(
        '$flutterImports\n$sampleCode'.split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$flutterComment$flutterImports\n$sampleCode\n',
    );
  });

  test('package imports only', () {
    expect(
      sortImports(
        '$packageImports\n$sampleCode'.split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$packageComment$packageImports\n$sampleCode\n',
    );
  });

  test('project imports only', () {
    expect(
      sortImports(
        '$projectImports\n$sampleCode'.split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$projectComment$projectImports\n$sampleCode\n',
    );
  });

  test('all import groups mixed order', () {
    expect(
      sortImports(
        '$projectImports\n$packageImports\n$dartImports\n$flutterImports\n$sampleCode'
            .split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      '$dartComment$dartImports\n'
      '$flutterComment$flutterImports\n'
      '$packageComment$packageImports\n'
      '$projectComment$projectImports\n'
      '$sampleCode\n',
    );
  });

  test('library declaration before imports', () {
    expect(
      sortImports(
        'library my_lib;\n$projectImports\n$dartImports\n$sampleCode'
            .split('\n'),
        packageName,
        emojis,
        false,
        noComments,
      ).sortedFile,
      'library my_lib;\n\n'
      '$dartComment$dartImports\n'
      '$projectComment$projectImports\n'
      '$sampleCode\n',
    );
  });

  test('already sorted file has updated=false', () {
    final alreadySorted = '$dartComment$dartImports\n$sampleCode\n';
    final result = sortImports(
      alreadySorted.split('\n'),
      packageName,
      emojis,
      false,
      noComments,
    );
    expect(result.updated, false);
  });

  test('imports inside triple-quote string are ignored', () {
    const fileWithMultilineString = r"""
void main() {
  const sql = '''
  import 'dart:io';
  ''';
  print(sql);
}
""";
    final result = sortImports(
      fileWithMultilineString.split('\n'),
      packageName,
      emojis,
      false,
      noComments,
    );
    expect(result.updated, false);
  });

  test('part of before imports', () {
    const input = "part of 'my_lib.dart';\nimport 'dart:io';\n";
    final result = sortImports(
      input.split('\n'),
      packageName,
      emojis,
      false,
      noComments,
    );
    expect(result.sortedFile, contains("import 'dart:io';"));
  });
}

void main() {
  group('No emojis, with comments', () => runSuite(false, false));
  group('Emojis, with comments', () => runSuite(true, false));
  group('No emojis, no comments', () => runSuite(false, true));
  group('Emojis, no comments', () => runSuite(true, true));
}
