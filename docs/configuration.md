# Configuration

Options come from three places, and the first one that speaks wins:

1. **A flag you typed** — `--flat`, `--no-emojis`. Every flag that mirrors a
   config key is negatable, so it can switch something off as well as on.
2. **`tidy_imports.yaml`** at the project root, when it exists.
3. **The `tidy_imports:` block** of `pubspec.yaml`.

The two files do not merge: a standalone `tidy_imports.yaml` replaces the
pubspec block entirely. `--ignore-config` reads neither.

## Every option

| Flag | Config key | Default | What it does |
|---|---|---|---|
| `-e`, `--emojis` | `emojis` | off | Emojis in the group comments |
| `--comments` / `--no-comments` | `comments` | **on** | The `// Dart imports:` group comments |
| `--blank-lines` / `--no-blank-lines` | `blank_lines` | **on** | A blank line between groups |
| `--separate-relative-imports` | `separate_relative_imports` | **on** | A blank line before relative project imports, [matching `dart format` 3.13+](lint-agreement.md#dart-format-313) |
| `--sort-exports` | `sort_exports` | off | [Sort `export` directives](output-shape.md#exports) into their own block |
| `--group-by-folder` | `group_project_by_folder` | off | [Break project imports](output-shape.md#grouping-by-folder) by folder |
| `--group-by-folder-depth=<n>` | `group_project_by_folder_depth` | `0` | Folder segments that make a group; above `0` implies `--group-by-folder` |
| `--test-imports` | `test_imports` | off | [Split test doubles](output-shape.md#test-doubles) (`fake_*`, `mock_*`) into their own group |
| — | `test_import_prefixes` | `[fake_, mock_]` | File-name prefixes that make a test double |
| — | `tiers` | `[]` | [Custom groups](output-shape.md#custom-tiers) for internal packages |
| `--flat` | `flat` | off | [One alphabetical run per section](lint-agreement.md#--flat--for-directives_ordering), for `directives_ordering` |
| `--relative-imports` | `relative_imports` | off | [Rewrite own imports as relative](lint-agreement.md#--relative-imports--for-prefer_relative_imports), for `prefer_relative_imports` |
| `--package-imports` | `package_imports` | off | [Rewrite relative imports as `package:`](lint-agreement.md#--package-imports--for-always_use_package_imports), for `always_use_package_imports` |
| `--attach-comments` | `attach_comments` | off | [A note above an import moves with it](output-shape.md#a-note-that-belongs-to-an-import) |
| `--remove-duplicates` | `remove_duplicates` | off | [Drop an import written twice](cleanup.md#--remove-duplicates) |
| `--remove-unused` | `remove_unused` | off | [Run `dart fix --code=unused_import` first](cleanup.md#--remove-unused) |
| `--sort-pubspec` | `sort_pubspec` | off | [Sort the dependency sections](cleanup.md#sorting-pubspecyaml) of `pubspec.yaml` |
| — | `ignored_files` | `[]` | Regexes on the project-relative path: files never sorted nor reported |
| — | `report_roots` | `[]` | [Extra entry points](import-graph.md#what-counts-as-an-entry-point) for `--report` |
| `--feature-depth=<n>` | `feature_depth` | `1` | [Folders that make a feature](import-graph.md#coupling-between-features) in `--report` |
| — | `ignored_dependencies` | `[]` | [Dependencies `--report` never flags](import-graph.md#checking-imports-against-pubspecyaml) |

Run modes — these describe one invocation and have no config key:

| Flag | What it does |
|---|---|
| `--dry-run` | Say what would change; write nothing |
| `--exit-if-changed` | Exit 1 if anything is unsorted — or, with `--report`, on any finding; with `--doctor`, on a conflict or a fight. Writes nothing |
| `--doctor` | [Check the configuration against your lints](lint-agreement.md#--doctor) |
| `--apply` | With `--doctor`: write the keys it suggests |
| `--report` | [Read the import graph](import-graph.md). Writes nothing |
| `--format=<text\|mermaid\|dot\|json>` | With `--report`: the output format |
| `--ignore-config` | Ignore `tidy_imports.yaml` and the pubspec block |
| `--strict-config` | Exit 1 on a configuration problem instead of warning |
| `-v`, `--version` | Print the version |
| `-h`, `--help` | Print the help |

## The configuration block

```yaml
# pubspec.yaml
tidy_imports:
  emojis: false
  comments: true
  blank_lines: true
  separate_relative_imports: true
  sort_exports: false
  sort_pubspec: false
  group_project_by_folder: false
  group_project_by_folder_depth: 0
  test_imports: false
  test_import_prefixes: [fake_, mock_]
  flat: false
  relative_imports: false
  package_imports: false
  attach_comments: false
  remove_duplicates: false
  remove_unused: false
  ignored_files:
    - /lib/generated/        # a whole folder
    - \.g\.dart$             # build_runner output
    - \.freezed\.dart$
  report_roots:
    - /lib/app/bootstrap\.dart
  feature_depth: 1
  ignored_dependencies:
    - flutter_native_splash
  tiers:
    - name: "Company imports:"
      pattern: "package:acme_"
```

`ignored_files` and `report_roots` are regular expressions matched against the
path relative to the project root, leading slash included:
`/lib/src/foo.dart`.

## The standalone file

The same options can live in `tidy_imports.yaml` at the project root — handy
for a monorepo with a shared root config. **The options are the document**, with
no `tidy_imports:` key around them:

```yaml
# tidy_imports.yaml
emojis: false
sort_pubspec: true
ignored_files:
  - \.g\.dart$
```

The wrapper is the pubspec shape, where the block has to be named because it
shares the file with everything else. Written in the standalone file, it used to
put every option one level below where it is read — the file parsed, configured
nothing, and the run fell back to defaults while reporting success. It is now
unwrapped and reported.

## When the configuration is wrong

Every problem with a configuration is a sentence on stderr, never silence and
never a stack trace:

```
Warning: unknown option `sort_export` in the tidy_imports configuration. Did
you mean `sort_exports`? It is being ignored.
Warning: option `emojis` expects a boolean (true or false), but the value is a
String. Using the default.
Warning: tidy_imports.yaml is not valid YAML — line 2, column 13: Mapping
values are not allowed here. Did you miss a colon earlier? Using the defaults.
Warning: `relative_imports` and `package_imports` are both on, and they
rewrite in opposite directions. Neither is applied — keep the one your lints
ask for (`dart run tidy_imports --doctor` says which).
```

Each one keeps the run going. Pass **`--strict-config`** to exit 1 instead — it
stops before the first file is touched, which is what you want in CI, where a
warning nobody reads is the same as no warning at all.

To find out whether the configuration agrees with your *lints* — a different
question from whether it parses — run [`--doctor`](lint-agreement.md#--doctor).
