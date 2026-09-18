// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:args/args.dart';
import 'package:tint/tint.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/args.dart' as local_args;
import 'package:tidy_imports/config.dart';
import 'package:tidy_imports/files.dart' as files;
import 'package:tidy_imports/graph.dart';
import 'package:tidy_imports/pubspec_sort.dart' as pubspec_sort;
import 'package:tidy_imports/sort.dart' as sort;

void main(List<String> args) {
  // Every flag that mirrors a config key is negatable, so `--no-x` can switch
  // off what the config file switched on. `--no-comments` and
  // `--no-blank-lines` keep working: they are the negated forms of the
  // `comments` and `blank-lines` flags, which is exactly how they read before.
  //
  // The rest — asking for help, a version, a dry run — describe this
  // invocation rather than a preference, so there is nothing to negate.
  final parser = ArgParser()
    ..addFlag('emojis', abbr: 'e')
    ..addFlag('comments', defaultsTo: true)
    ..addFlag('blank-lines', defaultsTo: true)
    ..addFlag('sort-pubspec')
    ..addFlag('sort-exports')
    ..addFlag('remove-duplicates')
    ..addFlag('flat')
    ..addFlag('relative-imports')
    ..addFlag('remove-unused')
    ..addFlag('group-by-folder')
    ..addOption('group-by-folder-depth', valueHelp: 'n')
    ..addFlag('separate-relative-imports')
    ..addFlag('test-imports')
    ..addFlag('ignore-config', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', abbr: 'v', negatable: false)
    ..addFlag('exit-if-changed', negatable: false)
    ..addFlag('dry-run', negatable: false)
    ..addFlag('report', negatable: false);

  final argResults = parser.parse(args);

  if (argResults['help'] == true) {
    local_args.outputHelp();
  }

  if (argResults['version'] == true) {
    local_args.outputVersion();
  }

  final currentPath = Directory.current.path;

  final pubspecYamlFile = File('$currentPath/pubspec.yaml');
  if (!pubspecYamlFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found in $currentPath');
    stderr.writeln('Run tidy_imports from the root of your Dart project.');
    exit(1);
  }

  final pubspecYaml = loadYaml(pubspecYamlFile.readAsStringSync());
  final packageName = pubspecYaml['name'] as String;

  // pubspec.lock may be absent in pub workspaces / monorepos where a
  // root-level lock file is used instead. Fall back to empty dependencies
  // (flutter plugin registrant skipping is disabled) rather than crashing.
  final pubspecLockFile = File('$currentPath/pubspec.lock');
  final dependencies = <dynamic>[];
  if (pubspecLockFile.existsSync()) {
    final pubspecLock = loadYaml(pubspecLockFile.readAsStringSync());
    dependencies.addAll((pubspecLock['packages'] as YamlMap).keys);
  }

  final config = argResults['ignore-config'] == true
      ? TidyConfig.fromYaml(null)
      : TidyConfig.load(currentPath, pubspecYaml as YamlMap);

  // A flag the user actually typed wins; otherwise the config decides. This
  // used to be `config.x || flag`, which meant a flag could only ever turn
  // something on — there was no way to opt out of a config key for one run.
  bool resolve(String flag, bool fromConfig) =>
      argResults.wasParsed(flag) ? argResults[flag] as bool : fromConfig;

  final emojis = resolve('emojis', config.emojis);
  // `comments` and `blank-lines` are stated positively on the command line and
  // negatively inside the sorter, so each crosses over once here.
  final noComments = !resolve('comments', !config.noComments);
  final noBlankLines = !resolve('blank-lines', !config.noBlankLines);
  final sortPubspec = resolve('sort-pubspec', config.sortPubspec);
  final sortExports = resolve('sort-exports', config.sortExports);
  final removeDuplicates =
      resolve('remove-duplicates', config.removeDuplicates);
  final removeUnused = resolve('remove-unused', config.removeUnused);
  final flat = resolve('flat', config.flat);
  final relativeImports = resolve('relative-imports', config.relativeImports);
  final groupByFolder = resolve('group-by-folder', config.groupProjectByFolder);

  // A depth is a count of folder segments, so anything but a non-negative
  // integer is a user error — reported the way a bad file pattern is, not as
  // a stack trace.
  final depthArg = argResults['group-by-folder-depth'] as String?;
  var groupByFolderDepth = config.groupProjectByFolderDepth;
  if (depthArg != null) {
    final parsed = int.tryParse(depthArg);
    if (parsed == null || parsed < 0) {
      stderr.writeln(
        'Error: --group-by-folder-depth expects a non-negative integer, '
        'got "$depthArg".',
      );
      exit(1);
    }
    groupByFolderDepth = parsed;
  }

  // A configured depth turns folder grouping on all by itself, so an explicit
  // `--no-group-by-folder` has to clear it too or the flag would do nothing.
  if (argResults.wasParsed('group-by-folder') && !groupByFolder) {
    groupByFolderDepth = 0;
  }

  final separateRelativeImports =
      resolve('separate-relative-imports', config.separateRelativeImports);
  final testImports = resolve('test-imports', config.testImports);
  final customTiers = config.customTiers;
  final ignoredFiles = config.ignoredFiles;
  final exitOnChange = argResults['exit-if-changed'] == true;
  final dryRun = argResults['dry-run'] == true;

  // File patterns are regular expressions; a malformed one is a user error,
  // not a crash.
  final Map<String, File> dartFiles;
  try {
    dartFiles = files.dartFiles(currentPath, argResults.rest);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  }

  // Matched on the normalised relative path, the way ignored_files are: the
  // keys use the platform separator, so an exact-string check against a
  // '/'-joined path never matched on Windows and the registrant got sorted.
  final containsFlutter = dependencies.contains('flutter');
  if (containsFlutter) {
    dartFiles.removeWhere((key, _) =>
        files.toPosix(key.replaceFirst(currentPath, '')) == _registrant);
  }

  // `ignored_files` patterns are regular expressions too, and a malformed one
  // used to surface as a raw stack trace from inside removeWhere. Compile them
  // the same way positional patterns are compiled: once, up front, reported as
  // the user error they are.
  final List<RegExp> ignoreMatchers;
  try {
    ignoreMatchers = files.compilePatterns(ignoredFiles, 'ignored_files entry');
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  }

  for (final matcher in ignoreMatchers) {
    dartFiles.removeWhere(
      (key, _) =>
          matcher.hasMatch(files.toPosix(key.replaceFirst(currentPath, ''))),
    );
  }

  // Both dry-run and exit-if-changed are read-only: they never write files.
  final readOnly = dryRun || exitOnChange;

  // `--report` answers questions about the project rather than tidying it, so
  // it runs on its own and writes nothing at all. It also discovers on its
  // own: the file set above is what the *sorter* touches, and using it as the
  // graph's node set deleted every edge leaving a filtered-out file.
  if (argResults['report'] == true) {
    exit(_report(
      currentPath,
      packageName,
      pubspecYaml as YamlMap,
      patterns: argResults.rest,
      ignoreMatchers: ignoreMatchers,
      reportRoots: config.reportRoots,
      failOnFindings: exitOnChange,
    ));
  }

  final label = readOnly ? 'Checking' : 'Sorting';
  stdout.write('┏━━ $label ${dartFiles.length} dart files');
  if (dryRun) stdout.write(' (dry run — no files will be written)');

  final stopwatch = Stopwatch()..start();
  final sortedFiles = <String>[];
  var duplicatesRemoved = 0;
  var unreadable = 0;
  final success = '✔'.green();

  // Whether an import is *used* is a question about resolved elements, not
  // about text, and this tool deliberately never resolves anything. The
  // analyzer already answers it — and ships with every SDK — so `dart fix`
  // does the removal and the sort that follows tidies up the gaps it leaves.
  if (removeUnused) {
    final code = _removeUnusedImports(currentPath, readOnly: readOnly);
    if (code != 0) exit(code);
  }

  for (final filePath in dartFiles.keys) {
    final file = dartFiles[filePath];
    if (file == null) continue;

    // Preserve the file's original line ending (CRLF on Windows) instead of
    // silently rewriting to LF, which creates spurious diffs and git noise.
    final String rawContent;
    try {
      rawContent = file.readAsStringSync();
    } on FileSystemException catch (e) {
      // A Latin-1 file, or one we may not read. Skipping it is safe here —
      // it simply stays unsorted — but it is still an error, reported once.
      // The header line above is still open; close it before the first error.
      stderr.writeln(
        '${unreadable == 0 ? '\n' : ''}Error: could not read '
        '${files.toPosix(filePath.replaceFirst(currentPath, ''))}: '
        '${e.osError?.message ?? e.message}',
      );
      unreadable++;
      continue;
    }
    final usesCrlf = rawContent.contains('\r\n');

    // The third positional argument is the deprecated, inert `exitIfChanged`.
    // Checking is this loop's job: it runs over the whole project and fails
    // once at the end, so every unsorted file is reported instead of the run
    // aborting on the first one (issue import_sorter#87).
    final result = sort.sortImports(
      const LineSplitter().convert(rawContent),
      packageName,
      emojis,
      false,
      noComments,
      noBlankLines: noBlankLines,
      customTiers: customTiers,
      groupProjectByFolder: groupByFolder,
      testImports: testImports,
      testImportPrefixes: config.testImportPrefixes,
      separateRelativeImports: separateRelativeImports,
      sortExports: sortExports,
      groupProjectByFolderDepth: groupByFolderDepth,
      removeDuplicates: removeDuplicates,
      flat: flat,
      relativeImports: relativeImports,
      libRelativePath: _libRelativePath(currentPath, filePath),
    );
    duplicatesRemoved += result.duplicatesRemoved;
    if (!result.updated) continue;

    final output = usesCrlf
        ? result.sortedFile.replaceAll('\n', '\r\n')
        : result.sortedFile;
    if (!readOnly) file.writeAsStringSync(output);
    sortedFiles.add(filePath);
  }

  stopwatch.stop();

  if (sortedFiles.length > 1) stdout.write('\n');

  final verb = exitOnChange
      ? 'Needs sorting:'
      : (dryRun ? 'Would sort' : 'Sorted imports for');
  for (var i = 0; i < sortedFiles.length; i++) {
    final file = dartFiles[sortedFiles[i]]!;
    final relativePath = file.path.replaceFirst(currentPath, '');
    final isLast = i == sortedFiles.length - 1;
    stdout.writeln(
      '${sortedFiles.length == 1 ? '\n' : ''}┃  ${isLast ? '┗' : '┣'}━━ $success $verb $relativePath',
    );
  }

  if (sortedFiles.isEmpty) stdout.write('\n');

  final elapsed = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
  final action = exitOnChange ? 'Checked' : (dryRun ? 'Would sort' : 'Sorted');
  final folded = duplicatesRemoved == 0
      ? ''
      : ', ${dryRun || exitOnChange ? 'found' : 'dropped'} $duplicatesRemoved '
          'duplicate ${duplicatesRemoved == 1 ? 'import' : 'imports'}';
  stdout.writeln(
      '┗━━ $success $action ${sortedFiles.length} files$folded in ${elapsed}s');

  // Optionally sort pubspec.yaml dependency sections (issue import_sorter#89).
  var pubspecUnsorted = false;
  if (sortPubspec) {
    final original = pubspecYamlFile.readAsStringSync();
    final sorted = pubspec_sort.sortPubspec(original);
    if (sorted != original) {
      pubspecUnsorted = true;
      if (!readOnly) pubspecYamlFile.writeAsStringSync(sorted);
      final pubspecVerb =
          exitOnChange ? 'Needs sorting:' : (dryRun ? 'Would sort' : 'Sorted');
      stdout.writeln('$success $pubspecVerb pubspec.yaml dependencies');
    }
  }

  if (unreadable > 0) {
    stderr.writeln('\n🚨 $unreadable file(s) could not be read.');
    exit(1);
  }

  // In CI mode, fail after reporting everything that needs attention.
  if (exitOnChange && (sortedFiles.isNotEmpty || pubspecUnsorted)) {
    final count = sortedFiles.length + (pubspecUnsorted ? 1 : 0);
    stderr.writeln(
      '\n🚨 $count file(s) are not sorted. Run `dart run tidy_imports` to fix.',
    );
    exit(1);
  }
}

/// Runs `dart fix` for `unused_import` over [projectPath].
///
/// Returns 0 to carry on, or an exit code to stop with. Under [readOnly] it
/// only reports: `--dry-run` and `--exit-if-changed` promise not to write, and
/// that promise has to cover the fixes too.
///
/// This shells out on purpose. Knowing an import is unused means resolving
/// every identifier in the file to the library that declares it — extension
/// methods and all — and the analyzer that ships with the SDK already does it
/// correctly. Reimplementing it on top of text matching would remove imports
/// that are in use.
int _removeUnusedImports(String projectPath, {required bool readOnly}) {
  final dart = _dartExecutable();
  final args = [
    'fix',
    readOnly ? '--dry-run' : '--apply',
    '--code=unused_import',
  ];

  stdout.writeln(
    '┏━━ ${readOnly ? 'Checking for' : 'Removing'} unused imports '
    '(${[dart.split(Platform.pathSeparator).last, ...args].join(' ')})',
  );

  final ProcessResult result;
  try {
    result = Process.runSync(dart, args, workingDirectory: projectPath);
  } on ProcessException catch (e) {
    stderr.writeln('Error: could not run `dart fix`: ${e.message}');
    stderr.writeln('--remove-unused needs the Dart SDK on PATH.');
    return 1;
  }

  final output = '${result.stdout}'.trim();
  if (output.isNotEmpty) stdout.writeln(output);

  if (result.exitCode != 0) {
    stderr.writeln('${result.stderr}'.trim());
    stderr.writeln(
      'Error: `dart fix` failed. It needs a project that resolves — try '
      '`dart pub get` first.',
    );
    return result.exitCode;
  }
  return 0;
}

/// The `dart` binary to shell out to.
///
/// [Platform.resolvedExecutable] is the Dart VM when the tool runs through
/// `dart run`, which is the common case and the most reliable answer. Compiled
/// to an executable it is *this* binary instead, so fall back to PATH.
String _dartExecutable() {
  final resolved = Platform.resolvedExecutable;
  final name = resolved.split(Platform.pathSeparator).last.toLowerCase();
  return (name == 'dart' || name == 'dart.exe') ? resolved : 'dart';
}

/// [filePath] written relative to `lib/`, with `/` separators — or null when
/// the file does not live under `lib/`.
///
/// Only a file inside `lib/` can be reached from another one by a relative
/// URI. A test or a script importing the package has to say `package:`, so
/// there is no relative form to rewrite to and the option simply does nothing
/// there.
String? _libRelativePath(String projectPath, String filePath) {
  const lib = '/lib/';
  final relative = files.toPosix(filePath.replaceFirst(projectPath, ''));
  return relative.startsWith(lib) ? relative.substring(lib.length) : null;
}

/// The Flutter web plugin registrant, generated and self-contained.
const _registrant = '/lib/generated_plugin_registrant.dart';

/// Prints what the project's own import graph says about it.
///
/// Returns the exit code: 1 when [failOnFindings] and something was found, so
/// `--report --exit-if-changed` can hold a line in CI, 0 otherwise. Also 1
/// when a file could not be read at all — a graph missing a node is missing
/// every edge that left it, which turns a crash into a wrong answer.
///
/// Discovery is the report's own and wider than the sorter's:
/// [files.reportDirectories] hold importers nobody wants reformatted.
/// [patterns] and [ignoreMatchers] narrow what is *printed*, never what is
/// *read* — a filter that removed nodes also removed their edges, and
/// everything they imported looked dead.
int _report(
  String currentPath,
  String packageName,
  YamlMap pubspec, {
  required List<String> patterns,
  required List<RegExp> ignoreMatchers,
  required List<String> reportRoots,
  required bool failOnFindings,
}) {
  final scanned = files.dartFiles(
    currentPath,
    const [],
    extraDirectories: files.reportDirectories,
  );

  if (scanned.isEmpty) {
    final dirs = [...files.standardDirectories, ...files.reportDirectories];
    stdout.writeln('┏━━ Reading the import graph');
    stdout.writeln('┗━━ ${'!'.yellow()} No Dart files under ${dirs.join(', ')} '
        '— nothing to report');
    if (failOnFindings) {
      stderr.writeln('🚨 --exit-if-changed with nothing to check. '
          'Run from the project root.');
      return 1;
    }
    return 0;
  }

  // Positional patterns were compiled once already in main(); a bad one has
  // exited by now, so this cannot throw.
  final scopeMatchers = files.compilePatterns(patterns, 'file pattern');
  final List<RegExp> rootMatchers;
  try {
    rootMatchers = files.compilePatterns(reportRoots, 'report_roots entry');
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 1;
  }

  // Node names: project-relative, '/'-separated, no leading slash.
  String relative(String absolute) => files
      .toPosix(absolute.replaceFirst(currentPath, ''))
      .replaceFirst(RegExp('^/'), '');

  final directives = <String, List<String>>{};
  final absolutes = <String, String>{};
  final mains = <String>{};
  final unreadable = <String>[];
  for (final entry in scanned.entries) {
    final path = relative(entry.key);
    absolutes[path] = files.toPosix(entry.key);
    final List<String> lines;
    try {
      // Directives are ASCII. A Latin-1 comment must not cost the file its
      // place in the graph, so decode leniently instead of failing.
      lines = const LineSplitter().convert(
        utf8.decode(entry.value.readAsBytesSync(), allowMalformed: true),
      );
    } on FileSystemException catch (e) {
      unreadable.add('$path: ${e.osError?.message ?? e.message}');
      continue;
    }
    directives[path] = sort.directiveUris(lines);
    if (sort.declaresMain(lines)) mains.add(path);
  }

  if (unreadable.isNotEmpty) {
    for (final failure in unreadable) {
      stderr.writeln('Error: could not read $failure');
    }
    stderr.writeln('🚨 ${unreadable.length} file(s) could not be read; a graph '
        'with a node missing would report every file it imports as dead.');
    return 1;
  }

  final packages = _subPackages(currentPath);
  final graph = ImportGraph.build(directives, packageName, packages: packages);

  // An entry point is unreferenced by definition. `flutter create` writes
  // `publish_to: none`, so a package that says so — or that has lib/main.dart
  // — is an app; anything else is a library, whose public surface is every
  // file outside lib/src (pub convention) and is imported by consumers, not
  // by itself.
  final isApp = '${pubspec['publish_to']}' == 'none' ||
      directives.containsKey('lib/main.dart');
  final roots = <String>{
    'lib/main.dart',
    'lib/$packageName.dart',
    _registrant.substring(1),
    ...mains,
    for (final entry in packages.entries) ...[
      '${entry.key}/lib/${entry.value}.dart',
      '${entry.key}/lib/main.dart',
    ],
  };
  final flavourMain = RegExp(r'^(?:.*/)?lib/main_[a-z0-9_]+\.dart$');
  for (final path in directives.keys) {
    final libRoot = graph.libraryRoot(path);
    if (libRoot == null) continue;
    if (flavourMain.hasMatch(path)) roots.add(path);
    // A sub-package's app-ness is unknown; treating it as a library is the
    // conservative side, since it reports less.
    final isLibrary = libRoot != 'lib/' || !isApp;
    if (isLibrary && !path.startsWith('${libRoot}src/')) roots.add(path);
    if (rootMatchers.any((m) => m.hasMatch('/$path'))) roots.add(path);
  }

  bool inScope(String path) =>
      (scopeMatchers.isEmpty ||
          scopeMatchers.any((m) => m.hasMatch(absolutes[path]!))) &&
      !ignoreMatchers.any((m) => m.hasMatch('/$path'));

  final groups = graph.cycles().where((g) => g.any(inScope)).toList();
  final dead = graph.unreachable(roots: roots).where(inScope).toList();

  stdout.writeln('┏━━ Reading the import graph of ${directives.length} files');

  if (groups.isEmpty) {
    stdout.writeln('┃  ${'✔'.green()} No import cycles');
  } else {
    stdout.writeln('┃  ${'✖'.red()} ${groups.length} '
        '${groups.length == 1 ? 'group' : 'groups'} of files that import '
        'each other:');
    for (final group in groups) {
      final walk = graph.cycleWalk(group);
      final rest = group.length - walk.length;
      stdout.writeln('┃     ${walk.join(' → ')} → ${walk.first}'
          '${rest > 0 ? '  (+$rest more in this group)' : ''}');
    }
  }

  if (dead.isEmpty) {
    stdout.writeln('┃  ${'✔'.green()} Every file under lib/ is reachable '
        'from an entry point');
  } else {
    stdout.writeln('┃  ${'!'.yellow()} ${dead.length} '
        '${dead.length == 1 ? 'file' : 'files'} no entry point reaches:');
    for (final path in dead) {
      stdout.writeln('┃     $path');
    }
    stdout.writeln('┃     (build_runner, reflection and dynamic loading are '
        'invisible here — read before deleting)');
  }

  final findings = groups.length + dead.length;
  stdout.writeln('┗━━ ${findings == 0 ? '✔'.green() : '•'} '
      '$findings ${findings == 1 ? 'finding' : 'findings'}');

  if (failOnFindings && findings > 0) {
    stderr.writeln('\n🚨 $findings ${findings == 1 ? 'finding' : 'findings'} '
        'in the import graph. Failing because --exit-if-changed was passed.');
    return 1;
  }
  return 0;
}

/// Every sub-package under `packages/`, as directory -> name, read from each
/// one's pubspec. Without this a monorepo's `package:core/x.dart` never
/// resolved, and its cycles and dead files were silently invisible.
Map<String, String> _subPackages(String currentPath) {
  final found = <String, String>{};
  final root = Directory('$currentPath/packages');
  if (!root.existsSync()) return found;

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('pubspec.yaml')) continue;
    final dir = files
        .toPosix(entity.parent.path.replaceFirst(currentPath, ''))
        .replaceFirst(RegExp('^/'), '');
    if (dir.contains('/.') || dir.contains('/build/')) continue;
    try {
      final name = (loadYaml(entity.readAsStringSync()) as YamlMap?)?['name'];
      if (name is String) found[dir] = name;
    } on Object {
      // A pubspec that does not parse belongs to no package we can name.
    }
  }
  return found;
}
