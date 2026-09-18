// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:tidy_imports/graph.dart';
import 'package:tidy_imports/sort.dart';

void main() {
  group('resolveUri', () {
    test('maps the package to its own lib/', () {
      expect(
        resolveUri('package:app/src/foo.dart',
            from: 'lib/a.dart', packageName: 'app'),
        'lib/src/foo.dart',
      );
    });

    test('walks a relative path from the importing file', () {
      expect(
        resolveUri('../foo.dart',
            from: 'lib/src/p2/bar.dart', packageName: 'app'),
        'lib/src/foo.dart',
      );
    });

    test('resolves a sibling', () {
      expect(
        resolveUri('foo.dart', from: 'lib/src/bar.dart', packageName: 'app'),
        'lib/src/foo.dart',
      );
    });

    test('leaves dart: and other packages outside', () {
      expect(resolveUri('dart:io', from: 'lib/a.dart', packageName: 'app'),
          isNull);
      expect(
        resolveUri('package:http/http.dart',
            from: 'lib/a.dart', packageName: 'app'),
        isNull,
      );
    });

    test('refuses to climb above the project root', () {
      expect(
        resolveUri('../../../etc/passwd',
            from: 'lib/a.dart', packageName: 'app'),
        isNull,
      );
    });
  });

  group('cycles', () {
    test('finds a two-file cycle', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['a.dart'],
        'lib/c.dart': [],
      }, 'app');

      expect(graph.cycles(), [
        ['lib/a.dart', 'lib/b.dart']
      ]);
    });

    test('finds a cycle that goes the long way round', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['c.dart'],
        'lib/c.dart': ['a.dart'],
      }, 'app');

      expect(graph.cycles().single, hasLength(3));
    });

    test('a chain with no way back is not a cycle', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['c.dart'],
        'lib/c.dart': [],
      }, 'app');

      expect(graph.cycles(), isEmpty);
    });

    test('a file importing itself is not reported as a cycle', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['a.dart'],
      }, 'app');

      expect(graph.cycles(), isEmpty);
    });

    test('reports two separate cycles separately', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['b.dart'],
        'lib/b.dart': ['a.dart'],
        'lib/x.dart': ['y.dart'],
        'lib/y.dart': ['x.dart'],
      }, 'app');

      expect(graph.cycles(), hasLength(2));
    });

    test('follows package: uris of the project itself', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['package:app/b.dart'],
        'lib/b.dart': ['package:app/a.dart'],
      }, 'app');

      expect(graph.cycles(), hasLength(1));
    });
  });

  group('unreferenced', () {
    test('reports a file nothing imports', () {
      final graph = ImportGraph.build({
        'lib/main.dart': ['used.dart'],
        'lib/used.dart': [],
        'lib/dead.dart': [],
      }, 'app');

      expect(graph.unreferenced(roots: {'lib/main.dart'}), ['lib/dead.dart']);
    });

    test('never reports a root', () {
      final graph = ImportGraph.build({
        'lib/main.dart': [],
      }, 'app');

      expect(graph.unreferenced(roots: {'lib/main.dart'}), isEmpty);
    });

    test('a barrel keeps what it exports alive', () {
      final graph = ImportGraph.build({
        'lib/app.dart': ['src/foo.dart'],
        'lib/src/foo.dart': [],
      }, 'app');

      expect(graph.unreferenced(roots: {'lib/app.dart'}), isEmpty);
    });

    test('a part keeps its generated file alive', () {
      final graph = ImportGraph.build({
        'lib/model.dart': ['model.g.dart'],
        'lib/model.g.dart': [],
      }, 'app');

      expect(graph.unreferenced(roots: {'lib/model.dart'}), isEmpty);
    });

    test('ignores files outside lib/, which are entry points', () {
      final graph = ImportGraph.build({
        'bin/tool.dart': [],
        'test/a_test.dart': [],
      }, 'app');

      expect(graph.unreferenced(roots: const {}), isEmpty);
    });
  });

  group('directiveUris', () {
    test('reads import, export and part', () {
      final uris = directiveUris([
        "import 'dart:io';",
        "export 'src/foo.dart';",
        "part 'model.g.dart';",
        '',
        'void main() {}',
      ]);

      expect(uris, ['dart:io', 'src/foo.dart', 'model.g.dart']);
    });

    test('skips `part of`, which points the other way', () {
      expect(directiveUris(["part of 'parent.dart';"]), isEmpty);
    });

    test('does not read a directive out of a block comment', () {
      final uris = directiveUris([
        "import 'real.dart';",
        '/*',
        "import 'commented_out.dart';",
        '*/',
      ]);

      expect(uris, ['real.dart']);
    });

    test('does not read a directive out of a string', () {
      const tq = "'''";
      final uris = directiveUris([
        "import 'real.dart';",
        'void main() {',
        '  const s = $tq',
        "import 'inside_string.dart';",
        '$tq;',
        '}',
      ]);

      expect(uris, ['real.dart']);
    });
  });
}
