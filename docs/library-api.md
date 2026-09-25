# Using it as a library

Everything the CLI does to the *text* of a file is a pure function you can
call. `bin/tidy_imports.dart` owns all of the argument parsing and console
output; the functions below print nothing and never call `exit()` — they throw,
or they return data. That is what makes them usable from your own script, a
code generator, or an editor extension.

```dart
import 'package:tidy_imports/tidy_imports.dart';

void main() {
  final result = sortImports(
    source.split('\n'),
    'my_app', // your package name — what the Project group is decided from
    false, // emojis
    false, // deprecated and inert; removed in 3.0.0
    false, // noComments
    separateRelativeImports: true,
  );

  if (result.updated) print(result.sortedFile);
}
```

## Sorting

| Symbol | What it is |
|---|---|
| `sortImports(lines, packageName, emojis, _, noComments, {…})` | The sorter. Returns `ImportSortData(sortedFile, updated, duplicatesRemoved:)`. Every option on the CLI is a named parameter; `relativeImports` and `packageImports` together throw an `ArgumentError` |
| `sortPubspec(String)` | The dependency sort, string in and string out |
| `directiveUris(lines)` | Every `import`, `export` and `part` URI — skipping anything inside a string or a `/* */` block |
| `declaresMain(lines)` | Whether the file declares a top-level `main()` |

## Configuration

| Symbol | What it is |
|---|---|
| `TidyConfig.load(root, pubspecYaml)`, `.fromYaml(node)`, `.fromStandalone(node)` | The config reader. `TidyConfig.issues` is what was wrong with it, as finished sentences |
| `CustomTier(name, pattern)` | One custom group |
| `setConfigKeys(source, values, standalone:)` | The line editor behind `--doctor --apply`: sets keys in a pubspec block or a standalone file, keeping comments and CRLF. `null` when the layout is not one it will edit |

## Lints

| Symbol | What it is |
|---|---|
| `readLints(optionsPath, read:, packageDir:)` | The lint rules in force, following `include:`. IO is passed in, so it runs on an in-memory file system as well as a real one |
| `diagnose(lints, config, formatterSeparates:)` | The `--doctor` verdict: a list of `DoctorFinding(kind, message, fix)` |
| `fixesOf(findings)` | The config keys the fights and suggestions would set |
| `importLints` | The three lint names `--doctor` knows about |

## The import graph

| Symbol | What it is |
|---|---|
| `ImportGraph.build(directivesByFile, packageName, {packages})` | The graph behind `--report`: `cycles()`, `cycleWalk()`, `unreachable()`, `unreferenced()`, `fanIn()`, `fanOut()`, `featureOf()`, `features()`, `coupling()` |
| `resolveUri(uri, from:, packageName:, packages:)` | One URI to a project-relative path, or `null` when it points outside |
| `toMermaid(graph, nodes:, …)`, `toDot(graph, nodes:, …)` | The drawings |
| `reportJson(graph, …)` | The JSON document, as a map, with `reportSchemaVersion` |
| `auditDependencies(pubspec, directivesByFile:, …)` | Unused and dev-only dependencies, as a `DependencyAudit` |

## Files

| Symbol | What it is |
|---|---|
| `dartFiles(root, patterns, {extraDirectories})` | File discovery — no links followed, hidden and `build/` directories skipped. Throws `FormatException` on a bad pattern |
| `compilePatterns(patterns, label)`, `toPosix(path)` | The pattern and path helpers the CLI uses |
| `standardDirectories`, `reportDirectories` | Where the sorter and the report look |

[`example/example.dart`](../example/example.dart) runs one demonstration per
option and is the fastest way to see the shapes `sortImports` takes.
