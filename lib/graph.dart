/// The project's own import graph, built from the directives the sorter
/// already reads on every run.
///
/// Nodes are project files, named by their path from the project root with
/// `/` separators (`lib/src/foo.dart`). Edges point from a file to the project
/// files it depends on — `import`, `export` and `part` all count, since all
/// three create a reason for a file to exist.
///
/// `dart:` URIs and other packages are not nodes: they are outside the project
/// and nothing here can say anything useful about them.
class ImportGraph {
  /// File -> the project files it depends on.
  final Map<String, Set<String>> edges;

  const ImportGraph(this.edges);

  /// Builds a graph from [directivesByFile], a map of project-relative file
  /// path to the raw URIs that file declares.
  ///
  /// [packageName] resolves `package:<packageName>/x.dart` to `lib/x.dart`.
  /// A URI that does not resolve to a file in [directivesByFile] is dropped:
  /// it points outside the project, or at something that is not there.
  factory ImportGraph.build(
    Map<String, List<String>> directivesByFile,
    String packageName,
  ) {
    final files = directivesByFile.keys.toSet();
    final edges = <String, Set<String>>{};

    for (final entry in directivesByFile.entries) {
      final from = entry.key;
      final targets = <String>{};
      for (final uri in entry.value) {
        final resolved = resolveUri(uri, from: from, packageName: packageName);
        // A self-edge is a file parting or importing itself: not a dependency,
        // and it would show up as a one-file cycle.
        if (resolved != null && resolved != from && files.contains(resolved)) {
          targets.add(resolved);
        }
      }
      edges[from] = targets;
    }
    return ImportGraph(edges);
  }

  /// Every group of files that depend on each other, directly or through
  /// others. Each group is reported once, sorted, longest first.
  ///
  /// Dart allows import cycles, so nothing in the toolchain surfaces them —
  /// but a cycle means two files cannot be understood, tested or moved apart.
  List<List<String>> cycles() {
    final components = _stronglyConnected();
    final found = components.where((c) => c.length > 1).toList()
      ..forEach((c) => c.sort())
      ..sort((a, b) {
        final bySize = b.length.compareTo(a.length);
        return bySize != 0 ? bySize : a.first.compareTo(b.first);
      });
    return found;
  }

  /// Files under `lib/` that nothing else in the project refers to.
  ///
  /// [roots] are never reported: entry points exist to be unreferenced. This
  /// is in-degree zero, not reachability — a pair of dead files that import
  /// each other survives it. That is deliberate for a first pass: a report
  /// people stop trusting is worse than one that misses something.
  List<String> unreferenced({required Set<String> roots}) {
    final referenced = <String>{};
    for (final targets in edges.values) {
      referenced.addAll(targets);
    }

    final orphans = edges.keys
        .where((file) =>
            file.startsWith('lib/') &&
            !referenced.contains(file) &&
            !roots.contains(file))
        .toList()
      ..sort();
    return orphans;
  }

  /// Tarjan's strongly connected components, iterative so a deep project
  /// cannot overflow the stack.
  List<List<String>> _stronglyConnected() {
    final index = <String, int>{};
    final low = <String, int>{};
    final onStack = <String>{};
    final stack = <String>[];
    final components = <List<String>>[];
    var counter = 0;

    for (final root in edges.keys) {
      if (index.containsKey(root)) continue;

      // Each frame is a node plus how many of its edges have been walked.
      final work = <List<Object>>[
        [root, 0]
      ];
      index[root] = low[root] = counter++;
      stack.add(root);
      onStack.add(root);

      while (work.isNotEmpty) {
        final frame = work.last;
        final node = frame[0] as String;
        final next = frame[1] as int;
        final targets = edges[node]!.toList()..sort();

        if (next < targets.length) {
          frame[1] = next + 1;
          final child = targets[next];
          if (!index.containsKey(child)) {
            index[child] = low[child] = counter++;
            stack.add(child);
            onStack.add(child);
            work.add([child, 0]);
          } else if (onStack.contains(child)) {
            low[node] = low[node]! < index[child]! ? low[node]! : index[child]!;
          }
          continue;
        }

        work.removeLast();
        if (work.isNotEmpty) {
          final parent = work.last[0] as String;
          low[parent] = low[parent]! < low[node]! ? low[parent]! : low[node]!;
        }

        if (low[node] == index[node]) {
          final component = <String>[];
          String popped;
          do {
            popped = stack.removeLast();
            onStack.remove(popped);
            component.add(popped);
          } while (popped != node);
          components.add(component);
        }
      }
    }
    return components;
  }
}

/// The project file [uri] points at, or null when it points outside.
///
/// Handles the three forms a project file can be named by: its own package's
/// `package:` URI, a relative path, and a root-relative one.
String? resolveUri(
  String uri, {
  required String from,
  required String packageName,
}) {
  if (uri.startsWith('dart:')) return null;

  final own = 'package:$packageName/';
  if (uri.startsWith(own)) return 'lib/${uri.substring(own.length)}';
  if (uri.startsWith('package:')) return null;
  if (uri.startsWith('http:') || uri.startsWith('https:')) return null;

  // Relative to the directory holding the importing file.
  final parts = from.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '.' || segment.isEmpty) continue;
    if (segment == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.isEmpty ? null : parts.join('/');
}
