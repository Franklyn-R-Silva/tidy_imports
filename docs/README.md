# tidy_imports documentation

The [README](../README.md) is the tour. These pages are the reference: every
option, every configuration key, and the reasoning behind the defaults.

| Page | What it covers |
|---|---|
| [Getting started](getting-started.md) | Installing, running, choosing files, what is on by default |
| [Configuration](configuration.md) | Every flag and every config key, the standalone file, config diagnostics |
| [Shaping the output](output-shape.md) | The groups, custom tiers, exports, folder grouping, test doubles, notes above imports |
| [Agreeing with your lints](lint-agreement.md) | `--doctor`, `--flat`, `--relative-imports`, `--package-imports`, `dart format` |
| [Cleaning up](cleanup.md) | Duplicate imports, unused imports, sorting `pubspec.yaml` |
| [The import graph](import-graph.md) | `--report`: cycles, dead files, dependencies, coupling metrics, Mermaid / DOT / JSON |
| [Tricky imports](tricky-imports.md) | Multi-line, conditional and commented directives — and what is never moved |
| [CI](ci.md) | GitHub Actions, exit codes, pre-commit, a graph in the job summary |
| [Using it as a library](library-api.md) | The pure functions behind the CLI |
| [Coming from import_sorter](migrating-from-import_sorter.md) | What changed, and how to switch |

Something missing or wrong? [Open an issue](https://github.com/Franklyn-R-Silva/tidy_imports/issues)
— a page that says the wrong thing is a bug like any other.
