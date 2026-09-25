// Package imports:
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/dependencies.dart';

void main() {
  YamlMap pubspec(String yaml) => loadYaml(yaml) as YamlMap;

  final declared = pubspec('''
name: app
dependencies:
  http: ^1.0.0
  intl: any
  cupertino_icons: ^1.0.0
  flutter:
    sdk: flutter
  collection: any
dev_dependencies:
  test: any
  mocktail: any
  build_runner: any
''');

  group('unused dependencies', () {
    test('a dependency nothing imports is reported', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/a.dart': ['package:http/http.dart', 'package:intl/intl.dart'],
        },
      );

      expect(audit.unused, ['collection']);
    });

    test('an import from a test still counts as use', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/a.dart': ['package:http/http.dart', 'package:intl/intl.dart'],
          'test/a_test.dart': ['package:collection/collection.dart'],
        },
      );

      expect(audit.unused, isEmpty);
    });

    test('an export and a conditional target count as use', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          // directiveUris hands over every target of a conditional import.
          'lib/a.dart': [
            'package:http/http.dart',
            'package:intl/intl.dart',
            'package:collection/collection.dart',
          ],
        },
      );

      expect(audit.unused, isEmpty);
    });

    test('sdk packages and cupertino_icons are never reported', () {
      final audit = auditDependencies(declared, directivesByFile: const {});

      expect(audit.unused, isNot(contains('flutter')));
      expect(audit.unused, isNot(contains('cupertino_icons')));
      expect(audit.unused, ['collection', 'http', 'intl']);
    });

    test('ignored dependencies are never reported', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: const {},
        ignored: ['http', 'intl'],
      );

      expect(audit.unused, ['collection']);
    });

    test('a sub-package using a dependency does not use it for the root', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'packages/core/lib/x.dart': ['package:http/http.dart'],
          'example/main.dart': ['package:intl/intl.dart'],
        },
        otherPackages: ['packages/core', 'example'],
      );

      expect(audit.unused, containsAll(['http', 'intl']));
    });

    test('intl is not unused when flutter gen-l10n writes the code using it',
        () {
      final audit = auditDependencies(
        pubspec('''
name: app
dependencies:
  intl: any
flutter:
  generate: true
'''),
        directivesByFile: const {},
      );

      expect(
        audit.unused,
        isEmpty,
        reason: 'the generated localizations import intl from .dart_tool/, '
            'which no scan of the project sees',
      );
    });

    test('a pubspec without sections has nothing to report', () {
      final audit = auditDependencies(
        pubspec('name: app'),
        directivesByFile: {
          'lib/a.dart': ['package:http/http.dart'],
        },
      );

      expect(audit.unused, isEmpty);
      expect(audit.devOnly, isEmpty);
      expect(audit.findings, 0);
    });
  });

  group('dev-only imports', () {
    test('a dev dependency imported under lib/ is reported with its files', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/testing/b.dart': ['package:mocktail/mocktail.dart'],
          'lib/testing/a.dart': ['package:mocktail/mocktail.dart'],
          'bin/tool.dart': ['package:mocktail/mocktail.dart'],
        },
      );

      expect(audit.devOnly, {
        'mocktail': [
          'bin/tool.dart',
          'lib/testing/a.dart',
          'lib/testing/b.dart',
        ],
      });
    });

    test('a build hook runs for consumers, so it ships like lib/', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'hook/build.dart': ['package:build_runner/build_runner.dart'],
        },
      );

      expect(audit.devOnly.keys, ['build_runner']);
    });

    test('a dev dependency imported from test/ is where it belongs', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'test/a_test.dart': [
            'package:test/test.dart',
            'package:mocktail/mocktail.dart',
          ],
          'tool/gen.dart': ['package:build_runner/build_runner.dart'],
        },
      );

      expect(audit.devOnly, isEmpty);
    });

    test('a package in both sections is a real dependency', () {
      final audit = auditDependencies(
        pubspec('''
name: app
dependencies:
  meta: any
dev_dependencies:
  meta: any
'''),
        directivesByFile: {
          'lib/a.dart': ['package:meta/meta.dart'],
        },
      );

      expect(audit.devOnly, isEmpty);
    });

    test('the package itself and undeclared packages are left alone', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/a.dart': [
            'package:app/src/b.dart',
            'package:undeclared/x.dart',
            'dart:io',
            'b.dart',
          ],
        },
      );

      expect(audit.devOnly, isEmpty);
    });

    test('findings count each dev-only package once, and no unused one', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/a.dart': ['package:mocktail/mocktail.dart'],
          'lib/b.dart': ['package:mocktail/mocktail.dart'],
        },
      );

      expect(audit.unused, hasLength(3));
      expect(
        audit.findings,
        1,
        reason: 'an unused dependency is a warning: a font or a plugin is used '
            'without an import, so failing a build on it would cry wolf',
      );
    });

    test('toJson names the package and its files', () {
      final audit = auditDependencies(
        declared,
        directivesByFile: {
          'lib/a.dart': ['package:mocktail/mocktail.dart'],
        },
      );

      expect(audit.toJson()['devOnly'], [
        {
          'package': 'mocktail',
          'files': ['lib/a.dart'],
        },
      ]);
    });
  });
}
