```txt

████████╗██╗██████╗░██╗░░░██╗  ██╗███╗░░░███╗██████╗░░█████╗░██████╗░████████╗░██████╗
╚══██╔══╝██║██╔══██╗╚██╗░██╔╝  ██║████╗░████║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
░░░██║░░░██║██║░░██║░╚████╔╝░  ██║██╔████╔██║██████╔╝██║░░██║██████╔╝░░░██║░░░╚█████╗░
░░░██║░░░██║██║░░██║░░╚██╔╝░░  ██║██║╚██╔╝██║██╔═══╝░██║░░██║██╔══██╗░░░██║░░░░╚═══██╗
░░░██║░░░██║██████╔╝░░░██║░░░  ██║██║░╚═╝░██║██║░░░░░╚█████╔╝██║░░██║░░░██║░░░██████╔╝
░░░╚═╝░░░╚═╝╚═════╝░░░░╚═╝░░░  ╚═╝╚═╝░░░░░╚═╝╚═╝░░░░░░╚════╝░╚═╝░░╚═╝░░░╚═╝░░░╚═════╝░
```

[![pub version](https://img.shields.io/pub/v/tidy_imports)](https://pub.dev/packages/tidy_imports)
[![pub points](https://img.shields.io/pub/points/tidy_imports)](https://pub.dev/packages/tidy_imports/score)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![CI](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml/badge.svg)](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Dart CLI tool that automatically organizes your import statements — sorted
alphabetically and grouped by origin (Dart, Flutter, package, project).

Spiritual successor to [import_sorter](https://github.com/fluttercommunity/import_sorter),
rebuilt for Dart 3+ with bug fixes, new flags, custom import tiers, `pubspec.yaml`
sorting, and monorepo support.

## How it works

Imports are grouped in this order and sorted alphabetically within each group:

1. **Dart imports** (`dart:`)
2. **Flutter imports** (`package:flutter/`)
3. **Package imports** (`package:`)
4. **Project imports** (relative or `package:<your_package>/`)

### Before

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:myapp/home.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'another_file.dart';
```

### After

```dart
// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:myapp/home.dart';
import 'another_file.dart';
```

## Installation

`tidy_imports` is a tool you run *over* your source, never something your app
imports at runtime. It belongs in **`dev_dependencies`** — put it in
`dependencies` and you ship a sorting tool inside your app.

### In a project (recommended)

```sh
dart pub add dev:tidy_imports
```

Flutter projects use `flutter pub add dev:tidy_imports`. Either way it lands in
the right section, at the current version:

```yaml
dev_dependencies:
  tidy_imports: ^1.5.0
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

Good for a one-off run on a project you do not want to touch the `pubspec.yaml`
of. The version is whatever you activated last, which is exactly why it is the
second choice.

## Usage

```sh
# Sort every dart file in the project
dart run tidy_imports

# Sort specific files
dart run tidy_imports lib/main.dart lib/app.dart

# Sort one folder
dart run tidy_imports "lib/features/"

# Preview changes without writing (dry run)
dart run tidy_imports --dry-run

# CI: fail if any file is unsorted
dart run tidy_imports --exit-if-changed
```

### Choosing which files to sort

A positional argument is a **regular expression**, matched against each file's
path — not a shell glob. Two things follow from that:

```sh
dart run tidy_imports "lib/features/"     # every file under lib/features
dart run tidy_imports "_test\.dart$"      # only test files
dart run tidy_imports "lib/a/" "lib/b/"   # several patterns: any match wins
```

Write patterns with **forward slashes on every platform**, Windows included —
paths are normalised before matching. With no pattern, the whole project is
sorted.

## Options

| Flag | Short | Description |
|---|---|---|
| `--emojis` | `-e` | Add emojis to import group comments |
| `--no-comments` | | Omit group comments entirely |
| `--no-blank-lines` | | Omit blank lines between import groups |
| `--sort-pubspec` | | Also sort `pubspec.yaml` dependencies alphabetically |
| `--sort-exports` | | Also sort `export` directives into their own block |
| `--group-by-folder` | | Separate project imports by subfolder |
| `--group-by-folder-depth=<n>` | | Folder segments to group project imports by (`0` = whole path; above `0` implies `--group-by-folder`) |
| `--test-imports` | | Group project test doubles (`fake_`/`mock_`) separately |
| `--separate-relative-imports` | | Blank line before relative imports, matching `dart format` (Dart 3.13+) |
| `--dry-run` | | Preview changes without writing files |
| `--exit-if-changed` | | Exit with code 1 if any file would change |
| `--ignore-config` | | Ignore configuration file / `pubspec.yaml` block |
| `--version` | `-v` | Print version and exit |
| `--help` | `-h` | Show help |

### Turning an option off

Everything in the first group above is negatable, so a flag can override your
config file for a single run — not only switch something on. A flag you type
always wins:

```sh
# pubspec.yaml says `emojis: true`, but not for this run
dart run tidy_imports --no-emojis

# pubspec.yaml says `comments: false`, but put them back this once
dart run tidy_imports --comments
```

`--no-comments` and `--no-blank-lines` are simply the "off" side of the
`comments` and `blank-lines` options, and mean what they always meant.

`--dry-run`, `--exit-if-changed`, `--ignore-config`, `--version` and `--help`
describe a single invocation rather than a preference, so there is nothing to
negate.

## Configuration

Add a `tidy_imports:` block to your `pubspec.yaml`:

```yaml
tidy_imports:
  emojis: false          # Default: false — add emojis to group comments
  comments: true         # Default: true  — add group comments
  blank_lines: true      # Default: true  — blank lines between groups
  sort_pubspec: false    # Default: false — also sort pubspec.yaml deps
  sort_exports: false    # Default: false — also sort export directives
  group_project_by_folder: false  # Default: false — split project imports by folder
  group_project_by_folder_depth: 0  # Default: 0 — folder segments to group by (0 = whole path)
  separate_relative_imports: false  # Default: false — blank line before relative imports
  test_imports: false    # Default: false — split fake_/mock_ files into their own group
  test_import_prefixes:  # Default: [fake_, mock_] — file-name prefixes treated as test doubles
    - fake_
    - mock_
  ignored_files:         # Regex patterns applied to relative file paths
    - \/lib\/generated\/  # ignore a whole folder
    - \.g\.dart$          # ignore generated files (build_runner)
    - \.freezed\.dart$    # ignore freezed files
    - \.gr\.dart$         # ignore auto_route files
  tiers:                 # Custom import groups (see below)
    - name: "Company imports:"
      pattern: "package:acme_"
```

The `ignored_files` patterns are regular expressions matched against the path
relative to the project root (e.g. `/lib/src/foo.dart`).

`sort_exports` turns on the separate `export` block described in
[Sorting exports](#sorting-exports). `group_project_by_folder_depth` limits how
much of the folder path counts as a grouping key, as described in
[Limiting the folder grouping depth](#limiting-the-folder-grouping-depth) — any
value above `0` enables folder grouping on its own, so `group_project_by_folder`
does not have to be set as well.

### Standalone config file

Instead of the `pubspec.yaml` block, you can place the same options in a
`tidy_imports.yaml` file at the project root. When present, it takes precedence
over the `pubspec.yaml` block — handy for monorepos with a shared root config.

```yaml
# tidy_imports.yaml
emojis: false
sort_pubspec: true
ignored_files:
  - \.g\.dart$
```

### Custom import tiers

By default, all third-party packages share the single **Package imports** group.
Custom tiers let you split out internal/shared packages into their own group,
placed between the generic package group and your project imports:

```yaml
tidy_imports:
  tiers:
    - name: "Shared imports:"
      pattern: "package:acme_shared"
    - name: "Company imports:"
      pattern: "package:acme_"
```

Each import whose line contains a tier's `pattern` goes into that tier (first
match wins, so list the most specific patterns first). Result:

```dart
// Package imports:
import 'package:http/http.dart';

// Shared imports:
import 'package:acme_shared/utils.dart';

// Company imports:
import 'package:acme_billing/api.dart';

// Project imports:
import 'package:myapp/home.dart';
```

## Sorting pubspec.yaml

Pass `--sort-pubspec` (or set `sort_pubspec: true`) to also alphabetize the
`dependencies`, `dev_dependencies`, and `dependency_overrides` sections of your
`pubspec.yaml`. Nested dependency blocks (git/path/hosted) and comments attached
to a dependency are preserved.

```sh
dart run tidy_imports --sort-pubspec
```

## Sorting exports

Pass `--sort-exports` (or set `sort_exports: true`) to also sort your `export`
directives. They are collected into a block of their own, placed right after the
import block, using the same taxonomy — `// Dart exports:`,
`// Flutter exports:`, `// Package exports:`, `// Project exports:` and
`// Test exports:`. Custom import tiers apply to exports as well.

It is **off by default** on purpose: enabled everywhere, it would rewrite the
barrel file of every existing project on the first run. Barrels are also where
it pays off — a `lib/index.dart` in a large app, or a generated `database.dart`
with hundreds of `export` lines, is the one file no formatter orders for you.

### Before

```dart
export 'src/widgets/button.dart';
export 'package:acme_shared/utils.dart';
export 'dart:async' show Future;
export 'src/models/user.dart';
export 'package:flutter/material.dart';
```

### After

```dart
// Dart exports:
export 'dart:async' show Future;

// Flutter exports:
export 'package:flutter/material.dart';

// Package exports:
export 'package:acme_shared/utils.dart';

// Project exports:
export 'src/models/user.dart';
export 'src/widgets/button.dart';
```

## Grouping project imports by folder

Pass `--group-by-folder` (or set `group_project_by_folder: true`) to visually
separate your project imports by their subfolder with a blank line whenever the
folder changes — useful in large projects with many local files.

```dart
// Project imports:
import 'package:myapp/data/user_repository.dart';
import 'package:myapp/data/user_service.dart';

import 'package:myapp/ui/home_page.dart';
import 'package:myapp/ui/settings_page.dart';
```

## Limiting the folder grouping depth

`--group-by-folder` breaks project imports at **every** folder change, because
the grouping key is the whole folder path. Pass `--group-by-folder-depth=<n>`
(or set `group_project_by_folder_depth: <n>`) to count only the first `n` folder
segments after the package root. **Any value above `0` already enables folder
grouping** — you do not need to pass `--group-by-folder` as well.

For `package:myapp/features/orders/presentation/widgets/order_card.dart` the
grouping key is:

| Depth | Key |
|---|---|
| `0` (default) | `package:myapp/features/orders/presentation/widgets` — the whole path |
| `1` | `package:myapp/features` |
| `2` | `package:myapp/features/orders` |

This exists because of feature-first / Clean Architecture layouts. There,
`--group-by-folder` on its own splits a file with 25 project imports into about
a dozen groups of one or two lines each, which is noise rather than structure.
At depth `1` the groups match the architecture instead: one `core/`, one
`components/`, one `features/`, one `providers/`.

### `--group-by-folder` (depth `0`)

```dart
// Project imports:
import 'package:myapp/components/app_button.dart';

import 'package:myapp/core/theme/app_theme.dart';

import 'package:myapp/core/util/format_utils.dart';

import 'package:myapp/features/orders/domain/order.dart';

import 'package:myapp/features/orders/presentation/order_page.dart';

import 'package:myapp/features/orders/presentation/widgets/order_card.dart';

import 'package:myapp/providers/session_provider.dart';
```

### `--group-by-folder-depth=1`

```dart
// Project imports:
import 'package:myapp/components/app_button.dart';

import 'package:myapp/core/theme/app_theme.dart';
import 'package:myapp/core/util/format_utils.dart';

import 'package:myapp/features/orders/domain/order.dart';
import 'package:myapp/features/orders/presentation/order_page.dart';
import 'package:myapp/features/orders/presentation/widgets/order_card.dart';

import 'package:myapp/providers/session_provider.dart';
```

## Matching `dart format` (Dart 3.13+)

Since [Dart 3.13](https://dart.dev/blog/announcing-dart-3-13#tools-updates) the
formatter inserts a blank line between the `package:` and relative import
sections. Because `tidy_imports` keeps `package:<your_project>/…` and relative
imports together in one **Project imports:** block, the two tools used to undo
each other on every run.

Pass `--separate-relative-imports` (or set `separate_relative_imports: true`) to
emit that blank line up front, so both tools agree and the file stops flip-flopping:

```dart
// Project imports:
import 'package:myapp/home.dart';

import 'another_file.dart';
```

The option is a no-op when blank lines are disabled (`--no-blank-lines` /
`blank_lines: false`), and it never doubles up with `--group-by-folder`, which
already breaks at that boundary. It applies to the `--test-imports` group too.

## Grouping test doubles

Pass `--test-imports` (or set `test_imports: true`) to pull fakes and mocks out
of your project imports and into a dedicated group:

```dart
// Project imports:
import 'package:myapp/cliente_details_repository.dart';

// Test imports:
import 'package:myapp/mock_auth_service.dart';
import 'fake_cliente_details_repository.dart';
```

A file counts as a test double when it is **a project import** (relative or
`package:<your_package>/`) **and** its file name starts with a configured
prefix — `fake_` or `mock_` by default. Override the list with
`test_import_prefixes` (e.g. add `stub_` or `spy_`); a custom list replaces the
defaults rather than extending them.

Third-party packages are never affected, so real pub packages whose names look
like doubles — `package:fake_async/fake_async.dart`,
`package:mock_web_server/mock_web_server.dart` — stay in **Package imports**.
To group testing libraries such as `mockito`, use a
[custom tier](#custom-import-tiers) instead:

```yaml
tidy_imports:
  test_imports: true
  tiers:
    - name: "Testing imports:"
      pattern: "package:mockito"
```

## Multi-line and commented imports

A directive does not have to be one clean line to be sorted. There is nothing to
turn on here — these are all recognised, classified and sorted like any other
import:

- **Imports that `dart format` wrapped onto two lines**, usually because of a
  long `show` or `as` clause. They used to be missed entirely, sliding out of
  the sorted block and ending up loose below the groups:

  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart'
      show Consumer, ProviderContainer;
  ```

  The same goes for conditional imports (`if (dart.library.io)`), which
  previously landed outside every group.

- **Imports with a trailing line comment.** They used to be ejected from the
  sorted block; now they are sorted normally and the comment stays on the same
  line:

  ```dart
  import 'package:app/x.dart'; // ignore-me: documented reason
  ```

- **`// ignore:` comments above an import travel with it.** Sorting used to tear
  the comment off its import and leave it below the block, silently switching
  the lint suppression off. `// ignore_for_file:` applies to the whole file, so
  it stays where it is, at the top.

Classification also reads the **import URI**, not the raw text of the line. A
line such as `import 'package:http/http.dart'; // uses dart:io underneath` used
to be filed under **Dart imports** because of the word in the comment; it now
goes to **Package imports**, where it belongs.

### What is left alone

The other half of the promise: text that only *looks* like a directive is never
moved. A commented-out import stays commented out, and an import inside a string
stays inside the string.

```dart
/*
import 'package:app/disabled.dart';    // stays disabled
*/

const template = '''
import 'package:app/generated.dart';   // stays in the template
''';
```

The sorter tracks quotes and `/* */` blocks — which nest in Dart — line by line,
so only a line that *begins* in executable code can be a directive at all.

## CI Integration

### GitHub Actions

```yaml
- name: Check import order
  run: dart run tidy_imports --exit-if-changed
```

`--exit-if-changed` checks the **whole project in one pass** and lists **every**
file that needs sorting before exiting with code `1` — so a single CI run shows
you everything to fix, not just the first offender. It never writes files. Use
`--dry-run` locally for the same read-only preview with a friendlier summary.

### pre-commit hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Franklyn-R-Silva/tidy_imports
    rev: 'v1.1.0' # use the latest release tag
    hooks:
      - id: dart-import-sorter      # for plain Dart projects
      # - id: flutter-import-sorter # for Flutter projects
```

## Directories scanned

`lib/`, `src/`, `bin/`, `test/`, `tests/`, `test_driver/`, `integration_test/`, `packages/`

The `packages/` directory is included to support pub workspaces and monorepos.

## Monorepo / pub workspace support

`tidy_imports` works in pub workspaces where individual packages do not have their own `pubspec.lock`. When no lock file is found, the tool continues normally — Flutter plugin registrant detection is simply skipped. No crash, no manual workaround needed.

## Improvements over import_sorter

| Issue | import_sorter | tidy_imports |
|---|---|---|
| Arg parsing | Raw string matching — breaks with flags | `ArgParser` — correct flag resolution |
| Positional file args | Passes raw `args` (includes flags) | Uses `argResults.rest` |
| `pubspec.lock` in monorepos | Crashes with `PathNotFoundException` | Graceful fallback |
| `packages/` folder | Not scanned | Scanned |
| `--dry-run` preview | Not available | Available |
| `--no-blank-lines` | Not available | Available |
| Custom import tiers | Not available | Available |
| Sort `pubspec.yaml` deps | Not available | `--sort-pubspec` |
| Group project imports by folder | Not available | `--group-by-folder` |
| Folder grouping depth | Not available | `--group-by-folder-depth=<n>` |
| Separate group for test doubles | Not available | `--test-imports` |
| Sort `export` directives | Not available | `--sort-exports` |
| `dart format` 3.13+ import sections | Fights the formatter | `--separate-relative-imports` |
| Invalid file pattern | Unhandled `FormatException` | Readable error, exit 1 |
| Group comments inside string literals | Silently deleted | Preserved |
| Multi-line imports (wrapped `show`/`as`) | Dropped out of the sorted block | Sorted like any other import |
| Trailing comment on an import | Ejected the import from the block | Sorted, comment kept on the line |
| `// ignore:` above an import | Detached from its import | Travels with the import |
| Import classification | Reads the raw line, comments included | Reads the import URI |
| Standalone config file | Not available | `tidy_imports.yaml` |
| Direct CLI command | `dart pub global run ...:main` | `tidy_imports` |
| `--exit-if-changed` in CI | Aborts on first unsorted file | Reports every unsorted file |
| pre-commit hook | `language: script` (broken) | `language: system` (works) |
| Dart SDK | `>=2.12.0` | `>=3.0.0` |
| Conditional imports | Misclassified | Handled correctly |
| Versioning | Manual | Manual, with CI refusing a mismatch |

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup,
commit format, and the release process.

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Credits

Based on the original work by [@gleich](https://github.com/gleich) and contributors
of [import_sorter](https://github.com/fluttercommunity/import_sorter).

## License

[MIT](LICENSE) © Franklyn R. Silva
