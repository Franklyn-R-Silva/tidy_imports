// Dart imports:
import 'dart:io';

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
  stdout.writeln(
      '      --ignore-config    Ignore configuration in pubspec.yaml.');
  stdout.writeln(
      '      --exit-if-changed  Exit with error if any file is unsorted.');
  stdout.writeln('                         Useful for CI pipelines.');
  stdout
      .writeln('      --no-comments      Omit group comments before imports.');
  stdout.writeln('\nExamples:');
  stdout.writeln('  dart run tidy_imports');
  stdout.writeln('  dart run tidy_imports -e');
  stdout.writeln('  dart run tidy_imports lib/main.dart lib/app.dart');
  stdout.writeln('  dart run tidy_imports "lib/*"');
  exit(0);
}
