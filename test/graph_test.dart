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

  group('resolveUri edge cases', () {
    String? r(String uri, {String from = 'lib/a.dart'}) =>
        resolveUri(uri, from: from, packageName: 'app');

    test('a leading slash is relative to the package lib/', () {
      // FlutterFlow barrels are written this way, and Dart resolves them
      // against the importing package's root.
      expect(
          r('/features/b.dart', from: 'lib/index.dart'), 'lib/features/b.dart');
      expect(r('/b.dart', from: 'lib/src/deep/a.dart'), 'lib/b.dart');
    });

    test('a leading slash outside any lib/ has no root to resolve against', () {
      expect(r('/b.dart', from: 'test/a_test.dart'), isNull);
    });

    test('a leading slash resolves inside its own sub-package', () {
      expect(
        resolveUri('/b.dart',
            from: 'packages/core/lib/a.dart',
            packageName: 'app',
            packages: {'packages/core': 'core'}),
        'packages/core/lib/b.dart',
      );
    });

    test('dot and empty segments are ignored in both forms', () {
      expect(r('./b.dart'), 'lib/b.dart');
      expect(r('x//b.dart'), 'lib/x/b.dart');
      expect(r('package:app/./b.dart'), 'lib/b.dart');
    });

    test('a package whose name merely starts the same is not ours', () {
      expect(r('package:app_core/b.dart'), isNull);
    });

    test('climbing exactly to the root is nothing', () {
      expect(r('..', from: 'lib/a.dart'), isNull);
    });

    test('a package uri walks .. the same way a relative one does', () {
      expect(r('package:app/../x.dart'), 'x.dart');
    });

    test('resolves a sub-package through its directory', () {
      expect(
        resolveUri('package:core/b.dart',
            from: 'lib/a.dart',
            packageName: 'app',
            packages: {'packages/core': 'core'}),
        'packages/core/lib/b.dart',
      );
    });
  });

  group('cycleWalk', () {
    test('follows edges that exist', () {
      final graph = ImportGraph.build({
        'lib/a.dart': ['c.dart'],
        'lib/b.dart': ['a.dart'],
        'lib/c.dart': ['b.dart'],
      }, 'app');

      final walk = graph.cycleWalk(graph.cycles().single);

      expect(walk, ['lib/a.dart', 'lib/c.dart', 'lib/b.dart']);
      for (var i = 0; i < walk.length; i++) {
        final next = walk[(i + 1) % walk.length];
        expect(graph.edges[walk[i]], contains(next),
            reason: '${walk[i]} must really import $next');
      }
    });

    test('takes the shortest way round a bigger group', () {
      final graph = ImportGraph.build({
        'lib/x.dart': ['y.dart', 'z.dart'],
        'lib/y.dart': ['x.dart'],
        'lib/z.dart': ['x.dart'],
      }, 'app');

      expect(
          graph.cycleWalk(graph.cycles().single), ['lib/x.dart', 'lib/y.dart']);
    });
  });

  group('unreachable', () {
    test('sees through a dead barrel', () {
      final graph = ImportGraph.build({
        'lib/main.dart': [],
        'lib/barrel.dart': ['inner.dart'],
        'lib/inner.dart': [],
      }, 'app');

      expect(graph.unreachable(roots: {'lib/main.dart'}),
          ['lib/barrel.dart', 'lib/inner.dart']);
    });

    test('reports a dead pair that only imports itself', () {
      final graph = ImportGraph.build({
        'lib/main.dart': [],
        'lib/p.dart': ['q.dart'],
        'lib/q.dart': ['p.dart'],
      }, 'app');

      expect(graph.unreachable(roots: {'lib/main.dart'}),
          ['lib/p.dart', 'lib/q.dart']);
    });

    test('a file outside lib/ is an entry point by nature', () {
      final graph = ImportGraph.build({
        'test/a_test.dart': ['package:app/only_tested.dart'],
        'lib/only_tested.dart': [],
      }, 'app');

      expect(graph.unreachable(roots: const {}), isEmpty);
    });

    test('knows the lib/ of a sub-package', () {
      final graph = ImportGraph.build(
          {
            'lib/main.dart': [],
            'packages/core/lib/core.dart': [],
            'packages/core/lib/src/dead.dart': [],
          },
          'app',
          packages: {'packages/core': 'core'});

      expect(graph.libraryRoot('packages/core/lib/src/dead.dart'),
          'packages/core/lib/');
      expect(
        graph.unreachable(
            roots: {'lib/main.dart', 'packages/core/lib/core.dart'}),
        ['packages/core/lib/src/dead.dart'],
      );
    });
  });

  group('a graph built by hand', () {
    test('treats a target that is not a node as a leaf', () {
      const graph = ImportGraph({
        'lib/a.dart': {'lib/missing.dart'},
      });

      expect(graph.cycles(), isEmpty);
    });
  });

  group('declaresMain', () {
    test('recognises the usual shapes', () {
      expect(declaresMain(['void main() {}']), isTrue);
      expect(declaresMain(['Future<void> main() async {}']), isTrue);
      expect(declaresMain(['main(List<String> args) {}']), isTrue);
      expect(declaresMain(['dynamic main() {}']), isTrue);
    });

    test('ignores a main in a comment, a string, or a class', () {
      expect(declaresMain(['// void main() {}']), isFalse);
      expect(declaresMain(['/*', 'void main() {}', '*/']), isFalse);
      expect(declaresMain(['class A {', '  void main() {}', '}']), isFalse);
      expect(declaresMain(['void mainly() {}']), isFalse);
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

    test('reads every target of a conditional directive', () {
      final uris = directiveUris([
        "import 'stub.dart'",
        "    if (dart.library.io) 'io.dart'",
        "    if (dart.library.html) 'web.dart';",
      ]);

      expect(uris, ['stub.dart', 'io.dart', 'web.dart']);
    });

    test('reads a uri on the line after the keyword', () {
      expect(directiveUris(['import', "    'src/a.dart';"]), ['src/a.dart']);
    });

    test('reads two directives on one line', () {
      expect(
        directiveUris(["import 'a.dart'; import 'b.dart';"]),
        ['a.dart', 'b.dart'],
      );
    });

    test('does not read a quoted path out of a trailing comment', () {
      expect(
        directiveUris(["import 'a.dart'; // see 'b.dart'"]),
        ['a.dart'],
      );
    });

    test('survives a show clause longer than the old 24-line bound', () {
      final uris = directiveUris([
        "export 'src/big.dart'",
        '    show',
        for (var i = 1; i <= 30; i++) '        A$i,',
        '        Z;',
      ]);

      expect(uris, ['src/big.dart']);
    });

    test('gives up on a directive that runs into the next one', () {
      final uris = directiveUris([
        "import 'broken.dart'",
        "import 'fine.dart';",
      ]);

      expect(uris, ['fine.dart']);
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
