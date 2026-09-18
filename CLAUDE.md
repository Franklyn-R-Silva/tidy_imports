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

**A config problem is data in `lib/`, output in `bin/`.** `TidyConfig.issues` is a list of finished sentences; `bin/` prints them as `Warning:` and, under `--strict-config`, as `Error:` followed by `exit(1)` — before the first file is touched. Three things fill it, and all three used to be silent: a standalone `tidy_imports.yaml` written in the pubspec shape (`TidyConfig.fromStandalone` unwraps a sole `tidy_imports:` key rather than refusing it, so an upgrade fixes those projects instead of breaking them — beside any other key it is not an envelope, and falls through to the unknown-key check); a key not in `_knownKeys`, which gets a `_closestKey` suggestion within two edits; and a value of the wrong type, read through `_readTyped` so it costs a sentence naming the key instead of a `TypeError` naming only two types. **Adding an option means adding it to `_knownKeys`**, or a valid config starts warning — the test `every option the reader supports passes without a word` is the tripwire. The warning is not opt-in: a diagnostic nobody switches on would leave the silence exactly where it was.

**`sortImports` never terminates the process.** `exitIfChanged` and `filePath` are `@Deprecated` and inert as of 1.4.2, and `lib/sort.dart` no longer imports `dart:io` at all. `bin/` owns the whole-project check and fails once at the end, so *every* unsorted file is reported (import_sorter#87). Both parameters go in 2.0.0; don't route new behavior through them.

**Read-only modes.** `--dry-run` and `--exit-if-changed` share one `readOnly` flag; the sort still runs for every file, only the write is skipped. Any new write site must respect `readOnly`.

**Line endings.** `sortImports` works purely in `\n`. `bin/` detects CRLF in the original content and re-applies it before writing, so Windows files don't get a whole-file diff.

**File discovery** (`lib/files.dart`) scans a fixed directory list (`lib`, `src`, `bin`, `test`, `tests`, `test_driver`, `integration_test`, `packages`). Positional CLI args are **regular expressions**, not globs, and *any* positional argument now activates the filter — it used to require one ending in the literal text `dart`, so `"lib/src/"` silently sorted everything. Both they and `ignored_files` are matched against a path run through `toPosix`, so a forward-slash pattern works on Windows; positional patterns see the absolute path, `ignored_files` the path relative to the project root (leading slash included, e.g. `/lib/foo.dart`). `compilePatterns` compiles both sets up front and throws `FormatException` on a bad one, which `bin/` turns into a one-line error + exit 1.

**Import classification order matters** (`lib/sort.dart`): `dart:` → `package:flutter/` → `package:<packageName>/` (project) → custom tiers → other `package:` → relative (project). Custom tiers match by `line.contains(tier.pattern)`, first match wins, so a tier can never capture flutter or own-package imports. Group comments (both plain and emoji forms, plus the legacy `// 📱 Flutter imports:`) are stripped on read and regenerated on write — adding a new group means teaching the strip branch to recognize its comment, or re-runs will duplicate it.

**`_SourceScanner.startsInCode` gates every branch that recognizes a line by its text.** The scanner walks each line and carries state across lines: single, double and triple quotes, raw strings, `//` to end of line, and `/* */` nesting (Dart block comments nest, so hunting for the next `*/` closes a level too early). It replaced a single boolean that toggled on `'''`/`"""`, which knew nothing about block comments — an import commented out inside `/* */` was hoisted back into the sorted block and became live again, and a group comment inside a string was stripped. The main loop must also `consume()` the lines it skips over, or state drifts. Any new text-recognizing branch needs the same gate.

**Test-double detection is deliberately narrow** (`_isTestDouble` in `lib/sort.dart`). It only runs on the two *project* branches, so a third-party package whose name starts with a prefix (`package:fake_async/`, `package:mock_web_server/`) keeps its place in the package group. Matching is on the URI's file name, not the whole line. Emitted last, after Project imports.

**Emission groups all follow the same shape**: `addSeparator(hasPrecedingGroup)` → comment → `sort()` → append, with `hasPrecedingGroup` set to `true` afterwards. Package-form and relative-form imports are kept in separate buckets and appended in that order (project and test groups both do this), because a plain `sort()` over both would interleave `import 'package:...'` and `import 'foo.dart'` by ASCII. `separateRelativeImports` (issue #1) puts a blank line at that bucket boundary so `dart format` 3.13+ — which separates the `package:`/relative sections itself — stops fighting the sorter; it is suppressed under `noBlankLines` and skipped on the `groupProjectByFolder` path, which already breaks there.

**The body below the block is re-emitted, never copied through.** After the last group, `sortImports` strips the blank lines that separated the directives from the rest of the file and re-adds exactly one — and *none* when nothing follows, so a barrel file ends on its last directive instead of a stray blank line `dart format` would strip right back out, leaving the two tools undoing each other (issue #6). Blank lines *after* the first line of code are the author's and are kept.

**One option ships on: `separateRelativeImports`.** The default lives in `TidyConfig` (constructor and `fromYaml`), not in `sortImports`, whose parameter stays `false` — the library is the mechanism and takes no policy, the config is the product and does. Flipping the parameter too breaks 22 emitter tests that document the primitive behaviour, which is the signal that it belongs where it is. Everything else in `TidyConfig` defaults to off; if you add an option, off is the answer unless it fixes a fight with another tool the way this one does (issue #1).

**`flat` bypasses the bucket machinery entirely.** Under it `classify` drops everything into `flatImports`/`flatExports` and returns, `_sortFlatly` orders by section (`dart:` 0, `package:` 1, relative 2) then URI, and nothing emits a header — `package:flutter/` is deliberately *not* special there, since singling it out is precisely what makes the grouped output trip `directives_ordering` (import_sorter#58, #28). `noDirectives()` has to test the flat lists too, or a flat-mode file looks empty and is returned unsorted. Grouping options are ignored rather than half-applied.

**`relativeImports` is the one place a URI is rewritten.** `relativize` runs before the duplicate check — a `package:` URI and its relative form are the same import and only look alike once both are written the same way — and only when `libRelativePath` is non-null, which `bin/` supplies solely for files under `lib/`. Everywhere else a relative URI cannot reach `lib/`, so there is nothing to rewrite to. `_relativePath` walks up with `..` from the importing file's directory.

**Deletion is opt-in, and split by what it takes to decide.** `removeDuplicates` lives in `lib/sort.dart` and folds a directive whose `signature` — leading `// ignore:` lines plus its own, whitespace collapsed, trailing comments *kept* — repeats one already classified. That is a text question, so it stays on the pure side. Whether an import is *unused* is not: it needs a resolved element model, so `--remove-unused` shells out from `bin/` to `dart fix --apply --code=unused_import` before the sort loop, and honours `readOnly` by passing `--dry-run` instead. Don't reimplement that in `lib/` — approximating it on text removes imports that are in use.

**`lib/graph.dart` is the second thing the directive scan is good for.** `sort.directiveUris` runs the sorter's own `_SourceScanner`, so a commented-out import never becomes an edge; it reads `part` as well (leaving it out made every generated `.g.dart` look dead) and *every* URI of a directive, not the first — a conditional import names three files. `ImportGraph` is pure, takes project-relative POSIX paths, and knows sub-packages through `packages` (directory → name, read from `packages/*/pubspec.yaml` in `bin/`); `resolveUri` routes `package:` and relative URIs through one segment walk and returns null for `/`-rooted, `dart:`, foreign-package and above-root URIs. Cycles are iterative Tarjan over a snapshot of each node's children (re-sorting per visit was quadratic); `cycles()` returns strongly connected *groups*, and `cycleWalk` turns one into a closed walk along edges that exist — sorting a group alphabetically and drawing arrows between neighbours claimed imports no file declares. Dead files come from `unreachable`, a BFS from the roots plus every file outside a `lib/`; `unreferenced` (in-degree zero) stays public for callers who want the shallower answer.

**`--report` discovers on its own and filters only what it prints.** It scans `standardDirectories` plus `reportDirectories` (`example`, `tool`, `web`, `benchmark` — importers nobody wants sorted), builds the graph from *all* of it, and applies positional patterns and `ignored_files` to the output. Using the sorter's filtered file set as the node set deleted every edge leaving a filtered file, so everything those files imported looked dead, and a generated cycle could not be hidden without hiding what it imports. Roots: `lib/main.dart`, `lib/main_*.dart`, any `lib/` file where `sort.declaresMain` is true, `lib/<package>.dart`, the plugin registrant, `report_roots` from config, and — for a library, meaning no `publish_to: none` and no `lib/main.dart` — every file outside `lib/src/`. Files are decoded with `allowMalformed: true` (directives are ASCII; a Latin-1 comment must not cost a file its node); a file that cannot be read at all is an error and exit 1, never a silently missing node. Read-only, and exits 1 only under `--exit-if-changed`, where it also refuses to pass with nothing scanned.

**`pubspec.lock` is optional.** It is absent in pub workspaces/monorepos; the tool falls back to an empty dependency list and only loses Flutter plugin-registrant skipping. Don't reintroduce a hard read.

**Public API surface.** `lib/tidy_imports.dart` is an export barrel required by pub.dev; new public symbols need an entry there.

**CI gates beyond the three commands above.** `tool/check_version_sync.dart` fails when `pubspec.yaml`, `lib/src/version.dart` and the top `CHANGELOG.md` section disagree, or when changelog sections are not newest-first — a section has landed in the wrong place three times. `tool/check_coverage.dart` fails under 85% line coverage of `lib/` (93.1% today); `bin/` runs as a subprocess in the CLI tests and is not instrumented, so it is deliberately out of scope. `dart pub publish --dry-run` runs on PRs — packaging problems surface before the version is tagged, not after. Publishing itself is manual and stays that way: a publish workflow existed briefly and could never upload, because that needs automated publishing enabled on pub.dev's admin page, and a pipeline that always fails at the last step is worse than no pipeline.

## Versioning

Releases are cut by hand; Release Please was removed because every release left a stale branch behind. A version lives in three places and they move in **one commit**: `version:` in `pubspec.yaml`, `packageVersion` in `lib/src/version.dart`, and a new section at the top of `CHANGELOG.md`. `tool/check_version_sync.dart` fails the build if they drift or if the changelog is out of order — run it before pushing. Then push the commit and a `vX.Y.Z` tag, and run `dart pub publish` by hand. CONTRIBUTING.md has the full sequence.

Commits still follow **Conventional Commits** (`feat:`, `fix:`, `feat!:`, `docs:`, `test:`, `refactor:`, `chore:`): nothing reads them automatically now, but they are what you size the next bump from.

`lib/src/build_info.dart` is generated by `tool/gen_version.dart` and gitignored. **No code reads it** — `--version` prints `packageVersion` from `lib/src/version.dart`. Wiring it in would need a checked-in stub, since consumers never receive the generated file.
