// Dart imports:
import 'dart:io';

/// Returns all dart files found in standard project directories.
///
/// Positional [args] are treated as regular expressions matched against the
/// absolute file path. Throws a [FormatException] with a readable message if a
/// pattern is not valid — callers are expected to report it and exit.
Map<String, File> dartFiles(String currentPath, List<String> args) {
  final dartFiles = <String, File>{};
  final allContents = [
    ..._readDir(currentPath, 'lib'),
    ..._readDir(currentPath, 'src'),
    ..._readDir(currentPath, 'bin'),
    ..._readDir(currentPath, 'test'),
    ..._readDir(currentPath, 'tests'),
    ..._readDir(currentPath, 'test_driver'),
    ..._readDir(currentPath, 'integration_test'),
    ..._readDir(currentPath, 'packages'),
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
