// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:tidy_imports/graph.dart';
import 'package:tidy_imports/graph_export.dart';
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

  group('metrics', () {
    // lib/features/auth and lib/features/home both lean on lib/core; home
    // also reaches into auth. test/ imports home, which counts as fan-in but
    // takes no part in feature coupling.
    final graph = ImportGraph.build(
      {
        'lib/core/theme.dart': [],
        'lib/core/api.dart': ['theme.dart'],
        'lib/features/auth/login.dart': [
          'package:app/core/api.dart',
          'package:app/core/theme.dart',
        ],
        'lib/features/home/home.dart': [
          'package:app/core/theme.dart',
          '../auth/login.dart',
        ],
        'lib/src/util.dart': [],
        'lib/main.dart': ['features/home/home.dart', 'src/util.dart'],
        'test/home_test.dart': ['package:app/features/home/home.dart'],
      },
      'app',
    );

    test('fan-in counts every importer, tests included', () {
      final fanIn = graph.fanIn();

      expect(fanIn['lib/core/theme.dart'], 3);
      expect(fanIn['lib/features/home/home.dart'], 2);
      expect(fanIn['lib/main.dart'], 0);
    });

    test('fan-out counts distinct project imports', () {
      expect(graph.fanOut()['lib/features/auth/login.dart'], 2);
      expect(graph.fanOut()['lib/core/theme.dart'], 0);
    });

    test('featureOf cuts the path under lib/ to the depth', () {
      expect(
        graph.featureOf('lib/features/auth/login.dart', 1),
        'lib/features',
      );
      expect(
        graph.featureOf('lib/features/auth/login.dart', 2),
        'lib/features/auth',
      );
      expect(graph.featureOf('lib/main.dart', 1), 'lib');
      expect(graph.featureOf('test/home_test.dart', 1), isNull);
    });

    test('featureOf looks through lib/src/', () {
      expect(graph.featureOf('lib/src/auth/x.dart', 1), 'lib/src/auth');
      expect(graph.featureOf('lib/src/util.dart', 1), 'lib/src');
    });

    test('featureOf names a sub-package feature by its real path', () {
      const monorepo = ImportGraph(
        {'packages/core/lib/net/http.dart': {}},
        packages: {'': 'app', 'packages/core': 'core'},
      );

      expect(
        monorepo.featureOf('packages/core/lib/net/http.dart', 1),
        'packages/core/lib/net',
      );
    });

    test('features count crossing imports as afferent and efferent', () {
      final features = {for (final f in graph.features(2)) f.name: f};

      final core = features['lib/core']!;
      expect(core.files, 2);
      expect(core.afferent, 3, reason: 'auth twice, home once');
      expect(core.efferent, 0);
      expect(core.instability, 0);

      final home = features['lib/features/home']!;
      expect(home.afferent, 1, reason: 'main; the test is not a feature');
      expect(home.efferent, 2);
      expect(home.instability, closeTo(2 / 3, 1e-9));
    });

    test('a feature with no crossing edge has no instability', () {
      const lonely = ImportGraph({'lib/a/x.dart': {}});

      expect(lonely.features(1).single.instability, isNull);
    });

    test('coupling lists feature pairs, heaviest first', () {
      final pairs = graph.coupling(2);

      expect(pairs.first.from, 'lib/features/auth');
      expect(pairs.first.to, 'lib/core');
      expect(pairs.first.edges, 2);
      expect(
        pairs.map((p) => '${p.from}>${p.to}'),
        containsAll([
          'lib/features/home>lib/core',
          'lib/features/home>lib/features/auth',
          'lib>lib/features/home',
          'lib>lib/src',
        ]),
      );
    });
  });

  group('exports', () {
    final graph = ImportGraph.build(
      {
        'lib/a/x.dart': ['../b/y.dart'],
        'lib/b/y.dart': ['../a/x.dart', 'z.dart'],
        'lib/b/z.dart': [],
        'lib/dead.dart': [],
      },
      'app',
    );
    final nodes = graph.edges.keys;

    test('Mermaid boxes features, reds cycles and dashes dead files', () {
      expect(
        toMermaid(graph, nodes: nodes, unreachable: {'lib/dead.dart'}),
        'flowchart LR\n'
        '  subgraph f0["lib"]\n'
        '    n3["dead.dart"]\n'
        '  end\n'
        '  subgraph f1["lib/a"]\n'
        '    n0["x.dart"]\n'
        '  end\n'
        '  subgraph f2["lib/b"]\n'
        '    n1["y.dart"]\n'
        '    n2["z.dart"]\n'
        '  end\n'
        '  n0 --> n1\n'
        '  n1 --> n0\n'
        '  n1 --> n2\n'
        '  linkStyle 0,1 stroke:#d33,stroke-width:2px\n'
        '  classDef dead stroke-dasharray:4 4,color:#888\n'
        '  class n3 dead\n',
      );
    });

    test('Mermaid draws only the nodes asked for, and their edges', () {
      final drawn = toMermaid(graph, nodes: ['lib/b/y.dart', 'lib/b/z.dart']);

      expect(drawn, contains('n0 --> n1'));
      expect(drawn, isNot(contains('x.dart')));
      expect(drawnEdges(graph, ['lib/b/y.dart', 'lib/b/z.dart']), 1);
    });

    test('Mermaid escapes a quote in a label', () {
      const quoted = ImportGraph({'lib/say "hi".dart': {}});

      expect(
        toMermaid(quoted, nodes: quoted.edges.keys),
        contains('["say #quot;hi#quot;.dart"]'),
      );
    });

    test('DOT clusters features and colours cycle edges', () {
      final dot = toDot(graph, nodes: nodes, unreachable: {'lib/dead.dart'});

      expect(dot, startsWith('digraph imports {\n  rankdir=LR;\n'));
      expect(dot, contains('subgraph "cluster_2" {\n    label="lib/b";\n'));
      expect(
        dot,
        contains(
          '"lib/a/x.dart" -> "lib/b/y.dart" [color="#dd3333", penwidth=2];',
        ),
      );
      expect(dot, contains('"lib/b/y.dart" -> "lib/b/z.dart";'));
      expect(
        dot,
        contains('"lib/dead.dart" [label="dead.dart", '
            'style="rounded,dashed", fontcolor="#888888"];'),
      );
      expect(dot.trimRight(), endsWith('}'));
    });

    test('DOT escapes quotes and backslashes', () {
      const odd = ImportGraph({r'lib/a"b\c.dart': {}});

      expect(
        toDot(odd, nodes: odd.edges.keys),
        contains(r'"lib/a\"b\\c.dart"'),
      );
    });

    test('JSON carries files, cycles, metrics and a schema version', () {
      final report = jsonDecode(
        jsonEncode(
          reportJson(
            graph,
            packageName: 'app',
            files: nodes,
            cycles: graph.cycles(),
            unreachable: ['lib/dead.dart'],
          ),
        ),
      ) as Map<String, Object?>;

      expect(report['schemaVersion'], reportSchemaVersion);
      expect(report['package'], 'app');
      expect(report['cycles'], [
        ['lib/a/x.dart', 'lib/b/y.dart'],
      ]);
      expect(report['unreachable'], ['lib/dead.dart']);
      expect(report.containsKey('dependencies'), isFalse);

      final files = (report['files'] as List).cast<Map<String, Object?>>();
      final y = files.firstWhere((f) => f['path'] == 'lib/b/y.dart');
      expect(y['imports'], ['lib/a/x.dart', 'lib/b/z.dart']);
      expect(y['importedBy'], 1);
      expect(y['feature'], 'lib/b');
      expect(y['cycle'], 0);
      expect(
        files.firstWhere((f) => f['path'] == 'lib/b/z.dart')['cycle'],
        isNull,
      );

      final metrics = report['metrics'] as Map<String, Object?>;
      expect(
        (metrics['mostImported'] as List).first,
        {'path': 'lib/a/x.dart', 'count': 1},
      );
      expect(metrics['features'] as List, hasLength(3));
    });

    test('JSON lists only the files in scope', () {
      final report = reportJson(
        graph,
        packageName: 'app',
        files: ['lib/b/z.dart'],
        cycles: const [],
        unreachable: ['lib/dead.dart'],
      );

      expect(report['files'] as List, hasLength(1));
      expect(report['unreachable'], isEmpty);
    });
  });
}
