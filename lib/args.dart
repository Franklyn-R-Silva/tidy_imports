// Dart imports:
import 'dart:io';

// Project imports:
import 'package:tidy_imports/src/version.dart';

void outputVersion() {
  stdout.writeln('$packageName $packageVersion');
  exit(0);
}

void outputHelp() {
  const title = r'''
 _   _     _          _
| |_(_) __| |_   _   (_)_ __ ___  _ __   ___  _ __| |_ ___
| __| |/ _` | | | |  | | '_ ` _ \| '_ \ / _ \| '__| __/ __|
| |_| | (_| | |_| |  | | | | | | | |_) | (_) | |  | |_\__ \
 \__|_|\__,_|\__, |  |_|_| |_| |_| .__/ \___/|_|   \__|___/
             |___/                |_|
''';

  stdout.write(title);
  stdout.write(_help);
  exit(0);
}

const _help = '''
A Dart tool that keeps your import statements organised.

Usage: dart run tidy_imports [options] [patterns...]

Options
  -e, --emojis                   Add emojis to the group comments.
      --sort-exports             Sort `export` directives into their own block,
                                 written after the imports.
      --sort-pubspec             Also sort the dependency lists in pubspec.yaml.
      --group-by-folder          Break project imports apart by subfolder.
      --group-by-folder-depth=<n>
                                 Folder segments to group by, counted after the
                                 package root. 0 keeps the whole path. Any value
                                 above 0 enables --group-by-folder on its own.
      --separate-relative-imports
                                 Blank line between `package:` and relative
                                 project imports, matching dart format 3.13+.
      --test-imports             Give project files named fake_* / mock_* their
                                 own "Test imports:" group, written last.
      --flat                     Drop the groups: one alphabetical run per
                                 section (dart:, package:, relative), which is
                                 the order the `directives_ordering` lint
                                 expects. Off by default.
      --relative-imports         Rewrite package:<your_package>/… imports as
                                 relative paths, matching the
                                 `prefer_relative_imports` lint. Only inside
                                 lib/. Off by default.
      --remove-duplicates        Drop an import written identically twice,
                                 keeping the first. Off by default.
      --remove-unused            Run `dart fix --code=unused_import` first, so
                                 unused imports go before the sort. Needs the
                                 Dart SDK on PATH. Off by default.
      --no-comments              Leave out the group comments.
      --no-blank-lines           Leave out the blank lines between groups.

  Each flag above is negatable. Pass the opposite form to override your
  config file for a single run: --no-emojis, --comments, --no-sort-exports.

Run modes
      --dry-run                  Report what would change; write nothing.
      --exit-if-changed          Exit 1 if anything is unsorted. For CI.
      --ignore-config            Ignore tidy_imports.yaml and the pubspec block.
  -h, --help                     Show this message.
  -v, --version                  Show the version.

Patterns
  Positional arguments are regular expressions matched against each file's
  path. Write them with forward slashes on every platform. With no pattern,
  the whole project is sorted.

Examples
  dart run tidy_imports
  dart run tidy_imports --dry-run
  dart run tidy_imports lib/main.dart
  dart run tidy_imports "lib/features/"
  dart run tidy_imports --sort-exports --group-by-folder-depth=1
  dart run tidy_imports --flat            # satisfy directives_ordering
  dart run tidy_imports --remove-unused --remove-duplicates
  dart run tidy_imports --no-emojis
''';
