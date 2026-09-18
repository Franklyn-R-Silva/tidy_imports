## 2.0.0 (2026-09-18)

One default changes, and that is the whole reason for the major version.

**`separate_relative_imports` is now on.** Since Dart 3.13 `dart format` puts a
blank line between the `package:` and relative import sections itself. With this
off, `tidy_imports` took it out and `dart format` put it back — the two tools
undid each other on every run, forever (issue #1). It is a bug fix wearing the
clothes of a preference, so it ships on.

That changes output: a file with both `package:<your_package>/…` and relative
project imports gains a blank line between them, and a CI step on
`--exit-if-changed` fails once until the project is re-sorted. That surprise is
exactly what a major version is for — `^1.6.0` will not pick this up on its own.
`--no-separate-relative-imports`, or `separate_relative_imports: false`, restores
the previous output.

Nothing else changed its default, and everything new below is off until asked
for. The README now has a **What is on by default** section that lists the three
things that are, and how to switch each off.

### Features

* `--flat` / `flat:` drops the groups for one alphabetical run per section —
  `dart:`, then `package:`, then relative, exports in their own block below.
  That is the order the `directives_ordering` lint expects; the default grouping
  trips it, because `package:flutter/…` sits above the other packages and breaks
  alphabetical order among them. Verified against the lint: one violation
  before, none after (import_sorter#58, #28)
* `--relative-imports` / `relative_imports:` rewrites `package:<your_package>/…`
  imports as paths relative to the importing file, which is what
  `prefer_relative_imports` wants. Only under `lib/` — a file in `test/` or
  `bin/` cannot reach `lib/` with a relative URI, so its imports are left alone.
  Prefixes, `show`/`hide` clauses and trailing comments survive the rewrite
  (import_sorter#59)

### Deprecations

* `sortImports`' `exitIfChanged` and `filePath` parameters, inert since 1.4.2,
  outlive this release on purpose: removing them here would have made the
  upgrade two changes instead of one. They go in 3.0.0

## 1.6.0 (2026-09-18)

Two things a sorter can do to your imports besides ordering them, both off by
default. Deleting a line you did not ask to have deleted is how a formatter
loses your trust, so each is opt-in — by flag or by config key.

`--remove-duplicates` / `remove_duplicates:` folds an import written identically
twice into the first one and tells you how many it dropped. It compares text,
with whitespace collapsed, so a directive `dart format` wrapped over two lines
matches its one-line twin. Imports that merely point at the same library are
left alone — a different prefix, a different `show` clause, or a trailing
comment only one of them carries — because folding those changes what the file
means.

`--remove-unused` / `remove_unused:` runs `dart fix --apply --code=unused_import`
over the project first, then sorts, so the gaps it leaves are tidied in the same
pass. It shells out deliberately: deciding an import is unused means resolving
every identifier to the library that declares it, extension methods included,
and the analyzer in your SDK already does that correctly. It needs the Dart SDK
on `PATH` and a project that resolves, and costs an analyzer pass.

`--dry-run` and `--exit-if-changed` stay read-only through both: `dart fix` runs
in its own dry-run mode, and duplicates are counted rather than removed.

### Features

* `--remove-duplicates` and `--remove-unused`, both defaulting to false
* `ImportSortData.duplicatesRemoved` reports what was folded away

### Docs

* the example is a runnable five-part tour instead of sixty lines of comment
* pub points and likes badges

## [1.5.0](https://github.com/Franklyn-R-Silva/tidy_imports/compare/v1.4.1...v1.5.0) (2026-09-18)

A line that only *looks* like a directive is no longer treated as one. An
`import` commented out inside a `/* */` block used to be hoisted out of the
comment and into the sorted block, turning a disabled import back into a live
one. The scanner knew about triple-quoted strings and nothing else; it now
carries real state across lines, nested `/* */` included.

File patterns work as documented. A positional pattern engaged only when one of
them ended in the literal text `dart`, so `tidy_imports "lib/src/"` sorted the
whole project instead of that folder, without saying so — and since patterns
were matched against raw paths, a forward-slash pattern never matched anything
on Windows. Write them with `/` on every platform now.

Flags can switch things off, not only on. Resolution was `config || flag`, so
whatever your `tidy_imports:` block enabled was enabled for every run;
`--no-emojis`, `--comments` and the rest let a single run disagree with the
config file.

### Features

* every config-backed flag is negatable ([b5f8494](https://github.com/Franklyn-R-Silva/tidy_imports/commit/b5f8494d911bc756e10b630747251e63e2e894b5))

### Bug Fixes

* an import inside a comment or a string is no longer moved ([5ee96fd](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ee96fdf103c5fe53972c1c1ee4ef3bc3b041dd3))
* any positional argument filters, and patterns match on Windows ([5ee96fd](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ee96fdf103c5fe53972c1c1ee4ef3bc3b041dd3))
* a malformed `ignored_files` entry is reported, not thrown ([5ee96fd](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ee96fdf103c5fe53972c1c1ee4ef3bc3b041dd3))
* `sortImports` never calls `exit()`; `exitIfChanged` and `filePath` are deprecated and inert ([5ee96fd](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ee96fdf103c5fe53972c1c1ee4ef3bc3b041dd3))

### Tooling

* releases publish from a `vX.Y.Z` tag over OIDC, and CI now guards changelog order, line coverage and package validity ([17ad384](https://github.com/Franklyn-R-Silva/tidy_imports/commit/17ad384))

## [1.4.1](https://github.com/Franklyn-R-Silva/tidy_imports/compare/v1.4.0...v1.4.1) (2026-09-18)


### Bug Fixes

* stop writing a blank line below the last directive ([7d816f1](https://github.com/Franklyn-R-Silva/tidy_imports/commit/7d816f1ab0301fe57c6c516196aae9f6727867d9)), closes [#6](https://github.com/Franklyn-R-Silva/tidy_imports/issues/6)

## [1.4.0](https://github.com/Franklyn-R-Silva/tidy_imports/compare/v1.3.0...v1.4.0) (2026-08-31)

Directives are now read as directives, not as lines that happen to look like
one. That single change closes three ways an import could silently fall out of
the sorted block, and it is what makes sorting `export` possible at all.

### Features

- **`--sort-exports`** (`sort_exports: true`) — sort `export` directives into
  their own block, placed after the imports, with the same grouping the imports
  get: `// Dart exports:`, `// Flutter exports:`, `// Package exports:`,
  `// Project exports:`. Custom tiers apply too. Opt-in on purpose — on by
  default it would rewrite the barrel file of every existing project.
- **`--group-by-folder-depth=<n>`** (`group_project_by_folder_depth: n`) — cap
  how many folder segments `--group-by-folder` groups by, counted after the
  package root. On its own, `--group-by-folder` breaks a file with 25 project
  imports into a dozen groups of one or two lines; `depth: 1` gives you the
  architecture instead — one `core/` group, one `components/`, one `features/`.
  Any value above `0` switches the grouping on by itself.

### Fixes

- **Multi-line directives are sorted.** A directive had to fit on a single line
  ending in `;` to be recognised at all. An import that `dart format` wrapped
  because of a long `show`/`as` clause failed that test, fell through to the
  "not an import" branch, and was left below the sorted block — in the wrong
  group, or in no group at all. Conditional imports (`if (dart.library.io)`)
  were in the same boat.
- **A trailing line comment no longer ejects its import.**
  `import 'package:app/x.dart'; // reason` is sorted like any other, and the
  comment stays on the line.
- **`// ignore:` travels with the directive below it.** It used to be torn off
  and dropped after the import block, which silently switches the lint
  suppression off. `// ignore_for_file:` is deliberately left where it is: it
  applies to the whole file, not to the line under it.
- **Directives are classified by their URI, not by the raw line text.**
  `import 'package:http/http.dart'; // wraps dart:io sockets` used to land in
  **Dart imports** because the line contained `dart:`. It now lands in
  **Package imports**.

### Tests

- `test/directives_test.dart` — 29 tests over the scanner: wrapped and
  conditional directives, trailing comments, `// ignore:` pragmas, export
  sorting and folder depth, each group carrying an idempotency case.

### Chores

- `lints` 4 → 6, `issue_tracker` in `pubspec.yaml`, and a `.pubignore` that
  keeps `test/`, `tool/` and the release plumbing out of the published tarball
  (29 KB → 22 KB).
- Changelog sections reordered newest-first. 1.2.0 had been sitting above
  1.3.0, so pub.dev was rendering the wrong version as the latest.

## [1.3.0](https://github.com/Franklyn-R-Silva/tidy_imports/compare/v1.2.0...v1.3.0) (2026-08-17)


### Features

* add --separate-relative-imports for dart format 3.13+ interop ([5ebf3f0](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ebf3f095ac02149ecdcf67810e96076e371f7a6))
* add --separate-relative-imports for dart format 3.13+ interop ([2bd19f9](https://github.com/Franklyn-R-Silva/tidy_imports/commit/2bd19f9b03bdcaa2a139ab1a63968585b57a6417))

## 1.2.0

A dedicated group for test doubles, plus two fixes — one of which prevented
silent file corruption.

### Features
- **`--test-imports`** (`test_imports: true`) — pull project test doubles into
  their own `// Test imports:` group, placed after project imports:

  ```dart
  // Project imports:
  import 'package:myapp/cliente_details_repository.dart';

  // Test imports:
  import 'package:myapp/mock_auth_service.dart';
  import 'fake_cliente_details_repository.dart';
  ```

  A file qualifies when it is a **project** import (relative or
  `package:<your_package>/`) **and** its file name starts with a configured
  prefix. Defaults are `fake_` and `mock_`; override with
  `test_import_prefixes` (a custom list replaces the defaults).
- Third-party packages are never reclassified, so real pub packages that look
  like doubles — `package:fake_async/`, `package:mock_web_server/` — stay in
  **Package imports**. Use a custom tier to group testing libraries such as
  `mockito`.

### Fixes
- **Group comments inside string literals are no longer deleted.** The comment
  stripping pass did not check whether it was inside a triple-quoted string, so
  a line like `// Dart imports:` embedded in a multi-line string was silently
  removed — corrupting fixtures, docs, and code-generation templates. The
  import-parsing branch already guarded against this; the stripping branch now
  does too.
- **Invalid file patterns no longer crash the CLI.** Positional arguments are
  regular expressions; a malformed one (e.g. `"lib/[a-z.dart"`) threw an
  unhandled `FormatException` with a stack trace. Patterns are now compiled up
  front and reported as `Error: invalid file pattern "..."` with exit code 1.

### Tests
- New end-to-end CLI suite (`test/cli_test.dart`) covering file writing,
  `--dry-run` read-only behavior, `--exit-if-changed` exit codes, CRLF
  preservation, `ignored_files`, and running without a `pubspec.lock`. The
  existing suites only exercised the pure functions in `lib/`.

### Docs
- `CLAUDE.md` for AI-assisted contributions.
- Corrected the claim that the CLI reads the generated `lib/src/build_info.dart`
  — it does not; `--version` prints the constant in `lib/src/version.dart`.

## 1.1.0

Tagged but never published to pub.dev; its contents ship as part of 1.2.0.

New features and fixes addressing long-standing
[import_sorter](https://github.com/fluttercommunity/import_sorter) issues.

### Features
- **Custom import tiers** (`tiers:` config) — group internal/shared packages
  into their own section between package and project imports (import_sorter#81)
- **`--sort-pubspec`** — alphabetize `dependencies`, `dev_dependencies`, and
  `dependency_overrides`, preserving nested blocks and comments (import_sorter#89)
- **`--group-by-folder`** — separate project imports by subfolder with a blank
  line between folders (import_sorter#69)
- **`--no-blank-lines`** — omit blank lines between import groups (import_sorter#80)
- **Standalone `tidy_imports.yaml`** config file at the project root, taking
  precedence over the `pubspec.yaml` block — handy for monorepos (import_sorter#67)
- Direct CLI command via `executables:` — run `tidy_imports` after
  `dart pub global activate` (import_sorter#82)
- `packages/` directory is now scanned (import_sorter#79)
- pub.dev `topics` for discoverability

### Fixes
- **Monorepo / pub workspaces**: no longer crash when `pubspec.lock` is absent;
  falls back gracefully (import_sorter#85)
- **`--exit-if-changed`** now checks the whole project in one pass and reports
  *every* unsorted file before exiting, instead of aborting on the first one
  (import_sorter#87)
- **pre-commit hooks** fixed: `language: script` never resolved the entry
  command — switched to `language: system` (import_sorter#83)

### Docs & community
- Comprehensive README (comparison table, CI, monorepo, config reference)
- `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue forms, and PR template
- Automated versioning via Release Please

## 1.0.0

Spiritual successor to [import_sorter](https://github.com/fluttercommunity/import_sorter).

### What's new
- Full Dart 3 support (`sdk: ">=3.0.0 <4.0.0"`)
- Correct arg parsing using `ArgResults` properly instead of raw string matching
- Fixed elapsed time display format (`0.12s` instead of `0.123` seconds)
- Fixed duplicate path separator in file output
- Removed debug prints that leaked to stdout in the original package
- Added `src/` directory to the default search paths
- Improved detection of multi-line conditional imports
- Better error messages when `pubspec.yaml` or `pubspec.lock` are missing
- Expanded test suite with multiline-string, `part of`, and `library` edge cases

### Inherited features
- Sort and group imports: Dart / Flutter / Package / Project
- Alphabetical sorting within each group
- Emoji comments (`-e` flag)
- `--no-comments`, `--exit-if-changed`, `--ignore-config` flags
- File filter via positional regex args
- `ignored_files` config in `pubspec.yaml`
- `pre-commit` hook support
