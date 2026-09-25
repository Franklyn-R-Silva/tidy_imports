# Cleaning up

Every option on this page removes or reorders something beyond the import
block, so every one is **off by default**. A sorter that deletes lines uninvited
is a sorter you stop trusting — each has to be asked for, by flag or by config
key.

## `--remove-duplicates`

Drops an import written identically twice, keeping the first occurrence:

```dart
// before                         // after
import 'dart:math';               import 'dart:math';
import 'package:demo/z.dart';
import 'dart:math';               import 'package:demo/z.dart';
```

It compares text with runs of whitespace collapsed, so a directive `dart format`
wrapped over two lines still matches its one-line twin. Anything that *reads*
differently is left alone, because folding it could change what the file means:

| Left alone | Why |
|---|---|
| `import 'z.dart' as a;` and `as b;` | Different prefixes; both are in use |
| `show Foo;` and `show Bar;` | Different combinators |
| `import 'dart:math'; // for max` and the plain form | Dropping one drops what the comment says |

After [`--relative-imports` or `--package-imports`](lint-agreement.md) a
`package:` import and its relative twin are written the same way, so they fold
too.

## `--remove-unused`

Runs `dart fix --apply --code=unused_import` over the project first, then sorts
— so the holes it leaves are tidied in the same pass:

```sh
dart run tidy_imports --remove-unused --remove-duplicates
```

This one shells out on purpose. Deciding that an import is unused means
resolving every identifier in the file to the library that declares it,
extension methods included. The analyzer that ships with your SDK already does
that, correctly; approximating it with text matching would eventually remove an
import that is in use.

It needs the Dart SDK on `PATH` and a project that resolves — run `dart pub get`
first — and it costs a full analyzer pass, which is the other reason it is
opt-in. Under `--dry-run` and `--exit-if-changed` nothing is written: `dart fix`
runs in its own dry-run mode.

## Sorting `pubspec.yaml`

`--sort-pubspec` (or `sort_pubspec: true`) alphabetizes the `dependencies`,
`dev_dependencies` and `dependency_overrides` sections. Nested declarations
(`git:`, `path:`, `hosted:`) and the comments above an entry travel with it.

```sh
dart run tidy_imports --sort-pubspec
```

To check the dependencies *against the imports* — declared and never used, or
used from `lib/` while declared only for development — see
[the import graph](import-graph.md#checking-imports-against-pubspecyaml).
