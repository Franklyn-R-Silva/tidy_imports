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
