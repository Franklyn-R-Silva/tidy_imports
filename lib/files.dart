// Dart imports:
import 'dart:io';

/// The directories the sorter walks. Anything else is left alone.
const standardDirectories = [
  'lib',
  'src',
  'bin',
  'test',
  'tests',
  'test_driver',
  'integration_test',
  'packages',
];

/// Directories the import *report* reads on top of [standardDirectories].
///
/// They are never sorted — nobody asked for `example/` to be reformatted — but
/// a directive in them is still a reason for a `lib/` file to exist. `web/`
/// holds the only entry point a Dart web project has; `example/` and `tool/`
/// are pub conventions; `benchmark/` is common. Leaving them out made every
/// file used only from there look unreferenced.
const reportDirectories = ['example', 'tool', 'web', 'benchmark'];

/// Returns all dart files found in [standardDirectories], plus any
/// [extraDirectories].
///
/// Positional [args] are treated as regular expressions matched against the
/// absolute file path. Throws a [FormatException] with a readable message if a
/// pattern is not valid — callers are expected to report it and exit.
Map<String, File> dartFiles(
  String currentPath,
  List<String> args, {
  List<String> extraDirectories = const [],
}) {
  final dartFiles = <String, File>{};
  final allContents = [
    for (final dir in standardDirectories) ..._readDir(currentPath, dir),
    for (final dir in extraDirectories) ..._readDir(currentPath, dir),
  ];

  for (final fileOrDir in allContents) {
    if (fileOrDir is File && fileOrDir.path.endsWith('.dart')) {
      dartFiles[fileOrDir.path] = fileOrDir;
    }
  }

  // Filter down to the patterns passed as positional args, if any were.
  //
  // This used to activate only when some argument ended in the literal text
  // `dart`, so `tidy_imports "lib/src/*"` — an example from the tool's own
  // help — silently sorted the whole project instead of that folder. Any
  // positional argument is a filter now.
  final patterns = args.where((arg) => !arg.startsWith('-')).toList();
  if (patterns.isEmpty) return dartFiles;

  final matchers = compilePatterns(patterns, 'file pattern');
  final filesToKeep = <String, File>{};
  for (final fileName in dartFiles.keys) {
    for (final matcher in matchers) {
      if (matcher.hasMatch(toPosix(fileName))) {
        filesToKeep[fileName] = dartFiles[fileName]!;
        break;
      }
    }
  }
  return filesToKeep;
}

/// [path] with Windows separators rewritten as `/`.
///
/// Patterns are written with forward slashes — the README, the help text and
/// every example use them — but `Directory.listSync` hands back `\` on
/// Windows, so `lib/src/` matched nothing there. Normalising the path, not the
/// pattern, keeps one pattern working on every platform.
String toPosix(String path) => path.replaceAll('\\', '/');

/// Compiles [patterns] as regular expressions, up front.
///
/// Compiling early means a malformed pattern fails with a message naming it
/// and [label], instead of a raw `RegExp` error thrown mid-scan — and means
/// each pattern is compiled once rather than once per file. Throws a
/// [FormatException]; callers report it and exit.
List<RegExp> compilePatterns(Iterable<String> patterns, String label) {
  final matchers = <RegExp>[];
  for (final pattern in patterns) {
    try {
      matchers.add(RegExp(pattern));
    } on FormatException catch (e) {
      throw FormatException('invalid $label "$pattern": ${e.message}');
    }
  }
  return matchers;
}

List<FileSystemEntity> _readDir(String currentPath, String name) {
  final dir = Directory('$currentPath/$name');
  if (dir.existsSync()) {
    return dir.listSync(recursive: true);
  }
  return [];
}
