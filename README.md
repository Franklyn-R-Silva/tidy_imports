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
| `--dry-run` | | Preview changes without writing files |
| `--exit-if-changed` | | Exit with code 1 if any file would change |
| `--ignore-config` | | Ignore `tidy_imports:` block in `pubspec.yaml` |
| `--version` | `-v` | Print version and exit |
| `--help` | `-h` | Show help |

## Configuration

Add a `tidy_imports:` block to your `pubspec.yaml`:

```yaml
tidy_imports:
  emojis: false          # Default: false — add emojis to group comments
  comments: true         # Default: true  — add group comments
  blank_lines: true      # Default: true  — blank lines between groups
  ignored_files:         # Regex patterns applied to relative file paths
    - \/lib\/generated\/
    - \.g\.dart$
```

The `ignored_files` patterns are matched against the path relative to the project root (e.g. `/lib/src/foo.dart`).

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
