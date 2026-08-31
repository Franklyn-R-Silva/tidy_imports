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
  stdout.writeln('\nA Dart tool to automatically organize your imports.\n');
  stdout.writeln('Usage: dart run tidy_imports [options] [files...]');
  stdout.writeln('\nOptions:');
  stdout
      .writeln('  -e, --emojis           Add emojis to import group comments.');
  stdout.writeln('  -h, --help             Show this help message.');
  stdout.writeln('  -v, --version          Show version and exit.');
  stdout.writeln(
      '      --dry-run          Preview changes without writing files.');
  stdout.writeln(
      '      --ignore-config    Ignore configuration in pubspec.yaml.');
  stdout.writeln(
      '      --exit-if-changed  Exit with code 1 if any file is unsorted.');
  stdout.writeln('                         Useful for CI pipelines.');
  stdout
      .writeln('      --no-comments      Omit group comments before imports.');
  stdout.writeln(
      '      --no-blank-lines   Omit blank lines between import groups.');
  stdout
      .writeln('      --sort-pubspec     Also sort pubspec.yaml dependencies.');
  stdout.writeln(
      '      --sort-exports     Also sort export directives into their own');
  stdout.writeln('                         block, placed after the imports.');
  stdout.writeln(
      '      --group-by-folder  Separate project imports by subfolder.');
  stdout.writeln('      --group-by-folder-depth=<n>');
  stdout.writeln(
      '                         Folder segments to group project imports by');
  stdout.writeln(
      '                         (0 = whole path). Any value above 0 also');
  stdout.writeln('                         enables --group-by-folder.');
  stdout.writeln(
      '      --test-imports     Group project test doubles (fake_/mock_)');
  stdout.writeln('                         under their own "Test imports:".');
  stdout.writeln('      --separate-relative-imports');
  stdout.writeln(
      '                         Blank line before relative imports, matching');
  stdout.writeln('                         dart format (Dart 3.13+).');
  stdout.writeln('\nExamples:');
  stdout.writeln('  dart run tidy_imports');
  stdout.writeln('  dart run tidy_imports -e');
  stdout.writeln('  dart run tidy_imports --dry-run');
  stdout.writeln('  dart run tidy_imports lib/main.dart lib/app.dart');
  stdout.writeln('  dart run tidy_imports "lib/*"');
  stdout.writeln(
      '  dart run tidy_imports --sort-exports --group-by-folder-depth=1');
  exit(0);
}
