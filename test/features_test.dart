// Dart imports:
import 'dart:io';

// Package imports:
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/config.dart';
import 'package:tidy_imports/pubspec_sort.dart';
import 'package:tidy_imports/sort.dart';

void main() {
  group('custom tiers (#81)', () {
    test('groups matching package imports into their own tier', () {
      final lines = [
        "import 'package:flutter/material.dart';",
        "import 'package:acme_shared/utils.dart';",
        "import 'package:http/http.dart';",
        "import 'package:demo/app.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        customTiers: const [CustomTier('Shared imports:', 'package:acme_')],
      );

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:http/http.dart';

// Shared imports:
import 'package:acme_shared/utils.dart';

// Project imports:
import 'package:demo/app.dart';

void main() {}
''',
      );
    });

    test('re-running an already-sorted tier file makes no change', () {
      final sorted = '''
// Package imports:
import 'package:http/http.dart';

// Shared imports:
import 'package:acme_shared/utils.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        customTiers: const [CustomTier('Shared imports:', 'package:acme_')],
      );

      expect(result.updated, isFalse);
    });
  });

  group('group project imports by folder (#69)', () {
    test('inserts a blank line between different project subfolders', () {
      final lines = [
        "import 'package:demo/aaa/foo.dart';",
        "import 'package:demo/bbb/baz.dart';",
        "import 'package:demo/aaa/bar.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/aaa/bar.dart';
import 'package:demo/aaa/foo.dart';

import 'package:demo/bbb/baz.dart';

void main() {}
''',
      );
    });

    test('re-running a folder-grouped file makes no change', () {
      final sorted = '''
// Project imports:
import 'package:demo/aaa/bar.dart';
import 'package:demo/aaa/foo.dart';

import 'package:demo/bbb/baz.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
      );

      expect(result.updated, isFalse);
    });
  });

  group('separate relative imports (#1)', () {
    test('inserts a blank line before relative project imports', () {
      final lines = [
        "import 'package:demo/home.dart';",
        "import 'another_file.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/home.dart';

import 'another_file.dart';

void main() {}
''',
      );
    });

    test('re-running a separated file makes no change', () {
      final sorted = '''
// Project imports:
import 'package:demo/home.dart';

import 'another_file.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        separateRelativeImports: true,
      );

      expect(result.updated, isFalse);
    });

    test('is a no-op when blank lines are off', () {
      final lines = [
        "import 'package:demo/home.dart';",
        "import 'another_file.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        noBlankLines: true,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/home.dart';
import 'another_file.dart';

void main() {}
''',
      );
    });

    test('adds no leading blank line when every import is relative', () {
      final lines = [
        "import 'b.dart';",
        "import 'a.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'a.dart';
import 'b.dart';

void main() {}
''',
      );
    });

    test('adds no trailing blank line when there are no relative imports', () {
      final lines = [
        "import 'package:demo/b.dart';",
        "import 'package:demo/a.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/a.dart';
import 'package:demo/b.dart';

void main() {}
''',
      );
    });

    test('does not stack a second blank line on top of folder grouping', () {
      final lines = [
        "import 'package:demo/aaa/foo.dart';",
        "import 'b.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/aaa/foo.dart';

import 'b.dart';

void main() {}
''',
      );
    });

    test('separates relative test doubles too', () {
      final lines = [
        "import 'fake_repo.dart';",
        "import 'package:demo/mock_service.dart';",
        "import 'package:demo/z.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        testImports: true,
        separateRelativeImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/z.dart';

// Test imports:
import 'package:demo/mock_service.dart';

import 'fake_repo.dart';

void main() {}
''',
      );
    });
  });

  group('no blank lines (#80)', () {
    test('omits separators between groups', () {
      final lines = [
        "import 'package:http/http.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        noBlankLines: true,
      );

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';
// Package imports:
import 'package:http/http.dart';

void main() {}
''',
      );
    });
  });

  group('pubspec sort (#89)', () {
    test('sorts dependency sections alphabetically', () {
      const input = '''
name: demo
dependencies:
  zebra: ^1.0.0
  alpha: ^2.0.0
dev_dependencies:
  test: ^1.0.0
  build: ^2.0.0
''';

      expect(
        sortPubspec(input),
        '''
name: demo
dependencies:
  alpha: ^2.0.0
  zebra: ^1.0.0
dev_dependencies:
  build: ^2.0.0
  test: ^1.0.0
''',
      );
    });

    test('preserves nested dependency blocks and leading comments', () {
      const input = '''
name: demo
dependencies:
  zebra: ^1.0.0
  # pin alpha
  alpha: ^2.0.0
  mango:
    git:
      url: https://example.com
''';

      expect(
        sortPubspec(input),
        '''
name: demo
dependencies:
  # pin alpha
  alpha: ^2.0.0
  mango:
    git:
      url: https://example.com
  zebra: ^1.0.0
''',
      );
    });

    test('already-sorted pubspec is returned unchanged', () {
      const input = '''
name: demo
dependencies:
  alpha: ^1.0.0
  zebra: ^2.0.0
''';

      expect(sortPubspec(input), input);
    });
  });

  group('test imports (fake_/mock_)', () {
    test('splits project test doubles into their own group', () {
      final lines = [
        "import 'package:demo/app.dart';",
        "import 'fake_cliente_details_repository.dart';",
        "import 'package:demo/mock_auth_service.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        testImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/app.dart';

// Test imports:
import 'package:demo/mock_auth_service.dart';
import 'fake_cliente_details_repository.dart';

void main() {}
''',
      );
    });

    test('is off by default', () {
      final lines = [
        "import 'fake_repo.dart';",
        "import 'package:demo/app.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/app.dart';
import 'fake_repo.dart';

void main() {}
''',
      );
    });

    test('leaves third-party packages named like doubles alone', () {
      final lines = [
        "import 'package:fake_async/fake_async.dart';",
        "import 'package:mock_web_server/mock_web_server.dart';",
        "import 'package:demo/app.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        testImports: true,
      );

      expect(
        result.sortedFile,
        '''
// Package imports:
import 'package:fake_async/fake_async.dart';
import 'package:mock_web_server/mock_web_server.dart';

// Project imports:
import 'package:demo/app.dart';

void main() {}
''',
      );
    });

    test('honors custom prefixes', () {
      final lines = [
        "import 'stub_gateway.dart';",
        "import 'fake_repo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        testImports: true,
        testImportPrefixes: const ['stub_'],
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'fake_repo.dart';

// Test imports:
import 'stub_gateway.dart';

void main() {}
''',
      );
    });

    test('writes the emoji label when emojis are on', () {
      final result = sortImports(
        ["import 'fake_repo.dart';", '', 'void main() {}'],
        'demo',
        true,
        false,
        false,
        testImports: true,
      );

      expect(
        result.sortedFile,
        '''
// 🧪 Test imports:
import 'fake_repo.dart';

void main() {}
''',
      );
    });

    test('re-running a file with a test group makes no change', () {
      const sorted = '''
// Project imports:
import 'package:demo/app.dart';

// Test imports:
import 'fake_repo.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        testImports: true,
      );

      expect(result.updated, isFalse);
    });
  });

  group('group comments inside string literals', () {
    test('are left alone (they are content, not import headers)', () {
      final lines = [
        "import 'package:demo/app.dart';",
        '',
        'const sample = \'\'\'',
        '// Dart imports:',
        "import 'dart:io';",
        '\'\'\';',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.sortedFile, contains('// Dart imports:\n'));
      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/app.dart';

const sample = \'\'\'
// Dart imports:
import 'dart:io';
\'\'\';
''',
      );
    });
  });

  group('config (#67)', () {
    test('defaults when config is null', () {
      final config = TidyConfig.fromYaml(null);
      expect(config.emojis, isFalse);
      expect(config.noComments, isFalse);
      expect(config.noBlankLines, isFalse);
      expect(config.sortPubspec, isFalse);
      expect(config.groupProjectByFolder, isFalse);
      expect(config.ignoredFiles, isEmpty);
      expect(config.customTiers, isEmpty);
      expect(config.testImports, isFalse);
      expect(config.testImportPrefixes, ['fake_', 'mock_']);
      expect(config.sortExports, isFalse);
      expect(config.removeDuplicates, isFalse);
      expect(config.removeUnused, isFalse);
      expect(config.flat, isFalse);
      expect(config.relativeImports, isFalse);
    });

    test('separate_relative_imports is the one default that is on', () {
      expect(
        TidyConfig.fromYaml(null).separateRelativeImports,
        isTrue,
        reason: 'dart format 3.13+ writes that blank line itself; off, the '
            'two tools undo each other every run (issue #1)',
      );
    });

    test('separate_relative_imports can be turned off in config', () {
      final config =
          TidyConfig.fromYaml(loadYaml('separate_relative_imports: false'));

      expect(config.separateRelativeImports, isFalse);
    });

    test('reads test import settings', () {
      final config = TidyConfig.fromYaml(
        loadYaml('''
test_imports: true
test_import_prefixes:
  - stub_
'''),
      );
      expect(config.testImports, isTrue);
      expect(config.testImportPrefixes, ['stub_']);
    });

    test('reads separate_relative_imports', () {
      final config = TidyConfig.fromYaml(
        loadYaml('separate_relative_imports: true'),
      );
      expect(config.separateRelativeImports, isTrue);
    });
  });

  group('config diagnostics', () {
    test('a standalone file wrapped in tidy_imports: still configures', () {
      final config = TidyConfig.fromStandalone(
        loadYaml('''
tidy_imports:
  emojis: true
'''),
      );

      expect(
        config.emojis,
        isTrue,
        reason: 'the envelope is the pubspec shape. Read as a standalone file '
            'it used to make every key invisible, so the whole config was '
            'discarded and the run silently fell back to defaults',
      );
    });

    test('the envelope is reported, not swallowed', () {
      final config = TidyConfig.fromStandalone(
        loadYaml('''
tidy_imports:
  emojis: true
'''),
      );

      expect(config.issues, hasLength(1));
      expect(config.issues.single, contains('tidy_imports:'));
    });

    test('a standalone file that does not parse is reported, not thrown', () {
      final temp = Directory.systemTemp.createTempSync('tidy_imports_cfg_');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}/tidy_imports.yaml')
          .writeAsStringSync('emojis: true\n  bad_indent: nope\n');

      final config =
          TidyConfig.load(temp.path, loadYaml('name: demo') as YamlMap);

      expect(
        config.issues.single,
        allOf(contains('not valid YAML'), contains('line 2')),
        reason: 'every other broken config is a sentence. This one threw a '
            'five-line YAML stack trace for a missing colon',
      );
      expect(config.emojis, isFalse, reason: 'and the run goes on');
    });

    test('a standalone file written at the top level reports nothing', () {
      final config = TidyConfig.fromStandalone(loadYaml('emojis: true'));

      expect(config.emojis, isTrue);
      expect(config.issues, isEmpty);
    });

    test('the envelope beside another key is not unwrapped', () {
      final config = TidyConfig.fromStandalone(
        loadYaml('''
tidy_imports:
  emojis: true
flat: true
'''),
      );

      expect(
        config.emojis,
        isFalse,
        reason: 'a key that sits beside real options is not an envelope; '
            'guessing which half to read would be worse than saying so',
      );
      expect(config.flat, isTrue);
      expect(config.issues.single, contains('tidy_imports'));
    });

    test('an unknown key is named, not ignored', () {
      final config = TidyConfig.fromYaml(loadYaml('banana: true'));

      expect(config.issues, hasLength(1));
      expect(config.issues.single, contains('banana'));
    });

    test('a near miss suggests the option it almost is', () {
      final config = TidyConfig.fromYaml(loadYaml('sort_export: true'));

      expect(
        config.issues.single,
        contains('sort_exports'),
        reason: 'naming the typo is a warning; naming the fix is a repair',
      );
    });

    test('every option the reader supports passes without a word', () {
      final config = TidyConfig.fromYaml(
        loadYaml('''
emojis: false
comments: true
blank_lines: true
sort_pubspec: false
group_project_by_folder: false
group_project_by_folder_depth: 0
separate_relative_imports: true
test_imports: false
test_import_prefixes:
  - fake_
ignored_files:
  - \\.g\\.dart\$
report_roots:
  - /lib/app/bootstrap.dart
tiers:
  - name: "Company imports:"
    pattern: "package:acme_"
sort_exports: false
remove_duplicates: false
remove_unused: false
flat: false
relative_imports: false
attach_comments: false
'''),
      );

      expect(
        config.issues,
        isEmpty,
        reason: 'this is the list drifting from the reader: add an option to '
            'one and not the other and a valid config starts warning',
      );
    });

    test('a boolean option given a string reports instead of crashing', () {
      final config = TidyConfig.fromYaml(loadYaml('emojis: "sim"'));

      expect(
        config.emojis,
        isFalse,
        reason: 'the cast used to throw a bare TypeError that named no key, '
            'so the one thing the user needed to know was the one thing the '
            'crash left out',
      );
      expect(config.issues.single, contains('emojis'));
      expect(config.issues.single, contains('boolean'));
    });

    test('a numeric option given a string reports instead of crashing', () {
      final config = TidyConfig.fromYaml(
        loadYaml('group_project_by_folder_depth: "two"'),
      );

      expect(config.groupProjectByFolderDepth, 0);
      expect(config.issues.single, contains('group_project_by_folder_depth'));
    });

    test('a list option given a scalar reports instead of crashing', () {
      final config = TidyConfig.fromYaml(loadYaml('ignored_files: nope'));

      expect(config.ignoredFiles, isEmpty);
      expect(config.issues.single, contains('ignored_files'));
    });

    test('a tier that is not a map reports instead of crashing', () {
      final config = TidyConfig.fromYaml(
        loadYaml('''
tiers:
  - nope
'''),
      );

      expect(config.customTiers, isEmpty);
      expect(config.issues.single, contains('tiers'));
    });

    test('a config file that is not a map at all reports', () {
      final config = TidyConfig.fromStandalone(loadYaml('hello'));

      expect(config.issues.single, contains('map'));
    });
  });
}
