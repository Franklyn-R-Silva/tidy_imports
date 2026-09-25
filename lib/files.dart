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
/// are pub conventions; `benchmark/` is common; `hook/` holds the build hooks
/// pub runs for every package that depends on this one. Leaving them out made
/// every file — and every dependency — used only from there look unused.
const reportDirectories = ['example', 'tool', 'web', 'benchmark', 'hook'];

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

/// Every file called [name] under `<currentPath>/<dir>`, found by the walk
/// [dartFiles] uses — so no link is followed, and hidden directories and a
/// package's `build/` output are skipped. The report finds sub-package
/// pubspecs with it: a walk of its own that followed links went through a
/// Flutter app's `.plugin_symlinks/` into the pub cache.
List<File> filesNamed(String currentPath, String dir, String name) => [
      for (final entity in _readDir(currentPath, dir))
        if (entity is File && _baseName(entity.path) == name) entity,
    ];

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

/// Every entity under `<currentPath>/<name>`, walked without following links.
///
/// `listSync(recursive: true)` follows links by default, and a Flutter app
/// under `packages/` carries links into the pub cache:
/// `windows/flutter/ephemeral/.plugin_symlinks/` and `ios/.symlinks/plugins/`
/// point at every plugin's own `lib/`. The sorter used to walk through them
/// and rewrite plugin sources that belong to no project at all. A link is now
/// never entered — and a link to a file is a [Link], not a [File], so it is
/// never sorted either.
///
/// Hidden directories (`.dart_tool/`, `.symlinks/`) and a package's `build/`
/// output are generated, so they are pruned too — `build/` only where it sits
/// beside a `pubspec.yaml`, since `lib/src/build/` is ordinary source.
List<FileSystemEntity> _readDir(String currentPath, String name) {
  final root = Directory('$currentPath/$name');
  if (!root.existsSync()) return [];

  final found = <FileSystemEntity>[];
  void walk(Directory directory) {
    final children = directory.listSync(followLinks: false);
    final isPackageRoot =
        children.any((e) => e is File && _baseName(e.path) == 'pubspec.yaml');
    for (final child in children) {
      if (child is! Directory) {
        found.add(child);
        continue;
      }
      final base = _baseName(child.path);
      if (base.startsWith('.') || (isPackageRoot && base == 'build')) continue;
      found.add(child);
      walk(child);
    }
  }

  walk(root);
  return found;
}

/// The last segment of [path], on either separator.
String _baseName(String path) => toPosix(path).split('/').last;
