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

## [1.5.0](https://github.com/Franklyn-R-Silva/tidy_imports/compare/v1.4.0...v1.5.0) (2026-08-31)


### Features

* add --no-blank-lines flag, packages/ scan, and monorepo pubspec.lock fix ([7c40e4c](https://github.com/Franklyn-R-Silva/tidy_imports/commit/7c40e4cf26e0cec800cfd9273b8db80a069974e5))
* add --separate-relative-imports for dart format 3.13+ interop ([5ebf3f0](https://github.com/Franklyn-R-Silva/tidy_imports/commit/5ebf3f095ac02149ecdcf67810e96076e371f7a6))
* add --separate-relative-imports for dart format 3.13+ interop ([2bd19f9](https://github.com/Franklyn-R-Silva/tidy_imports/commit/2bd19f9b03bdcaa2a139ab1a63968585b57a6417))
* add --test-imports group for fake_/mock_ test doubles ([f74a957](https://github.com/Franklyn-R-Silva/tidy_imports/commit/f74a957bb976eaf0f0edef2a903a78300e6febfc))
* add executables entry so tidy_imports runs as a direct command ([53ccafe](https://github.com/Franklyn-R-Silva/tidy_imports/commit/53ccafee4167d3d4664abce9b628074783aa4429))
* add versioning system, --version/--dry-run flags, and pub.dev improvements ([4eadab8](https://github.com/Franklyn-R-Silva/tidy_imports/commit/4eadab86468004c020cf5dadc0d15a63eadd3b72))
* custom import tiers, pubspec sorting, standalone config, and community files ([4afc1ea](https://github.com/Franklyn-R-Silva/tidy_imports/commit/4afc1ea4bfa3af814538013aca8fd87371ea3a48))
* group project imports by subfolder (--group-by-folder) ([94880bd](https://github.com/Franklyn-R-Silva/tidy_imports/commit/94880bd865d2f7b57c6e8f99abb57b8a7383ff31))
* initial release v1.0.0 — spiritual successor to import_sorter ([f010e2f](https://github.com/Franklyn-R-Silva/tidy_imports/commit/f010e2fd26fa707a1a89d85c91a65eab526d9894))
* read directives whole, and sort exports and folder depth on top of it ([d452731](https://github.com/Franklyn-R-Silva/tidy_imports/commit/d4527310b1f215d953380d6e7144f11de648a2da))
* read directives whole, and sort exports and folder depth on top of it ([371b434](https://github.com/Franklyn-R-Silva/tidy_imports/commit/371b4344a524e99872b404b9a555c82f101e5b04))
* report all unsorted files in --exit-if-changed and fix pre-commit hooks ([48af73e](https://github.com/Franklyn-R-Silva/tidy_imports/commit/48af73e574bec0ae69eda658cc4152897d8e36d2))


### Bug Fixes

* preserve original line endings (CRLF) when rewriting files ([c3b7983](https://github.com/Franklyn-R-Silva/tidy_imports/commit/c3b7983e22d4e13501af60fa4954b05710bdc50a))

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
