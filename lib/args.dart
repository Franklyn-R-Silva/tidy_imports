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
                                 ON by default — pass the --no- form to stop it.
                                 It is the only option here that starts on.
      --test-imports             Give project files named fake_* / mock_* their
                                 own "Test imports:" group, written last.
      --flat                     Drop the groups: one alphabetical run per
                                 section (dart:, package:, relative), which is
                                 the order the `directives_ordering` lint
                                 expects. A blank line marks each section
                                 boundary, where dart format 3.13+ writes one
                                 too; --no-blank-lines gives the tight run
                                 back. Exports move only with --sort-exports.
                                 Off by default.
      --relative-imports         Rewrite package:<your_package>/… imports as
                                 relative paths, matching the
                                 `prefer_relative_imports` lint. Only inside
                                 lib/. Off by default.
      --package-imports          The opposite: rewrite relative imports under
                                 lib/ as package:<your_package>/…, matching
                                 `always_use_package_imports`. Off by default;
                                 never together with --relative-imports.
      --attach-comments          Keep a // comment written directly above an
                                 import with that import. Without it the
                                 comment ends up below the sorted block. The
                                 note above the first import is a file header
                                 either way. Off by default.
      --remove-duplicates        Drop an import written identically twice,
                                 keeping the first. Off by default.
      --remove-unused            Run `dart fix --code=unused_import` first, so
                                 unused imports go before the sort. Needs the
                                 Dart SDK on PATH. Off by default.
      --no-comments              Leave out the group comments.
      --no-blank-lines           Leave out the blank lines between groups.
                                 (--blank-lines forces them back on.)

  Each flag above is negatable. Pass the opposite form to override your
  config file for a single run: --no-emojis, --comments, --no-sort-exports.

Run modes
      --doctor                   Read analysis_options.yaml — following its
                                 include: chain — and say whether this
                                 configuration agrees with the lints that read
                                 imports (directives_ordering,
                                 prefer_relative_imports,
                                 always_use_package_imports) and with
                                 dart format. Flags two lints that contradict
                                 each other. Sorts nothing.
      --apply                    With --doctor: write the keys it suggests
                                 into tidy_imports.yaml or the pubspec block.
      --report                   Read the project's own import graph and say
                                 what it found: files that import each other,
                                 and files under lib/ no entry point reaches.
                                 Sorts nothing, writes nothing. Patterns and
                                 ignored_files narrow what is printed, never
                                 what is read.
      --dry-run                  Report what would change; write nothing.
      --exit-if-changed          Exit 1 if anything is unsorted — or, with
                                 --report, on any finding; with --doctor, on
                                 a conflict or a fight. For CI.
      --ignore-config            Ignore tidy_imports.yaml and the pubspec block.
      --strict-config            Exit 1 on a configuration problem instead of
                                 warning about it. Either way it is reported:
                                 an unknown or misspelled option, a value of
                                 the wrong type, or a standalone
                                 tidy_imports.yaml written in the pubspec shape
                                 — options wrapped in a `tidy_imports:` key,
                                 which is read from there but does not belong
                                 there. For CI.
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
  dart run tidy_imports --report          # cycles and dead files
  dart run tidy_imports --doctor          # which options your lints want
  dart run tidy_imports --doctor --apply  # ...and write them to the config
  dart run tidy_imports --flat            # satisfy directives_ordering
  dart run tidy_imports --remove-unused --remove-duplicates
  dart run tidy_imports --no-emojis
''';
