# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`tidy_imports` is a published pub.dev Dart CLI package that sorts and groups Dart import statements. It is a rebuilt successor to `import_sorter`; many features and code comments reference upstream issue numbers (e.g. `issue import_sorter#81`) — keep that convention when fixing an inherited bug.

## Commands

```sh
dart pub get                                    # install deps
dart test                                       # full suite
dart test test/features_test.dart               # one file
dart test -n "custom tiers"                     # one group/test by name
dart test test/cli_test.dart                    # end-to-end CLI tests (spawns real processes)
dart analyze --fatal-infos                      # CI-equivalent analysis (infos are fatal)
dart format --output=none --set-exit-if-changed .   # CI-equivalent format check
dart format .                                   # apply formatting
dart run bin/tidy_imports.dart                  # run the CLI against the current directory
dart run tool/gen_version.dart                  # generate lib/src/build_info.dart (gitignored)
```

CI (`.github/workflows/test.yml`) runs format check → `dart analyze --fatal-infos` → `dart test`. All three must pass. Note `--fatal-infos`: lint *infos* fail the build, not just warnings.

The CLI always resolves its target from `Directory.current`, so running it from this repo root sorts this repo's own sources (the package dogfoods itself, configured by the `tidy_imports:` block in `pubspec.yaml`).

## Architecture

**IO boundary.** `bin/tidy_imports.dart` owns *all* filesystem access, argument parsing, and console output. Everything in `lib/` is pure: `sortImports` takes `List<String> lines` and returns `ImportSortData(sortedFile, updated)`; `sortPubspec` takes and returns a `String`. Keep new logic on the pure side so it stays unit-testable — `lib/` should surface errors by throwing (see `dartFiles`), never by calling `exit()`. `test/sort_test.dart` and `test/features_test.dart` are pure unit tests; only `test/cli_test.dart` touches the filesystem, via a temp dir and a real process.

**A typed flag overrides the config; an untyped one defers to it.** `bin/tidy_imports.dart` resolves every boolean through `resolve(flag, config.x)`, which reads `argResults.wasParsed(flag)` — not `config.x || flag`, which was the old rule and could only ever turn things *on*. Flags mirroring a config key are negatable, so `--no-x` exists for each; `comments` and `blank-lines` are stated positively on the command line and negatively in `TidyConfig` (`noComments`, `noBlankLines`), so each crosses over exactly once in `bin/`. Run-mode flags (`--dry-run`, `--exit-if-changed`, `--ignore-config`, `--help`, `--version`) stay `negatable: false`. Adding a flag means adding it to the parser, the `_help` string in `lib/args.dart`, `TidyConfig`, and the README options table.

**Config precedence** (`lib/config.dart`): a standalone `tidy_imports.yaml` at project root wins entirely over the `tidy_imports:` block in `pubspec.yaml` — they do not merge. `--ignore-config` bypasses both via `TidyConfig.fromYaml(null)`.

**`sortImports` never terminates the process.** `exitIfChanged` and `filePath` are `@Deprecated` and inert as of 1.4.2, and `lib/sort.dart` no longer imports `dart:io` at all. `bin/` owns the whole-project check and fails once at the end, so *every* unsorted file is reported (import_sorter#87). Both parameters go in 2.0.0; don't route new behavior through them.

**Read-only modes.** `--dry-run` and `--exit-if-changed` share one `readOnly` flag; the sort still runs for every file, only the write is skipped. Any new write site must respect `readOnly`.

**Line endings.** `sortImports` works purely in `\n`. `bin/` detects CRLF in the original content and re-applies it before writing, so Windows files don't get a whole-file diff.

**File discovery** (`lib/files.dart`) scans a fixed directory list (`lib`, `src`, `bin`, `test`, `tests`, `test_driver`, `integration_test`, `packages`). Positional CLI args are **regular expressions**, not globs, and *any* positional argument now activates the filter — it used to require one ending in the literal text `dart`, so `"lib/src/"` silently sorted everything. Both they and `ignored_files` are matched against a path run through `toPosix`, so a forward-slash pattern works on Windows; positional patterns see the absolute path, `ignored_files` the path relative to the project root (leading slash included, e.g. `/lib/foo.dart`). `compilePatterns` compiles both sets up front and throws `FormatException` on a bad one, which `bin/` turns into a one-line error + exit 1.

**Import classification order matters** (`lib/sort.dart`): `dart:` → `package:flutter/` → `package:<packageName>/` (project) → custom tiers → other `package:` → relative (project). Custom tiers match by `line.contains(tier.pattern)`, first match wins, so a tier can never capture flutter or own-package imports. Group comments (both plain and emoji forms, plus the legacy `// 📱 Flutter imports:`) are stripped on read and regenerated on write — adding a new group means teaching the strip branch to recognize its comment, or re-runs will duplicate it.

**`_SourceScanner.startsInCode` gates every branch that recognizes a line by its text.** The scanner walks each line and carries state across lines: single, double and triple quotes, raw strings, `//` to end of line, and `/* */` nesting (Dart block comments nest, so hunting for the next `*/` closes a level too early). It replaced a single boolean that toggled on `'''`/`"""`, which knew nothing about block comments — an import commented out inside `/* */` was hoisted back into the sorted block and became live again, and a group comment inside a string was stripped. The main loop must also `consume()` the lines it skips over, or state drifts. Any new text-recognizing branch needs the same gate.

**Test-double detection is deliberately narrow** (`_isTestDouble` in `lib/sort.dart`). It only runs on the two *project* branches, so a third-party package whose name starts with a prefix (`package:fake_async/`, `package:mock_web_server/`) keeps its place in the package group. Matching is on the URI's file name, not the whole line. Emitted last, after Project imports.

**Emission groups all follow the same shape**: `addSeparator(hasPrecedingGroup)` → comment → `sort()` → append, with `hasPrecedingGroup` set to `true` afterwards. Package-form and relative-form imports are kept in separate buckets and appended in that order (project and test groups both do this), because a plain `sort()` over both would interleave `import 'package:...'` and `import 'foo.dart'` by ASCII. `separateRelativeImports` (issue #1) puts a blank line at that bucket boundary so `dart format` 3.13+ — which separates the `package:`/relative sections itself — stops fighting the sorter; it is suppressed under `noBlankLines` and skipped on the `groupProjectByFolder` path, which already breaks there.

**The body below the block is re-emitted, never copied through.** After the last group, `sortImports` strips the blank lines that separated the directives from the rest of the file and re-adds exactly one — and *none* when nothing follows, so a barrel file ends on its last directive instead of a stray blank line `dart format` would strip right back out, leaving the two tools undoing each other (issue #6). Blank lines *after* the first line of code are the author's and are kept.

**Deletion is opt-in, and split by what it takes to decide.** `removeDuplicates` lives in `lib/sort.dart` and folds a directive whose `signature` — leading `// ignore:` lines plus its own, whitespace collapsed, trailing comments *kept* — repeats one already classified. That is a text question, so it stays on the pure side. Whether an import is *unused* is not: it needs a resolved element model, so `--remove-unused` shells out from `bin/` to `dart fix --apply --code=unused_import` before the sort loop, and honours `readOnly` by passing `--dry-run` instead. Don't reimplement that in `lib/` — approximating it on text removes imports that are in use.

**`pubspec.lock` is optional.** It is absent in pub workspaces/monorepos; the tool falls back to an empty dependency list and only loses Flutter plugin-registrant skipping. Don't reintroduce a hard read.

**Public API surface.** `lib/tidy_imports.dart` is an export barrel required by pub.dev; new public symbols need an entry there.

**CI gates beyond the three commands above.** `tool/check_version_sync.dart` fails when `pubspec.yaml`, `lib/src/version.dart` and the top `CHANGELOG.md` section disagree, or when changelog sections are not newest-first — a section has landed in the wrong place three times. `tool/check_coverage.dart` fails under 85% line coverage of `lib/` (93.1% today); `bin/` runs as a subprocess in the CLI tests and is not instrumented, so it is deliberately out of scope. `dart pub publish --dry-run` runs on PRs. Publishing itself happens from a `vX.Y.Z` tag over OIDC (`.github/workflows/publish.yml`), which needs automated publishing enabled on the package's pub.dev admin page.

## Versioning

Releases are cut by hand; Release Please was removed because every release left a stale branch behind. A version lives in three places and they move in **one commit**: `version:` in `pubspec.yaml`, `packageVersion` in `lib/src/version.dart`, and a new section at the top of `CHANGELOG.md`. `tool/check_version_sync.dart` fails the build if they drift or if the changelog is out of order — run it before pushing. Then push the commit and a `vX.Y.Z` tag; the tag triggers `.github/workflows/publish.yml`. CONTRIBUTING.md has the full sequence.

Commits still follow **Conventional Commits** (`feat:`, `fix:`, `feat!:`, `docs:`, `test:`, `refactor:`, `chore:`): nothing reads them automatically now, but they are what you size the next bump from.

`lib/src/build_info.dart` is generated by `tool/gen_version.dart` and gitignored. **No code reads it** — `--version` prints `packageVersion` from `lib/src/version.dart`. Wiring it in would need a checked-in stub, since consumers never receive the generated file.
