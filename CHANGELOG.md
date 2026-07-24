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
