# tidy_imports

[![pub version](https://img.shields.io/pub/v/tidy_imports)](https://pub.dev/packages/tidy_imports)
[![CI](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml/badge.svg)](https://github.com/Franklyn-R-Silva/tidy_imports/actions/workflows/test.yml)

A Dart CLI tool that automatically organizes your import statements.  
Spiritual successor to [import_sorter](https://github.com/fluttercommunity/import_sorter).

Imports are sorted **alphabetically** and grouped in this order:

1. Dart imports (`dart:`)
2. Flutter imports (`package:flutter/`)
3. Package imports (`package:`)
4. Project imports (relative or `package:<your_package>/`)

## Before

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:myapp/home.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'another_file.dart';
```

## After

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

## Installing

Add to `dev_dependencies` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  tidy_imports: ^1.0.0
```

Then run:

```sh
dart pub get
```

## Running

```sh
dart run tidy_imports
```

Sort only specific files:

```sh
dart run tidy_imports lib/main.dart lib/app.dart
dart run tidy_imports "lib/*"
```

## Options

| Flag | Short | Description |
|---|---|---|
| `--emojis` | `-e` | Add emojis to import group comments |
| `--no-comments` | | Omit group comments entirely |
| `--exit-if-changed` | | Exit with code 1 if any file would change (useful for CI) |
| `--ignore-config` | | Ignore `tidy_imports:` block in `pubspec.yaml` |
| `--help` | `-h` | Show help |

## Configuration

Add a `tidy_imports:` block to your `pubspec.yaml`:

```yaml
tidy_imports:
  emojis: true           # Optional, default: false
  comments: false        # Optional, default: true
  ignored_files:         # Optional, regex patterns applied to file paths
    - \/lib\/generated\/*
```

## pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Franklyn-R-Silva/tidy_imports
    rev: 'v1.0.0'
    hooks:
      - id: dart-import-sorter      # for plain Dart projects
      # - id: flutter-import-sorter # for Flutter projects
```

## Directories Scanned

`lib/`, `src/`, `bin/`, `test/`, `tests/`, `test_driver/`, `integration_test/`

## Contributing

Pull requests are welcome! Please open an issue first to discuss what you'd like to change.

## Credits

Based on the original work by [@gleich](https://github.com/gleich) and contributors  
of [import_sorter](https://github.com/fluttercommunity/import_sorter).

## License

MIT
