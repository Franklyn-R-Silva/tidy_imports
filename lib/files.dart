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

  // Filter to only the files/patterns passed as positional args (if any)
  var onlyCertainFiles = false;
  for (final arg in args) {
    if (!onlyCertainFiles) {
      onlyCertainFiles = arg.endsWith('dart');
    }
  }

  if (onlyCertainFiles) {
    final patterns = args.where((arg) => !arg.startsWith('-'));
    final filesToKeep = <String, File>{};

    // Compile once, up front, so an invalid pattern fails immediately with a
    // message naming it instead of a raw RegExp error mid-scan.
    final matchers = <RegExp>[];
    for (final pattern in patterns) {
      try {
        matchers.add(RegExp(pattern));
      } on FormatException catch (e) {
        throw FormatException('invalid file pattern "$pattern": ${e.message}');
      }
    }

    for (final fileName in dartFiles.keys) {
      var keep = false;
      for (final matcher in matchers) {
        if (matcher.hasMatch(fileName)) {
          keep = true;
          break;
        }
      }
      if (keep) {
        filesToKeep[fileName] = File(fileName);
      }
    }
    return filesToKeep;
  }

  return dartFiles;
}

List<FileSystemEntity> _readDir(String currentPath, String name) {
  final dir = Directory('$currentPath/$name');
  if (dir.existsSync()) {
    return dir.listSync(recursive: true);
  }
  return [];
}
