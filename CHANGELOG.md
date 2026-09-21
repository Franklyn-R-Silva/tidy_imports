## 2.5.0 (2026-09-21)

Four ways to lose work, all of them quiet.

`--flat` wrote no blank line anywhere. `dart format` 3.13+ writes one at every
import section boundary, so the formatter added all three and the next `--flat`
run took them away again — the same fight issue #1 settled for the grouped
output, still running in the one mode that had no separator at all. Every run
of either tool produced a diff, forever. `--flat` now writes those lines
itself, and `--no-blank-lines` still gives back the tight run: the lint reads
order, not spacing.

Turning `--attach-comments` back off corrupted the block it had written, and
the corruption was a fixed point. The header above an attached note stopped
being recognised as one, so it stayed behind as body text while a second copy
was written above the import — and the next run read that as already sorted, so
nothing ever repaired the file. One flag dropped from one command line, and the
block never recovered.

A directive whose keyword *ends* the line — `import` with its URI on the next
one, which is legal Dart and which the import graph already read — was not a
directive to the sorter, which matched `import ` with a trailing space. It slid
out of the sorted block: exactly the failure the multi-line scanner exists to
prevent.

And three user errors still arrived as stack traces, in a tool whose stated
design is that each of them is a sentence: a misspelled flag, a `pubspec.yaml`
with no `name:`, and — one release after "a config that says when it failed" —
a config file that does not parse at all.

### Bug fixes

* `--flat` writes a blank line at each section boundary, so it stops undoing
  `dart format` 3.13+ (issue #1, in flat mode)
* turning `--attach-comments` off no longer duplicates the group header and
  orphans the note under it, and the state it used to leave behind is no longer
  read as already sorted
* a directive whose keyword ends the line is sorted like any other
* a misspelled flag is one error line and exit 1, not an `ArgParserException`
  with eight frames of `package:args` under it
* a `pubspec.yaml` that does not parse, or that declares no `name:`, is an
  error naming the problem instead of a `YamlException` or a bare `TypeError`
* a `tidy_imports.yaml` that does not parse is a configuration issue like any
  other — reported with its line and column, then run past on the defaults
* a `pubspec.lock` in an unexpected shape costs plugin-registrant skipping, not
  the run

### Features

* `declaresMain`, `standardDirectories` and `reportDirectories` are exported
  from the package barrel, where every other public symbol already was

### Docs

* README: a contents map, an exit-code table, a section on `--attach-comments`
  — the one option with no prose anywhere — and a "Using it as a library"
  section covering the whole public surface
* README: the `--flat` section no longer claims exports move without
  `--sort-exports`, and says where the blank lines now go
* `tool/check_version_sync.dart` also checks the two version numbers the README
  tells people to copy, which had drifted to `^1.5.0` and `v1.1.0`

## 2.4.0 (2026-09-18)

A configuration could fail without saying anything.

A standalone `tidy_imports.yaml` written in the `pubspec.yaml` shape — every
option wrapped in a `tidy_imports:` key — parsed cleanly, matched no key the
reader looks for, and was replaced by the defaults. No error, no warning: the
run reported success while doing the opposite of what the file said. It was
found on a project whose `ignored_files` was supposed to keep a 555-file
generated SDK out of the scan; the file had been inert for weeks, and the only
symptom was a file count nobody had reason to question.

Unknown keys were the same silence with a smaller blast radius: `sort_export`
for `sort_exports` simply did not exist, and neither did the behaviour asked
for. Values of the wrong type were the opposite failure — `emojis: "yes"` threw
`type 'String' is not a subtype of type 'bool?' in type cast`, which is loud
but names no key, so the one fact needed to fix it was the one left out.

All three now produce a sentence naming the key, and a near miss names the
option it was probably meant to be. The envelope is read rather than refused,
so no existing project breaks on upgrade — it is reported, not obeyed in
silence. `--strict-config` turns every one of them into an error and exits
before the first file is touched, for CI, where a warning nobody reads is the
same as no warning at all.

### Features

* `--strict-config`: exit 1 on a configuration problem instead of warning
* `TidyConfig.issues` carries what was wrong with a config, so `lib/` reports
  it as data and `bin/` stays the only place that prints
* `TidyConfig.fromStandalone` reads a standalone config file, unwrapping the
  `tidy_imports:` envelope and reporting it

### Bug fixes

* a standalone `tidy_imports.yaml` in the pubspec shape configured nothing, in
  silence — it now configures, and says so
* an unknown or misspelled option is named instead of dropped
* a value of the wrong type — including a malformed `tiers` entry, or a file
  that is not a map at all — is reported instead of throwing a bare `TypeError`

### Docs

* `example/example.dart` now runs one demonstration per option — the twelve
  shapes `sortImports` takes, plus `sortPubspec`, the graph behind `--report`,
  the path helpers, and a config being read and criticised

## 2.3.0 (2026-09-18)

`--attach-comments` / `attach_comments:`, off by default, keeps a `//` note
written directly above an import with that import.

Without it the note is not part of the directive, so rebuilding the block
leaves it behind — below the sorted imports, now explaining whatever follows
it, and with the group header above it duplicated. That has been the behaviour
since at least 1.4.0; it surfaced on a 2343-file app where several imports
carry a paragraph explaining why they exist.

It is opt-in because it moves comments that are already in a file, and a
project that has learned to write around the old behaviour should not have its
diff rewritten by an upgrade.

The note above the *first* directive is untouched either way: a licence header,
or one of our own group comments, belongs at the top of the file. A `///` doc
comment is never attached — it documents a declaration, not a directive.

### Features

* `--attach-comments` / `attach_comments:` and the `attachComments` parameter
  on `sortImports`

## 2.2.1 (2026-09-18)

`--report` read a root-relative URI as nothing at all.

`export '/features/login/screens/login_screen.dart';` is how FlutterFlow writes
its barrels, and Dart resolves it against the importing package's `lib/`. 2.2.0
returned null for the whole form — a review verifier had argued Dart has no
root-relative URI, and the argument was wrong. Every file such a barrel exported
lost its incoming edge.

Found on a real 2343-file Flutter app the first time the report ran on one: 63
files listed as unreachable, among them the login screen, the settings screen
and half the order module, all of them reached through one `lib/index.dart`
with 38 root-relative exports. With the form resolved the same list is 7 — and
those seven are genuinely dead.

### Bug Fixes

* `resolveUri`: a leading `/` resolves against the `lib/` of the importing
  file's own package, sub-packages included; outside a `lib/` there is no root
  to resolve against and it stays null

## 2.2.0 (2026-09-18)

A review of `--report` — five reviewers, one lens each, then three adversarial
verifiers per finding — confirmed twenty things wrong with the first version.
Four of them made the report lie in ordinary Flutter projects; this release
fixes all twenty.

**The graph is built from the whole project now.** It used to be built from
the sorter's file set, after positional patterns and `ignored_files` had
trimmed it — so a filtered-out file contributed no edges, and everything it
imported looked dead. Ignore `\.config\.dart$` and every service the
injectable output was the only importer of was reported; run
`--report "lib/features/"` and a cycle crossing that boundary vanished. Patterns
and `ignored_files` now narrow what is *printed*, never what is *read*. That is
also how a cycle inside generated code — `flutter gen-l10n` output is the stock
example — gets out of the way without losing its edges. Importers under
`example/`, `tool/`, `web/` and `benchmark/` are read too; they were never
scanned, so a `lib/` file used only from there was reported.

**Entry points are recognised, not hard-coded.** Only `lib/main.dart` and
`lib/<package>.dart` counted, so every Flutter flavour main, every `lib/` script
with a `main()`, and every public library of a pub package (`package:foo/
testing.dart` — imported by consumers, never by the package itself) was a
permanent finding, and `--report --exit-if-changed` could never pass. Roots now
include `lib/main_*.dart`, any `lib/` file declaring a top-level `main()`
(comments and strings excluded), the plugin registrant, a `report_roots` list
in the config, and — for a library, meaning no `publish_to: none` and no
`lib/main.dart` — every file outside `lib/src/`.

**Cycle arrows follow real edges.** A group was sorted alphabetically and
joined with `→`, which claimed imports no file declares: for `a → c → b → a`
the report printed `a → b → c → a`, and a developer following it to cut the
right import opened the wrong file. Each group is now drawn as a shortest
closed walk along edges that exist, with the rest of the group counted.

**Dead files are the unreachable ones.** In-degree zero was one layer deep: a
dead barrel hid everything it exported, and a pair of dead files importing each
other was reported as a cycle, which reads as "alive". The report now walks
from every entry point and names what is never reached — the barrel *and* its
exports, both halves of the pair.

**Every target of a directive is an edge.** Only the first quoted URI of the
first line counted, so a conditional import's `if (dart.library.io) 'io.dart'`
targets — the standard shape for platform code — had nothing pointing at them.
So did a URI written on the line after `import`, and the second of two
directives on one line. A directive spread over more than 24 lines by the tall
formatter was dropped entirely; the bound is 512 now, and a scan that runs into
the next directive gives up instead of swallowing it.

**Smaller, all real.** Monorepo sub-packages under `packages/` resolve their
own `package:` URIs, so their cycles and dead files are visible. The Flutter
registrant is matched on a normalised path — the old check never matched on
Windows, and the file was sorted and reported there. A file that is not valid
UTF-8 is decoded leniently instead of crashing the report; one that cannot be
read at all is an error line and exit 1, never a silently missing node. A run
that finds no Dart files says so, and fails under `--exit-if-changed`. Failing
under `--exit-if-changed` writes a line to stderr saying why. Tarjan no longer
re-sorts a node's children on every visit, and a hand-built graph with a
target that is not a node no longer throws.

### Fixes

* `--report`: graph built from every scanned file; patterns and `ignored_files`
  narrow the output only
* `--report`: flavour mains, `main()` declarers, library public files, the
  registrant and `report_roots` are entry points
* `--report`: cycle walks follow edges that exist
* `--report`: dead files are those no entry point reaches
* `directiveUris`: every URI of a directive, URIs on the next line, two
  directives on one line, directives longer than 24 lines
* `--report`: sub-packages, the registrant on Windows, invalid UTF-8,
  unreadable files, empty projects, a stderr line on failure
* sorter: an unreadable file is an error line and exit 1, not a stack trace

### Features

* `report_roots:` config key — extra entry points as regexes
* `ImportGraph.cycleWalk`, `ImportGraph.unreachable`, `ImportGraph.libraryRoot`
  and `packages`; `declaresMain` in `lib/sort.dart`
* CI runs the suite on Windows as well

## 2.1.0 (2026-09-18)

`tidy_imports` has always parsed every directive in the project on every run,
then thrown the result away. Those directives are a dependency graph, and
`--report` is what it has to say:

```
┏━━ Reading the import graph of 9 files
┃  ✖ 1 import cycle:
┃     lib/core/api.dart → lib/core/db.dart → lib/features/home.dart → lib/core/api.dart
┃  ! 2 files nothing refers to:
┃     lib/core/legacy_cart.dart
┃     lib/core/old_checkout.dart
┃     (build_runner, reflection and dynamic loading are invisible here — read before deleting)
┗━━ • 3 findings
```

**Import cycles.** Dart permits them, so no tool in the chain mentions them —
yet two files in a cycle cannot be read, tested or moved apart on their own.
The whole loop is named, not one edge of it.

**Files nothing refers to.** Not an unused *import*: a whole file that no
`import`, `export` or `part` anywhere in the project mentions. `part` counts as
a reference, so generated `.g.dart` files are never reported, and entry points
— `lib/main.dart`, `lib/<your_package>.dart`, anything outside `lib/` — are
never reported either.

The report sorts nothing and writes nothing. With `--exit-if-changed` it exits
1 on a finding, so a cycle introduced by a pull request fails the build instead
of settling in.

It sees directives and nothing else: code reached through `build_runner`,
reflection or a runtime path is invisible to it. An unreferenced file is a
question to answer, not an instruction to follow.

### Features

* `--report` — import cycles and unreferenced files, from the same directive
  scanner the sorter uses
* `ImportGraph` and `resolveUri` in `lib/graph.dart`, and `directiveUris` in
  `lib/sort.dart`, are public: the graph is usable without the CLI

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
