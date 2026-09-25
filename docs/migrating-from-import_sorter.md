# Coming from import_sorter

`tidy_imports` is a rebuild of
[import_sorter](https://github.com/fluttercommunity/import_sorter) for Dart 3,
and its default output is the same: the same four groups, the same comments,
in the same order. Switching is a dependency swap.

## Switching

```sh
dart pub remove import_sorter
dart pub add dev:tidy_imports
```

Rename the configuration block:

```yaml
# before
import_sorter:
  emojis: true
  ignored_files:
    - \.g\.dart$

# after
tidy_imports:
  emojis: true
  ignored_files:
    - \.g\.dart$
```

And the command:

```sh
dart run tidy_imports      # was: flutter pub run import_sorter:main
```

The first run adds one thing import_sorter never wrote: a blank line between
`package:<your_package>/` imports and relative ones inside the Project group.
Since Dart 3.13, `dart format` writes that line itself, and without it the two
tools undo each other on every run. See
[why it is on by default](getting-started.md#why-that-third-one-is-on).

## What changed

| | import_sorter | tidy_imports |
|---|---|---|
| Dart SDK | `>=2.12.0` | `>=3.0.0` |
| Command | `dart pub global run import_sorter:main` | `tidy_imports` |
| Argument parsing | Raw string matching — breaks with flags | `package:args`, every option negatable |
| `pubspec.lock` in a monorepo | Crashes with `PathNotFoundException` | Carries on |
| `packages/` folder | Not scanned | Scanned |
| Links and `.dart_tool/` under `packages/` | — | Never followed, never sorted |
| `--exit-if-changed` in CI | Aborts on the first unsorted file | Reports every unsorted file |
| pre-commit hook | `language: script` (broken) | `language: system` |
| `dart format` 3.13+ import sections | Fights the formatter | Agrees with it, by default |
| `directives_ordering` | Requested in #58 / #28 | `--flat` |
| `prefer_relative_imports` | Requested in #59 | `--relative-imports` |
| `always_use_package_imports` | — | `--package-imports` |
| Which flags your lints need | — | `--doctor`, and `--doctor --apply` |
| Duplicate imports | Requested in #57 | `--remove-duplicates` |
| Unused imports | Requested in #56 | `--remove-unused` |
| Custom import groups | Requested in #81 | `tiers` |
| Sorting `pubspec.yaml` | Requested in #89 | `--sort-pubspec` |
| Sorting `export` directives | — | `--sort-exports` |
| Folder grouping | Requested in #69 | `--group-by-folder`, `--group-by-folder-depth` |
| Test doubles | — | `--test-imports` |
| Import cycles, dead files, coupling | — | `--report` |
| The graph as a picture | — | `--report --format=mermaid\|dot\|json` |
| Imports checked against `pubspec.yaml` | — | `--report` |
| Standalone config | Requested in #67 | `tidy_imports.yaml` |
| A misspelled option | Silently ignored | Named, with a suggestion; `--strict-config` fails on it |
| Multi-line imports (wrapped `show`/`as`) | Dropped out of the sorted block | Sorted like any other |
| Trailing comment on an import | Ejected the import from the block | Sorted, comment kept |
| `// ignore:` above an import | Detached from its import | Travels with it |
| Import inside a string or `/* */` | Hoisted into the block | Left alone |
| Classification | Reads the raw line, comments included | Reads the URI |
| Invalid pattern, flag or pubspec | Stack trace | One line on stderr, exit 1 |
