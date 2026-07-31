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
  });
}
