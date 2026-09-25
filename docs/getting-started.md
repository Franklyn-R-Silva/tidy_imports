# Getting started

## Installation

`tidy_imports` is a tool you run *over* your source, never something your app
imports at runtime. It belongs in **`dev_dependencies`** — put it in
`dependencies` and you ship a sorting tool inside your app.

### In a project (recommended)

```sh
dart pub add dev:tidy_imports       # Dart
flutter pub add dev:tidy_imports    # Flutter
```

Then, from the project root:

```sh
dart run tidy_imports
```

This is the form to prefer: the version is pinned in `pubspec.yaml`, so your
machine, your teammates' machines and CI all sort with the same rules.

### Globally

```sh
dart pub global activate tidy_imports
tidy_imports
```

Good for a one-off run on a project whose `pubspec.yaml` you do not want to
touch. The version is whatever you activated last, which is exactly why it is
the second choice.

## Usage

```sh
dart run tidy_imports                              # sort every Dart file
dart run tidy_imports lib/main.dart lib/app.dart   # specific files
dart run tidy_imports "lib/features/"              # one folder
dart run tidy_imports --dry-run                    # preview, write nothing
dart run tidy_imports --exit-if-changed            # CI: fail if anything is unsorted
dart run tidy_imports --doctor                     # which options your lints want
dart run tidy_imports --report                     # what the imports say about the project
```

The command always works on the project in the **current directory**: run it
from the folder that holds `pubspec.yaml`.

## Choosing which files to sort

A positional argument is a **regular expression** matched against each file's
path — not a shell glob:

```sh
dart run tidy_imports "lib/features/"     # every file under lib/features
dart run tidy_imports "_test\.dart$"      # only test files
dart run tidy_imports "lib/a/" "lib/b/"   # several patterns: any match wins
```

Write patterns with **forward slashes on every platform**, Windows included —
paths are normalised before matching. With no pattern, the whole project is
sorted. To leave files out permanently, use
[`ignored_files`](configuration.md#the-configuration-block).

### Directories scanned

`lib/`, `src/`, `bin/`, `test/`, `tests/`, `test_driver/`, `integration_test/`
and `packages/` — the last one for pub workspaces and monorepos.

Links are never followed, and hidden directories (`.dart_tool/`, `.symlinks/`)
and a package's `build/` output are skipped: a Flutter app under `packages/`
carries links into the pub cache, and nothing there is yours to rewrite.

### Monorepos and pub workspaces

Packages inside a pub workspace have no `pubspec.lock` of their own. When none
is found the run continues normally; the only thing lost is skipping the
Flutter plugin registrant, which a workspace member rarely has.

## What is on by default

Almost nothing. `tidy_imports` sorts and groups your imports and changes
nothing else about the file unless you ask — no deleting, no rewriting, no
touching `pubspec.yaml`.

A tool that removes a line you did not ask it to remove is a tool you stop
running, and a tool you stop running sorts nothing at all. So the destructive
options are opt-in — and so are the layout options, because a project's
existing layout is a decision somebody already made.

| On by default | Why |
|---|---|
| Group comments (`// Dart imports:` …) | The point of the tool. `--no-comments` drops them |
| Blank line between groups | Readability. `--no-blank-lines` drops it |
| **Blank line before relative project imports** | Not taste — see below. `--no-separate-relative-imports` drops it |

Everything else is **off** until you turn it on, by flag or by config key.

### Why that third one is on

Since Dart 3.13, `dart format` puts a blank line between the `package:` and
relative import sections by itself. With this off, `tidy_imports` removes the
line and `dart format` puts it back, forever — every run of either tool
produces a diff (issue #1). Turning it on by default is a bug fix wearing the
clothes of a preference. [`--doctor`](lint-agreement.md#--doctor) says so when
it finds it switched off.

## Turning an option off for one run

Every flag that mirrors a config key is negatable, so a flag you type always
wins over the config file — in either direction:

```sh
dart run tidy_imports --no-emojis     # the config says emojis: true, not this time
dart run tidy_imports --comments      # the config says comments: false, put them back
```

`--dry-run`, `--exit-if-changed`, `--report`, `--doctor`, `--apply`,
`--ignore-config`, `--strict-config`, `--version` and `--help` describe a
single invocation rather than a preference, so there is nothing to negate.

Next: [Configuration](configuration.md) for the full option list.
