// Package imports:
import 'package:test/test.dart';

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

  group('config (#67)', () {
    test('defaults when config is null', () {
      final config = TidyConfig.fromYaml(null);
      expect(config.emojis, isFalse);
      expect(config.noComments, isFalse);
      expect(config.noBlankLines, isFalse);
      expect(config.sortPubspec, isFalse);
      expect(config.ignoredFiles, isEmpty);
      expect(config.customTiers, isEmpty);
    });
  });
}
