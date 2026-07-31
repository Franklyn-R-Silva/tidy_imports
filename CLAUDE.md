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

**Flag/config resolution is an OR, not an override.** In `bin/tidy_imports.dart`, every boolean is `config.x || argResults['x']`. All CLI flags are `negatable: false`, so a flag can only *enable* a behavior — there is no way to switch off something the config file turned on. Adding a flag means adding it to the parser, `lib/args.dart` help text, `TidyConfig`, and the README options table.

**Config precedence** (`lib/config.dart`): a standalone `tidy_imports.yaml` at project root wins entirely over the `tidy_imports:` block in `pubspec.yaml` — they do not merge. `--ignore-config` bypasses both via `TidyConfig.fromYaml(null)`.

**`exitIfChanged` in `sortImports` is legacy.** It calls `exit(1)` mid-sort. `bin/` deliberately passes `false` and does its own whole-project check afterwards so *every* unsorted file is reported before failing (the fix for import_sorter#87). Don't route new CI behavior through that parameter.

**Read-only modes.** `--dry-run` and `--exit-if-changed` share one `readOnly` flag; the sort still runs for every file, only the write is skipped. Any new write site must respect `readOnly`.

**Line endings.** `sortImports` works purely in `\n`. `bin/` detects CRLF in the original content and re-applies it before writing, so Windows files don't get a whole-file diff.

**File discovery** (`lib/files.dart`) scans a fixed directory list (`lib`, `src`, `bin`, `test`, `tests`, `test_driver`, `integration_test`, `packages`). Positional CLI args are compiled as **regular expressions** matched against absolute paths — the README's `"lib/src/*"` "glob" is really a regex. Patterns are compiled up front and a bad one throws `FormatException`, which `bin/` turns into a one-line error + exit 1. `ignored_files` config patterns are regexes matched against the path *relative* to the project root (leading slash included, e.g. `/lib/foo.dart`).

**Import classification order matters** (`lib/sort.dart`): `dart:` → `package:flutter/` → `package:<packageName>/` (project) → custom tiers → other `package:` → relative (project). Custom tiers match by `line.contains(tier.pattern)`, first match wins, so a tier can never capture flutter or own-package imports. Group comments (both plain and emoji forms, plus the legacy `// 📱 Flutter imports:`) are stripped on read and regenerated on write — adding a new group means teaching the strip branch to recognize its comment, or re-runs will duplicate it.

**`isMultiLineString` must guard every branch that consumes a line.** The classifier tracks triple-quoted strings by toggling on each line containing `'''`/`"""`. Both the import branch *and* the comment-stripping branch check it — a group comment inside a string literal is content, and stripping it silently corrupts files (which is exactly what happened to this repo's own test fixtures before the guard was added). Any new branch that recognizes a line by its text needs the same guard.

**Test-double detection is deliberately narrow** (`_isTestDouble` in `lib/sort.dart`). It only runs on the two *project* branches, so a third-party package whose name starts with a prefix (`package:fake_async/`, `package:mock_web_server/`) keeps its place in the package group. Matching is on the URI's file name, not the whole line. Emitted last, after Project imports.

**Emission groups all follow the same shape**: `addSeparator(hasPrecedingGroup)` → comment → `sort()` → append, with `hasPrecedingGroup` set to `true` afterwards. Package-form and relative-form imports are kept in separate buckets and appended in that order (project and test groups both do this), because a plain `sort()` over both would interleave `import 'package:...'` and `import 'foo.dart'` by ASCII.

**`pubspec.lock` is optional.** It is absent in pub workspaces/monorepos; the tool falls back to an empty dependency list and only loses Flutter plugin-registrant skipping. Don't reintroduce a hard read.

**Public API surface.** `lib/tidy_imports.dart` is an export barrel required by pub.dev; new public symbols need an entry there.

## Versioning

Releases are automated by Release Please. Never hand-edit `version:` in `pubspec.yaml` or `packageVersion` in `lib/src/version.dart` — the latter is bracketed by `x-release-please-start-version` markers and listed as an `extra-files` target in `release-please-config.json`.

Commits must follow **Conventional Commits** (`feat:`, `fix:`, `feat!:`, `docs:`, `test:`, `refactor:`, `chore:`) because the version bump is derived from them.

`lib/src/build_info.dart` is generated by `tool/gen_version.dart` and gitignored. **No code reads it** — `--version` prints `packageVersion` from `lib/src/version.dart`. Wiring it in would need a checked-in stub, since consumers never receive the generated file.
