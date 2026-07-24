# tidy_imports

[![pub version](https://img.shields.io/pub/v/tidy_imports)](https://pub.dev/packages/tidy_imports)
[![pub points](https://img.shields.io/pub/points/tidy_imports)](https://pub.dev/packages/tidy_imports/score)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![CI](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml/badge.svg)](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Dart CLI tool that automatically organizes your import statements — alphabetically sorted and grouped by origin.

Spiritual successor to [import_sorter](https://github.com/fluttercommunity/import_sorter), built for Dart 3+ with bug fixes, new flags, and monorepo support.

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

### As a dev dependency (per project)

Add to `dev_dependencies` in `pubspec.yaml`:

```yaml
dev_dependencies:
  tidy_imports: ^1.0.0
```

```sh
dart pub get
dart run tidy_imports
```

### Global activation

```sh
dart pub global activate tidy_imports
tidy_imports
```

## Usage

```sh
# Sort all dart files in the project
dart run tidy_imports

# Sort specific files
dart run tidy_imports lib/main.dart lib/app.dart

# Sort files matching a glob pattern
dart run tidy_imports "lib/src/*"

# Preview changes without writing (dry run)
dart run tidy_imports --dry-run

# CI: fail if any file is unsorted
dart run tidy_imports --exit-if-changed
```

## Options

| Flag | Short | Description |
|---|---|---|
| `--emojis` | `-e` | Add emojis to import group comments |
| `--no-comments` | | Omit group comments entirely |
| `--no-blank-lines` | | Omit blank lines between import groups |
| `--sort-pubspec` | | Also sort `pubspec.yaml` dependencies alphabetically |
| `--dry-run` | | Preview changes without writing files |
| `--exit-if-changed` | | Exit with code 1 if any file would change |
| `--ignore-config` | | Ignore configuration file / `pubspec.yaml` block |
| `--version` | `-v` | Print version and exit |
| `--help` | `-h` | Show help |

## Configuration

Add a `tidy_imports:` block to your `pubspec.yaml`:

```yaml
tidy_imports:
  emojis: false          # Default: false — add emojis to group comments
  comments: true         # Default: true  — add group comments
  blank_lines: true      # Default: true  — blank lines between groups
  sort_pubspec: false    # Default: false — also sort pubspec.yaml deps
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

## CI Integration

### GitHub Actions

```yaml
- name: Check import order
  run: dart run tidy_imports --exit-if-changed
```

The command exits with code `1` if any file has unsorted imports, causing the CI job to fail. Use `--dry-run` locally to preview what would change without modifying files.

### pre-commit hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Franklyn-R-Silva/tidy_imports
    rev: 'v1.0.0'
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
| `--dry-run` flag | Not available | Available |
| `--no-blank-lines` flag | Not available | Available |
| Dart SDK | `>=2.12.0` | `>=3.0.0` |
| Conditional imports | Misclassified | Handled correctly |
| Versioning | Manual | Automated via Release Please |

## Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, commit format, and release process.

## Credits

Based on the original work by [@gleich](https://github.com/gleich) and contributors
of [import_sorter](https://github.com/fluttercommunity/import_sorter).

## License

MIT
