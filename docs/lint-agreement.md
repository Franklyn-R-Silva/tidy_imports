# Agreeing with your lints

The default output — grouped and labelled — is the point of the tool for most
people. But three lints in the Dart ecosystem read the imports too, and a
sorter that writes what a lint reports makes the two tools undo each other on
every run. Each lint has an option that agrees with it; `--doctor` tells you
which ones you need.

| Lint | What it wants | Option that agrees |
|---|---|---|
| `directives_ordering` | One alphabetical run per section, exports last | [`flat` + `sort_exports`](#--flat--for-directives_ordering) |
| `prefer_relative_imports` | Relative paths to your own files under `lib/` | [`relative_imports`](#--relative-imports--for-prefer_relative_imports) |
| `always_use_package_imports` | `package:` URIs to your own files under `lib/` | [`package_imports`](#--package-imports--for-always_use_package_imports) |
| — (`dart format` 3.13+) | A blank line between `package:` and relative imports | [`separate_relative_imports`](#dart-format-313), on by default |

## `--doctor`

```sh
dart run tidy_imports --doctor
```

`--doctor` reads the nearest `analysis_options.yaml` — as the analyzer does,
walking up from the project — follows its `include:` chain through
`.dart_tool/package_config.json`, and checks the configuration against the
lints it finds:

```
┏━━ Checking the tidy_imports configuration against analysis_options.yaml
┃  Lints that read imports: directives_ordering, always_use_package_imports
┃  ✖ `directives_ordering` (from analysis_options.yaml) wants one
┃    alphabetical run per section, and the grouped output breaks it: Flutter
┃    first and your own package last are both out of alphabetical order.
┃    `flat` writes the order the lint asks for, and `sort_exports` moves
┃    exports below the imports, where it wants them too.
┃      → flat: true, sort_exports: true
┃  ! `always_use_package_imports` (from analysis_options.yaml) is on.
┃    `package_imports` rewrites the relative imports under lib/ into the
┃    `package:` form it asks for.
┃      → package_imports: true, relative_imports: false
┗━━ ✖ 1 fight, 1 suggestion

Add to the tidy_imports: block of pubspec.yaml — or run again with --apply:

tidy_imports:
  flat: true
  sort_exports: true
  package_imports: true
  relative_imports: false
```

It says three kinds of thing:

| Kind | Meaning | `--apply` |
|---|---|---|
| **Conflict** | Two lints that cannot both be satisfied — `prefer_relative_imports` and `always_use_package_imports` together. Only `analysis_options.yaml` can settle it | Nothing to apply |
| **Fight** | The configuration makes every run write what a lint reports, or undo what `dart format` writes | Writes the fix |
| **Suggestion** | A lint is on and an option would satisfy it; nothing fights, the tool just leaves those lines alone | Writes the fix |

Each rule says where it was switched on — the project file, or the
`package:…` include that brought it — because "`directives_ordering` is on"
sends you hunting through a file that never mentions it. An include that does
not resolve (no `dart pub get` yet) is reported, and the rest is still checked.

### `--apply`

```sh
dart run tidy_imports --doctor --apply
```

Writes the fixes into `tidy_imports.yaml` when there is one, or into the
`tidy_imports:` block of `pubspec.yaml` — creating the block when there is
none. It edits lines, not the parsed YAML, so your comments, key order and CRLF
line endings stay exactly as they were; an existing key has only its value
replaced.

The edit is checked before it is written: the new text is parsed back and every
key must read as the value that was meant. A layout it will not edit by
guesswork — a flow-style `tidy_imports: {…}`, tab indentation — costs you a
snippet to paste, never a pubspec. `--dry-run` shows what would be written.

### In CI

```sh
dart run tidy_imports --doctor --exit-if-changed
```

Exits 1 while a conflict or a fight is left standing. Suggestions do not fail
the build: nothing is fighting.

`--doctor` judges the **configuration** — what every future run reads — not the
sorting flags typed next to it.

## `--flat` — for `directives_ordering`

`directives_ordering` wants one alphabetical run per section: `dart:`, then
`package:`, then relative. The default grouping breaks it twice — Flutter is
lifted above the other packages, and your own package is held back until last:

```dart
// default                                   // --flat
// Dart imports:                             import 'dart:io';
import 'dart:io';
                                             import 'package:args/args.dart';
// Flutter imports:                          import 'package:flutter/material.dart';
import 'package:flutter/material.dart';      import 'package:myapp/home.dart';

// Package imports:                          import 'helper.dart';
import 'package:args/args.dart';
                                             // no lint warning
// ← Sort directive sections alphabetically
```

Under `--flat` Flutter stops being special and the headers go away — a comment
between two runs the lint reads as one section would be a lie about the
structure. A blank line is written wherever the section changes, which is
exactly where `dart format` 3.13+ writes one; `--no-blank-lines` gives you the
tight run back, since the lint reads order, not spacing.

`export` directives move only when asked. The lint wants them in a block below
the imports, which is what **`--flat --sort-exports`** produces.

Grouping options (`--group-by-folder`, `--test-imports`, custom tiers) are
ignored under `--flat`: there are no groups left for them to shape. `--doctor`
notes it when you have them set.

## `--relative-imports` — for `prefer_relative_imports`

Rewrites imports of your own package as paths relative to the importing file:

```dart
// in lib/src/p2/bar.dart
import 'package:my_app/src/foo.dart';      →  import '../foo.dart';
import 'package:my_app/src/p2/foo.dart';   →  import 'foo.dart';
```

## `--package-imports` — for `always_use_package_imports`

The opposite direction:

```dart
// in lib/features/home/view.dart
import '../../core/theme.dart';   →  import 'package:my_app/core/theme.dart';
import 'widgets/card.dart';       →  import 'package:my_app/features/home/widgets/card.dart';
```

### What both rewrites have in common

- **Only files under `lib/` are touched.** A file in `test/` or `bin/` cannot
  reach `lib/` with a relative URI at all, so there is nothing to rewrite.
- **Only your own package.** Another package's `package:` URI has no relative
  form, and a relative URI that climbs out of `lib/` has no `package:` form —
  both are left exactly as written. So are root-relative (`/x.dart`) URIs.
- **Every URI of the directive** is rewritten — each target of a conditional
  import too — wherever `dart format` broke the line. The prefix, the
  `show`/`hide` clause and a trailing comment survive untouched.
- If a rewrite produces an import you already had, `--remove-duplicates` folds
  the two.
- `export` directives are rewritten only when `--sort-exports` moves them.
  Neither lint reads exports, so one left as written is not a warning.

The two lints are opposites — the Dart team ships both and expects you to pick
one — so the two options are never applied together. A config asking for both
gets neither, with a warning; a flag you type wins over the config for that run;
typing both is an error.

## `dart format` 3.13+

Since [Dart 3.13](https://dart.dev/blog/announcing-dart-3-13#tools-updates) the
formatter inserts a blank line between the `package:` and relative import
sections. `tidy_imports` keeps both forms of your own imports in one **Project
imports** group, so the two tools used to undo each other on every run.

**`separate_relative_imports` is on by default since 2.0.0**: the blank line is
written up front, both tools agree, and the file stops flip-flopping.

```dart
// Project imports:
import 'package:myapp/home.dart';

import 'another_file.dart';
```

It is a no-op under `--no-blank-lines`, never doubles up with
`--group-by-folder`, and applies to the test-double group too. Turn it off with
`--no-separate-relative-imports` only if you do not run `dart format` — and
`--doctor` will say so if you have it off on an SDK that separates.
