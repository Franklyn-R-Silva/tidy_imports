// Package imports:
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/config.dart';
import 'package:tidy_imports/config_edit.dart';
import 'package:tidy_imports/doctor.dart';

void main() {
  group('readLints', () {
    LintState lintsOf(
      Map<String, String> files, {
      Map<String, String> packages = const {},
    }) =>
        readLints(
          '/p/analysis_options.yaml',
          read: (path) => files[path],
          packageDir: (name) => packages[name],
        );

    test('reads a list of rules', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': '''
linter:
  rules:
    - directives_ordering
    - prefer_relative_imports
''',
      });

      expect(lints.has('directives_ordering'), isTrue);
      expect(lints.has('prefer_relative_imports'), isTrue);
      expect(lints.enabled['directives_ordering'], 'analysis_options.yaml');
    });

    test('reads a map of rules, false switching one off', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': '''
linter:
  rules:
    directives_ordering: true
    always_use_package_imports: false
''',
      });

      expect(lints.has('directives_ordering'), isTrue);
      expect(lints.has('always_use_package_imports'), isFalse);
    });

    test('follows a package: include and names it as the source', () {
      final lints = lintsOf(
        {
          '/p/analysis_options.yaml':
              'include: package:strict/analysis_options.yaml\n',
          '/cache/strict/lib/analysis_options.yaml': '''
linter:
  rules:
    - always_use_package_imports
''',
        },
        packages: {'strict': '/cache/strict/lib'},
      );

      expect(
        lints.enabled['always_use_package_imports'],
        'package:strict/analysis_options.yaml',
        reason: 'a rule nobody wrote in the project file has to say where it '
            'came from, or the finding sends the reader hunting',
      );
    });

    test('the including file wins over what it includes', () {
      final lints = lintsOf(
        {
          '/p/analysis_options.yaml': '''
include: package:strict/all.yaml
linter:
  rules:
    directives_ordering: false
''',
          '/cache/strict/lib/all.yaml': '''
linter:
  rules:
    - directives_ordering
''',
        },
        packages: {'strict': '/cache/strict/lib'},
      );

      expect(lints.has('directives_ordering'), isFalse);
    });

    test('a list of includes merges in order, the later one winning', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': '''
include:
  - base.yaml
  - ../team/override.yaml
''',
        '/p/base.yaml': 'linter:\n  rules:\n    - directives_ordering\n',
        '/team/override.yaml':
            'linter:\n  rules:\n    directives_ordering: false\n',
      });

      expect(lints.has('directives_ordering'), isFalse);
    });

    test('an include of an include is followed', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': 'include: a.yaml\n',
        '/p/a.yaml': 'include: nested/b.yaml\n',
        '/p/nested/b.yaml': 'linter:\n  rules:\n    - directives_ordering\n',
      });

      expect(lints.has('directives_ordering'), isTrue);
    });

    test('analyzer errors: ignore switches a rule off', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': '''
analyzer:
  errors:
    directives_ordering: ignore
linter:
  rules:
    - directives_ordering
''',
      });

      expect(lints.has('directives_ordering'), isFalse);
    });

    test('an include that does not resolve is a problem, not a crash', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': '''
include: package:very_good_analysis/analysis_options.yaml
linter:
  rules:
    - directives_ordering
''',
      });

      expect(lints.has('directives_ordering'), isTrue);
      expect(lints.problems.single, contains('dart pub get'));
    });

    test('an include cycle is read once and reported', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': 'include: a.yaml\n',
        '/p/a.yaml': 'include: analysis_options.yaml\n'
            'linter:\n  rules:\n    - directives_ordering\n',
      });

      expect(lints.has('directives_ordering'), isTrue);
      expect(lints.problems.single, contains('includes itself'));
    });

    test('a file that does not parse is a problem, not a crash', () {
      final lints = lintsOf({
        '/p/analysis_options.yaml': 'linter:\n  rules:\n - bad: [\n',
      });

      expect(lints.enabled, isEmpty);
      expect(lints.problems.single, contains('not valid YAML'));
    });

    test('Windows paths are followed like any other', () {
      final lints = readLints(
        r'C:\p\analysis_options.yaml',
        read: (path) => {
          'C:/p/analysis_options.yaml': r'include: ..\shared\o.yaml',
          'C:/shared/o.yaml': 'linter:\n  rules:\n    - directives_ordering\n',
        }[path],
        packageDir: (_) => null,
      );

      expect(lints.has('directives_ordering'), isTrue);
    });
  });

  group('diagnose', () {
    const none = TidyConfig(
      emojis: false,
      noComments: false,
      noBlankLines: false,
      sortPubspec: false,
      groupProjectByFolder: false,
      ignoredFiles: [],
      customTiers: [],
    );

    LintState on(List<String> rules) =>
        LintState({for (final rule in rules) rule: 'analysis_options.yaml'});

    TidyConfig config(String yaml) => TidyConfig.fromYaml(loadYaml(yaml));

    List<DoctorFinding> check(
      LintState lints, [
      TidyConfig config = none,
      bool formatterSeparates = true,
    ]) =>
        diagnose(lints, config, formatterSeparates: formatterSeparates);

    test('nothing on, nothing to say', () {
      expect(check(on([])), isEmpty);
    });

    test('the two import-style lints together are a conflict', () {
      final findings =
          check(on(['prefer_relative_imports', 'always_use_package_imports']));

      expect(findings.single.kind, FindingKind.conflict);
      expect(findings.single.fix, isEmpty);
    });

    test('prefer_relative_imports suggests relative_imports', () {
      final finding = check(on(['prefer_relative_imports'])).single;

      expect(finding.kind, FindingKind.suggestion);
      expect(finding.fix, {'relative_imports': true});
    });

    test('prefer_relative_imports fights package_imports', () {
      final finding = check(
        on(['prefer_relative_imports']),
        config('package_imports: true'),
      ).single;

      expect(finding.kind, FindingKind.fight);
      expect(finding.fix, {'package_imports': false, 'relative_imports': true});
    });

    test('prefer_relative_imports with relative_imports is settled', () {
      expect(
        check(
            on(['prefer_relative_imports']), config('relative_imports: true')),
        isEmpty,
      );
    });

    test('always_use_package_imports suggests package_imports', () {
      final finding = check(on(['always_use_package_imports'])).single;

      expect(finding.kind, FindingKind.suggestion);
      expect(finding.fix, {'package_imports': true});
    });

    test('always_use_package_imports fights relative_imports', () {
      final finding = check(
        on(['always_use_package_imports']),
        config('relative_imports: true'),
      ).single;

      expect(finding.kind, FindingKind.fight);
      expect(finding.fix, {'relative_imports': false, 'package_imports': true});
    });

    test('directives_ordering fights the grouped output', () {
      final finding = check(on(['directives_ordering'])).single;

      expect(finding.kind, FindingKind.fight);
      expect(finding.fix, {'flat': true, 'sort_exports': true});
    });

    test('directives_ordering under flat still wants sort_exports', () {
      final finding =
          check(on(['directives_ordering']), config('flat: true')).single;

      expect(finding.kind, FindingKind.suggestion);
      expect(finding.fix, {'sort_exports': true});
    });

    test('directives_ordering is settled by flat and sort_exports', () {
      expect(
        check(
          on(['directives_ordering']),
          config('flat: true\nsort_exports: true'),
        ),
        isEmpty,
      );
    });

    test('grouping options under directives_ordering earn a note', () {
      final findings = check(
        on(['directives_ordering']),
        config('flat: true\nsort_exports: true\ntest_imports: true'),
      );

      expect(findings.single.kind, FindingKind.note);
      expect(findings.single.message, contains('`test_imports`'));
    });

    test('separate_relative_imports off fights dart format 3.13+', () {
      final finding =
          check(on([]), config('separate_relative_imports: false')).single;

      expect(finding.kind, FindingKind.fight);
      expect(finding.fix, {'separate_relative_imports': true});
    });

    test('an older formatter does not separate, so there is no fight', () {
      expect(
        check(on([]), config('separate_relative_imports: false'), false),
        isEmpty,
      );
    });

    test('without blank lines there is nothing for the formatter to undo', () {
      expect(
        check(
          on([]),
          config('separate_relative_imports: false\nblank_lines: false'),
        ),
        isEmpty,
      );
    });

    test('findings come worst first', () {
      final findings = check(
        on(['always_use_package_imports', 'directives_ordering']),
      );

      expect(
        findings.map((f) => f.kind),
        [FindingKind.fight, FindingKind.suggestion],
      );
    });

    test('fixesOf merges fights and suggestions, never notes', () {
      final fixes = fixesOf(const [
        DoctorFinding(FindingKind.fight, '', {'flat': true}),
        DoctorFinding(FindingKind.suggestion, '', {'package_imports': true}),
        DoctorFinding(FindingKind.note, '', {'emojis': true}),
      ]);

      expect(fixes, {'flat': true, 'package_imports': true});
    });
  });

  group('setConfigKeys', () {
    test('opens a block at the end of a pubspec that has none', () {
      expect(
        setConfigKeys(
          'name: demo\n\ndependencies:\n  args: any\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\n\ndependencies:\n  args: any\n\n'
        'tidy_imports:\n  flat: true\n',
      );
    });

    test('adds to an existing block at its own indentation', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports:\n    emojis: false\nflutter:\n  x: 1\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\ntidy_imports:\n    emojis: false\n    flat: true\n'
        'flutter:\n  x: 1\n',
      );
    });

    test('replaces a value in place and keeps its comment', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports:\n  flat: false # for now\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\ntidy_imports:\n  flat: true # for now\n',
      );
    });

    test('never touches a same-named key nested deeper', () {
      final edited = setConfigKeys(
        'name: demo\ntidy_imports:\n  tiers:\n    - name: x\n'
        '      flat: false\n',
        {'flat': true},
        standalone: false,
      )!;

      expect(edited, contains('      flat: false\n'));
      expect(edited, endsWith('  flat: true\n'));
    });

    test('an empty block is filled', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports:\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\ntidy_imports:\n  flat: true\n',
      );
    });

    test('a standalone file takes top-level keys', () {
      expect(
        setConfigKeys(
          'emojis: true\nflat: false\n',
          {'flat': true, 'sort_exports': true},
          standalone: true,
        ),
        'emojis: true\nflat: true\nsort_exports: true\n',
      );
    });

    test('a standalone file in the pubspec shape is edited inside the key', () {
      expect(
        setConfigKeys(
          'tidy_imports:\n  emojis: true\n',
          {'flat': true},
          standalone: true,
        ),
        'tidy_imports:\n  emojis: true\n  flat: true\n',
      );
    });

    test('keeps CRLF line endings', () {
      expect(
        setConfigKeys(
          'name: demo\r\ntidy_imports:\r\n  emojis: true\r\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\r\ntidy_imports:\r\n  emojis: true\r\n  flat: true\r\n',
      );
    });

    test('refuses a flow-style block', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports: {emojis: true}\n',
          {'flat': true},
          standalone: false,
        ),
        isNull,
      );
    });

    test('refuses a key whose value is a nested block', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports:\n  flat:\n    nested: 1\n',
          {'flat': true},
          standalone: false,
        ),
        isNull,
      );
    });

    test('refuses tab indentation', () {
      expect(
        setConfigKeys(
          'name: demo\ntidy_imports:\n\temojis: true\n',
          {'flat': true},
          standalone: false,
        ),
        isNull,
      );
    });

    test('the dev_dependencies entry is not mistaken for the block', () {
      expect(
        setConfigKeys(
          'name: demo\ndev_dependencies:\n  tidy_imports: ^2.6.0\n',
          {'flat': true},
          standalone: false,
        ),
        'name: demo\ndev_dependencies:\n  tidy_imports: ^2.6.0\n\n'
        'tidy_imports:\n  flat: true\n',
      );
    });
  });
}
