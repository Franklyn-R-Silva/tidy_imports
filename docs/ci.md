# CI

## GitHub Actions

```yaml
- name: Imports are sorted
  run: dart run tidy_imports --exit-if-changed

- name: The configuration agrees with the lints
  run: dart run tidy_imports --doctor --exit-if-changed

- name: No import cycles, dead files or dev-only imports
  run: dart run tidy_imports --report --exit-if-changed
```

`--exit-if-changed` checks the **whole project in one pass** and names
**every** file that needs sorting before exiting with code `1` — one CI run
shows everything to fix, not just the first offender. It never writes files.
Add `--strict-config` to fail on a misspelled option instead of warning.

### The import graph in the job summary

GitHub renders Mermaid in the job summary, so a pull request can carry a picture
of the architecture it changed:

```yaml
- name: Import graph
  if: always()
  run: |
    {
      echo '### Import graph'
      echo '```mermaid'
      dart run tidy_imports --report --format=mermaid --feature-depth=2
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
```

The diagram goes to stdout and every warning to stderr, so nothing but Mermaid
lands between the fences. For a large project, pass a pattern
(`"lib/features/checkout/"`) to draw the part the pull request touched.

## Exit codes

| Code | When |
|---|---|
| `0` | Nothing to report. Files were sorted, or — in a read-only mode — none needed it |
| `1` | Something you asked to hear about: a file needs sorting under `--exit-if-changed`; a finding under `--report --exit-if-changed` (an unused dependency is only a warning); a conflict or a fight under `--doctor --exit-if-changed`; a configuration problem under `--strict-config`; a file that could not be read; an invalid pattern, flag or value; a missing or nameless `pubspec.yaml` |

Under `--remove-unused` a failing `dart fix` exits with whatever code `dart fix`
returned, so a broken analysis stays distinguishable from an unsorted file.

Every user error is one line on stderr — never a stack trace. If you ever see
one, that is a bug worth
[reporting](https://github.com/Franklyn-R-Silva/tidy_imports/issues).

## pre-commit

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Franklyn-R-Silva/tidy_imports
    rev: 'vX.Y.Z' # the latest release tag
    hooks:
      - id: dart-import-sorter      # plain Dart projects
      # - id: flutter-import-sorter # Flutter projects
```

The README carries the current tag, kept in step with each release.
