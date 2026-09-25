// Project imports:
import 'package:tidy_imports/graph.dart';

/// Version of the document [reportJson] builds. Bumped only when a field
/// changes meaning or goes away; a new field is not a new version.
const reportSchemaVersion = 1;

/// Mermaid's default `maxEdges`: past it, GitHub renders an error box instead
/// of a diagram.
const mermaidEdgeLimit = 500;

/// [graph] as a Mermaid flowchart — the form GitHub draws inline in a README,
/// an issue or a pull request.
///
/// Only [nodes] are drawn, and only the edges between two of them. Files are
/// boxed by the feature [ImportGraph.featureOf] puts them in at
/// [featureDepth]; an edge inside an import cycle is red, and a file in
/// [unreachable] is dashed. Ids are `n0…` in path order, so the same graph
/// always prints the same text and a diff of two reports means something.
String toMermaid(
  ImportGraph graph, {
  required Iterable<String> nodes,
  Set<String> unreachable = const {},
  int featureDepth = 1,
}) {
  final layout = _Layout(graph, nodes, featureDepth);
  final out = StringBuffer('flowchart LR\n');

  var cluster = 0;
  for (final feature in layout.features.entries) {
    final name = feature.key;
    if (name == null) {
      for (final file in feature.value) {
        out.writeln('  ${layout.id[file]}["${_mermaid(file)}"]');
      }
      continue;
    }
    out.writeln('  subgraph f${cluster++}["${_mermaid(name)}"]');
    for (final file in feature.value) {
      out.writeln(
        '    ${layout.id[file]}["${_mermaid(layout.label(file, name))}"]',
      );
    }
    out.writeln('  end');
  }

  final cyclic = <int>[];
  for (final (index, edge) in layout.edges.indexed) {
    out.writeln('  ${layout.id[edge.$1]} --> ${layout.id[edge.$2]}');
    if (layout.inCycle(edge)) cyclic.add(index);
  }

  if (cyclic.isNotEmpty) {
    out.writeln('  linkStyle ${cyclic.join(',')} stroke:#d33,stroke-width:2px');
  }
  final dead = layout.files.where(unreachable.contains).toList();
  if (dead.isNotEmpty) {
    out
      ..writeln('  classDef dead stroke-dasharray:4 4,color:#888')
      ..writeln('  class ${dead.map((f) => layout.id[f]).join(',')} dead');
  }
  return out.toString();
}

/// How many edges [toMermaid] would draw for the same [nodes] — for warning
/// before a diagram crosses [mermaidEdgeLimit].
int drawnEdges(ImportGraph graph, Iterable<String> nodes) =>
    _Layout(graph, nodes, 1).edges.length;

/// [graph] in Graphviz DOT, for `dot -Tsvg`: the same drawing as [toMermaid],
/// without a size limit, with features as clusters.
String toDot(
  ImportGraph graph, {
  required Iterable<String> nodes,
  Set<String> unreachable = const {},
  int featureDepth = 1,
}) {
  final layout = _Layout(graph, nodes, featureDepth);
  final out = StringBuffer()
    ..writeln('digraph imports {')
    ..writeln('  rankdir=LR;')
    ..writeln('  node [shape=box, style=rounded, fontname="Helvetica"];');

  String node(String file, String label) {
    final dead = unreachable.contains(file)
        ? ', style="rounded,dashed", fontcolor="#888888"'
        : '';
    return '${_dot(file)} [label=${_dot(label)}$dead];';
  }

  var cluster = 0;
  for (final feature in layout.features.entries) {
    final name = feature.key;
    if (name == null) {
      for (final file in feature.value) {
        out.writeln('  ${node(file, file)}');
      }
      continue;
    }
    out
      ..writeln('  subgraph "cluster_${cluster++}" {')
      ..writeln('    label=${_dot(name)};');
    for (final file in feature.value) {
      out.writeln('    ${node(file, layout.label(file, name))}');
    }
    out.writeln('  }');
  }

  for (final edge in layout.edges) {
    final style = layout.inCycle(edge) ? ' [color="#dd3333", penwidth=2]' : '';
    out.writeln('  ${_dot(edge.$1)} -> ${_dot(edge.$2)}$style;');
  }
  out.writeln('}');
  return out.toString();
}

/// Everything `--report` knows, as a JSON-ready map.
///
/// [files] is what the report is about — the in-scope files, library or not
/// — and every list in the document is limited to them. The graph itself is
/// always read whole: fan-in counts an importer that is out of scope, since
/// the import is real either way. [top] caps the two ranked lists.
Map<String, Object?> reportJson(
  ImportGraph graph, {
  required String packageName,
  required Iterable<String> files,
  required List<List<String>> cycles,
  required Iterable<String> unreachable,
  int featureDepth = 1,
  int top = 10,
  Map<String, Object?>? dependencies,
}) {
  final scope = files.toSet();
  final fanIn = graph.fanIn();
  final fanOut = graph.fanOut();
  final dead = unreachable.toSet();
  final cycleOf = <String, int>{};
  for (final (index, group) in cycles.indexed) {
    for (final file in group) {
      cycleOf[file] = index;
    }
  }

  List<Map<String, Object>> ranked(Map<String, int> counts) {
    final entries = counts.entries
        .where((e) => e.value > 0 && scope.contains(e.key))
        .toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries.take(top))
        {'path': entry.key, 'count': entry.value},
    ];
  }

  return {
    'schemaVersion': reportSchemaVersion,
    'package': packageName,
    'featureDepth': featureDepth,
    'files': [
      for (final file in scope.toList()..sort())
        {
          'path': file,
          'library': graph.isLibraryFile(file),
          'feature': graph.featureOf(file, featureDepth),
          'imports': (graph.edges[file] ?? const <String>{}).toList()..sort(),
          'importedBy': fanIn[file] ?? 0,
          'reachable': !dead.contains(file),
          'cycle': cycleOf[file],
        },
    ],
    'cycles': cycles,
    'unreachable': [
      for (final file in dead.toList()..sort())
        if (scope.contains(file)) file,
    ],
    'metrics': {
      'mostImported': ranked(fanIn),
      'mostImporting': ranked(fanOut),
      'features': [
        for (final feature in graph.features(featureDepth))
          {
            'name': feature.name,
            'files': feature.files,
            'afferent': feature.afferent,
            'efferent': feature.efferent,
            'instability': feature.instability,
          },
      ],
      'coupling': [
        for (final pair in graph.coupling(featureDepth))
          {'from': pair.from, 'to': pair.to, 'edges': pair.edges},
      ],
    },
    if (dependencies != null) 'dependencies': dependencies,
  };
}

/// What both drawings share: which files, grouped how, joined by which edges.
class _Layout {
  /// Drawn files, in path order.
  final List<String> files;

  /// Feature name (null: no feature) -> its files, features in name order.
  final Map<String?, List<String>> features;

  /// File -> `n<index>`.
  final Map<String, String> id;

  /// Every edge between two drawn files, in (from, to) order.
  final List<(String, String)> edges;

  final Map<String, int> _cycleOf;

  factory _Layout(ImportGraph graph, Iterable<String> nodes, int depth) {
    final files = nodes.toSet().toList()..sort();
    final drawn = files.toSet();

    final grouped = <String?, List<String>>{};
    for (final file in files) {
      grouped.putIfAbsent(graph.featureOf(file, depth), () => []).add(file);
    }
    final names = grouped.keys.toList()
      ..sort((a, b) => a == null
          ? 1
          : b == null
              ? -1
              : a.compareTo(b));

    final edges = <(String, String)>[
      for (final from in files)
        for (final to
            in (graph.edges[from] ?? const <String>{}).toList()..sort())
          if (drawn.contains(to)) (from, to),
    ];

    final cycleOf = <String, int>{};
    for (final (index, group) in graph.cycles().indexed) {
      for (final file in group) {
        cycleOf[file] = index;
      }
    }

    return _Layout._(
      files,
      {for (final name in names) name: grouped[name]!},
      {for (final (index, file) in files.indexed) file: 'n$index'},
      edges,
      cycleOf,
    );
  }

  _Layout._(this.files, this.features, this.id, this.edges, this._cycleOf);

  /// Whether both ends of [edge] sit in the same import cycle.
  bool inCycle((String, String) edge) {
    final group = _cycleOf[edge.$1];
    return group != null && group == _cycleOf[edge.$2];
  }

  /// [file] as shown inside the box of [feature]: the rest of its path.
  String label(String file, String feature) =>
      file.startsWith('$feature/') ? file.substring(feature.length + 1) : file;
}

/// Text inside a Mermaid `["…"]` label: a double quote would end it.
String _mermaid(String text) => text.replaceAll('"', '#quot;');

/// A quoted DOT id or string.
String _dot(String text) =>
    '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
