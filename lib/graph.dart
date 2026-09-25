/// The project's own import graph, built from the directives the sorter
/// already reads on every run.
///
/// Nodes are project files, named by their path from the project root with
/// `/` separators (`lib/src/foo.dart`). Edges point from a file to the project
/// files it depends on — `import`, `export` and `part` all count, since all
/// three create a reason for a file to exist.
///
/// `dart:` URIs and packages outside the project are not nodes: nothing here
/// can say anything useful about them.
class ImportGraph {
  /// File -> the project files it depends on.
  ///
  /// [ImportGraph.build] guarantees every target is also a key. A graph made
  /// by hand need not: a target that is not a key is treated as a leaf.
  final Map<String, Set<String>> edges;

  /// Package directory -> package name, for every package the graph spans.
  /// The root package lives at `''`.
  final Map<String, String> packages;

  const ImportGraph(this.edges, {this.packages = const {'': ''}});

  /// Builds a graph from [directivesByFile], a map of project-relative file
  /// path to the raw URIs that file declares.
  ///
  /// [packageName] resolves `package:<packageName>/x.dart` to `lib/x.dart`.
  /// [packages] does the same for sub-packages of a monorepo: a directory
  /// (`packages/core`) mapped to the name its own pubspec declares, so
  /// `package:core/x.dart` resolves to `packages/core/lib/x.dart`.
  ///
  /// A URI that does not resolve to a file in [directivesByFile] is dropped:
  /// it points outside the project, or at something that is not there.
  factory ImportGraph.build(
    Map<String, List<String>> directivesByFile,
    String packageName, {
    Map<String, String> packages = const {},
  }) {
    final files = directivesByFile.keys.toSet();
    final edges = <String, Set<String>>{};

    for (final entry in directivesByFile.entries) {
      final from = entry.key;
      final targets = <String>{};
      for (final uri in entry.value) {
        final resolved = resolveUri(
          uri,
          from: from,
          packageName: packageName,
          packages: packages,
        );
        // A self-edge is a file parting or importing itself: not a dependency,
        // and it would show up as a one-file cycle.
        if (resolved != null && resolved != from && files.contains(resolved)) {
          targets.add(resolved);
        }
      }
      edges[from] = targets;
    }
    return ImportGraph(edges, packages: {'': packageName, ...packages});
  }

  /// Every group of files that depend on each other, directly or through
  /// others — the strongly connected components with more than one member.
  /// Each group is sorted; groups come largest first.
  ///
  /// A group is the right unit for "these files cannot be separated", but it
  /// is not itself a path: see [cycleWalk] for arrows that follow real edges.
  ///
  /// Dart allows import cycles, so nothing in the toolchain surfaces them —
  /// but two files in one cannot be understood, tested or moved apart.
  List<List<String>> cycles() {
    final found = _stronglyConnected().where((c) => c.length > 1).toList()
      ..forEach((c) => c.sort())
      ..sort((a, b) {
        final bySize = b.length.compareTo(a.length);
        return bySize != 0 ? bySize : a.first.compareTo(b.first);
      });
    return found;
  }

  /// A shortest closed walk through [group] starting at its first member,
  /// following only edges that exist. The last element points back to the
  /// first.
  ///
  /// Sorting a group alphabetically and drawing arrows between neighbours
  /// used to claim imports that no file declares; a developer following those
  /// arrows to decide which import to cut opened the wrong file. In a group of
  /// two or more, a walk back to any member always exists.
  List<String> cycleWalk(List<String> group) {
    if (group.isEmpty) return const [];
    final members = group.toSet();
    final start = group.first;

    final parent = <String, String>{};
    final queue = <String>[start];
    var head = 0;
    while (head < queue.length) {
      final node = queue[head++];
      final targets = (edges[node] ?? const <String>{}).toList()..sort();
      for (final next in targets) {
        if (!members.contains(next)) continue;
        if (next == start) {
          final walk = <String>[];
          for (String? at = node; at != null; at = parent[at]) {
            walk.add(at);
          }
          return walk.reversed.toList();
        }
        if (parent.containsKey(next)) continue;
        parent[next] = node;
        queue.add(next);
      }
    }
    return [start];
  }

  /// Library files that nothing in the project refers to: in-degree zero over
  /// [edges], with [roots] exempt.
  ///
  /// One layer deep on purpose — a file kept alive only by another dead file
  /// is not listed. [unreachable] is the deeper question.
  List<String> unreferenced({required Set<String> roots}) {
    final referenced = <String>{};
    for (final targets in edges.values) {
      referenced.addAll(targets);
    }
    return edges.keys
        .where((file) =>
            isLibraryFile(file) &&
            !referenced.contains(file) &&
            !roots.contains(file))
        .toList()
      ..sort();
  }

  /// Library files that no entry point can reach.
  ///
  /// Walks [edges] from every file in [roots] and from every file outside a
  /// `lib/` — tests, tools, examples are entry points by nature — and reports
  /// the library files never visited. Unlike [unreferenced] this sees through
  /// a dead barrel to the files it exports, and through a pair of dead files
  /// that import each other. It is only as good as [roots]: an entry point
  /// the caller failed to name is reported along with everything only it
  /// reaches.
  List<String> unreachable({required Set<String> roots}) {
    final queue = <String>[
      ...roots.where(edges.containsKey),
      ...edges.keys.where((f) => !isLibraryFile(f)),
    ];
    final visited = queue.toSet();
    var head = 0;
    while (head < queue.length) {
      for (final next in edges[queue[head++]] ?? const <String>{}) {
        if (visited.add(next)) queue.add(next);
      }
    }
    return edges.keys
        .where((file) => isLibraryFile(file) && !visited.contains(file))
        .toList()
      ..sort();
  }

  /// How many project files depend on each file — its fan-in. Every node is
  /// a key, so a file nothing imports reads 0.
  Map<String, int> fanIn() {
    final counts = {for (final file in edges.keys) file: 0};
    for (final targets in edges.values) {
      for (final target in targets) {
        counts[target] = (counts[target] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// How many project files each file depends on — its fan-out.
  Map<String, int> fanOut() =>
      {for (final entry in edges.entries) entry.key: entry.value.length};

  /// The feature [file] belongs to: its directory under `lib/`, cut to
  /// [depth] folders — or null for a file outside every `lib/`.
  ///
  /// `lib/src/` is pub's convention for "private", not a feature, so it is
  /// looked through: at depth 1 both `lib/auth/x.dart` and
  /// `lib/src/auth/x.dart` fall in their `auth` folder. A file directly in
  /// `lib/` (or `lib/src/`) belongs to that directory. The name is the real
  /// path prefix, so a reader can find it.
  String? featureOf(String file, int depth) {
    final root = libraryRoot(file);
    if (root == null) return null;
    final dirs = file.substring(root.length).split('/')..removeLast();
    final skip = dirs.isNotEmpty && dirs.first == 'src' ? 1 : 0;
    final kept = dirs.take(skip + (depth < 0 ? 0 : depth));
    return [root.substring(0, root.length - 1), ...kept].join('/');
  }

  /// Every feature at [depth], with its size and how it couples to the rest,
  /// sorted by name. Only files under a `lib/` take part, and only edges that
  /// cross from one feature into another count.
  List<FeatureMetrics> features(int depth) {
    final files = <String, int>{};
    final afferent = <String, int>{};
    final efferent = <String, int>{};
    for (final entry in edges.entries) {
      final from = featureOf(entry.key, depth);
      if (from == null) continue;
      files[from] = (files[from] ?? 0) + 1;
      for (final target in entry.value) {
        final to = featureOf(target, depth);
        if (to == null || to == from) continue;
        efferent[from] = (efferent[from] ?? 0) + 1;
        afferent[to] = (afferent[to] ?? 0) + 1;
      }
    }
    return [
      for (final name in files.keys.toList()..sort())
        FeatureMetrics(
          name,
          files: files[name]!,
          afferent: afferent[name] ?? 0,
          efferent: efferent[name] ?? 0,
        ),
    ];
  }

  /// Every pair of features at [depth] joined by at least one edge, with the
  /// number of imports from one into the other — heaviest first.
  List<Coupling> coupling(int depth) {
    final counts = <String, Map<String, int>>{};
    for (final entry in edges.entries) {
      final from = featureOf(entry.key, depth);
      if (from == null) continue;
      for (final target in entry.value) {
        final to = featureOf(target, depth);
        if (to == null || to == from) continue;
        final row = counts.putIfAbsent(from, () => {});
        row[to] = (row[to] ?? 0) + 1;
      }
    }
    return [
      for (final from in counts.entries)
        for (final to in from.value.entries)
          Coupling(from.key, to.key, to.value),
    ]..sort((a, b) {
        final byEdges = b.edges.compareTo(a.edges);
        if (byEdges != 0) return byEdges;
        final byFrom = a.from.compareTo(b.from);
        return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
      });
  }

  /// Whether [file] sits under the `lib/` of any package in [packages].
  bool isLibraryFile(String file) => libraryRoot(file) != null;

  /// The `lib/` directory [file] belongs to, as a prefix (`lib/`,
  /// `packages/core/lib/`), or null for a file outside every one.
  String? libraryRoot(String file) {
    String? best;
    for (final dir in packages.keys) {
      final prefix = dir.isEmpty ? 'lib/' : '$dir/lib/';
      if (file.startsWith(prefix) &&
          (best == null || prefix.length > best.length)) {
        best = prefix;
      }
    }
    return best;
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

    // Each node's children are snapshotted once, when its frame is pushed.
    // Re-sorting them on every visit made a hub file with d imports cost
    // d² log d, and the order does not change the partition anyway.
    _Frame push(String node) {
      index[node] = low[node] = counter++;
      stack.add(node);
      onStack.add(node);
      return _Frame(node, (edges[node] ?? const <String>{}).toList()..sort());
    }

    for (final root in edges.keys) {
      if (index.containsKey(root)) continue;
      final work = <_Frame>[push(root)];

      while (work.isNotEmpty) {
        final frame = work.last;
        final node = frame.node;

        if (frame.next < frame.targets.length) {
          final child = frame.targets[frame.next++];
          if (!index.containsKey(child)) {
            work.add(push(child));
          } else if (onStack.contains(child)) {
            low[node] = _min(low[node]!, index[child]!);
          }
          continue;
        }

        work.removeLast();
        if (work.isNotEmpty) {
          final parent = work.last.node;
          low[parent] = _min(low[parent]!, low[node]!);
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

/// One feature of the project and how it is coupled to the others.
///
/// [afferent] counts the imports reaching in from other features, [efferent]
/// the imports going out to them — Robert C. Martin's Ca and Ce.
class FeatureMetrics {
  final String name;
  final int files;
  final int afferent;
  final int efferent;

  const FeatureMetrics(
    this.name, {
    required this.files,
    required this.afferent,
    required this.efferent,
  });

  /// Ce / (Ca + Ce): 0 for a feature everything leans on and that leans on
  /// nothing, 1 for one that only leans on others. Null when it has no edge
  /// to any other feature at all.
  double? get instability {
    final total = afferent + efferent;
    return total == 0 ? null : efferent / total;
  }
}

/// [edges] imports from files of feature [from] into files of feature [to].
class Coupling {
  final String from;
  final String to;
  final int edges;

  const Coupling(this.from, this.to, this.edges);
}

/// One node on Tarjan's explicit stack: the node, its children in a fixed
/// order, and how many of them have been walked.
class _Frame {
  final String node;
  final List<String> targets;
  int next = 0;

  _Frame(this.node, this.targets);
}

int _min(int a, int b) => a < b ? a : b;

/// The project file [uri] points at, or null when it points outside.
///
/// Three forms name a project file: a `package:` URI of the root package or
/// of one of [packages], a path relative to [from], and a root-relative one.
/// All go through the same segment walk, so `.`, `..` and empty segments mean
/// the same thing in each; a URI climbing above the project is null.
///
/// Root-relative means a leading `/`, which Dart resolves against the `lib/`
/// of the importing file's own package — `export '/features/x.dart'` from
/// `lib/index.dart` is `package:<self>/features/x.dart`. FlutterFlow writes
/// its barrels this way, so dropping the form made every file such a barrel
/// exported look unreachable.
String? resolveUri(
  String uri, {
  required String from,
  required String packageName,
  Map<String, String> packages = const {},
}) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('http:') || uri.startsWith('https:')) return null;

  final List<String> base;
  final String rest;
  if (uri.startsWith('/')) {
    final root = _libRootOf(from, packages);
    // Outside a lib/ there is no package root to be relative to.
    if (root == null) return null;
    base = root;
    rest = uri.substring(1);
  } else if (uri.startsWith('package:')) {
    final slash = uri.indexOf('/');
    if (slash < 0) return null;
    final name = uri.substring('package:'.length, slash);
    rest = uri.substring(slash + 1);
    if (name == packageName) {
      base = ['lib'];
    } else {
      String? dir;
      for (final entry in packages.entries) {
        if (entry.value == name && entry.key.isNotEmpty) {
          dir = entry.key;
          break;
        }
      }
      if (dir == null) return null;
      base = [...dir.split('/'), 'lib'];
    }
  } else {
    base = from.split('/')..removeLast();
    rest = uri;
  }

  final parts = [...base];
  for (final segment in rest.split('/')) {
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

/// The `lib/` of the package holding [from], as path segments, or null when
/// [from] lives outside every one.
List<String>? _libRootOf(String from, Map<String, String> packages) {
  List<String>? best;
  for (final dir in [...packages.keys, '']) {
    final prefix = dir.isEmpty ? 'lib/' : '$dir/lib/';
    if (from.startsWith(prefix) &&
        (best == null || prefix.length > best.join('/').length + 1)) {
      best = prefix.split('/')..removeLast();
    }
  }
  return best;
}
