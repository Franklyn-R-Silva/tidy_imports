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

  final containsFlutter = dependencies.contains('flutter');
  final registrantPath = '$currentPath/lib/generated_plugin_registrant.dart';
  if (containsFlutter && dartFiles.containsKey(registrantPath)) {
    dartFiles.remove(registrantPath);
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
  // it runs on its own and writes nothing at all.
  if (argResults['report'] == true) {
    exit(_report(dartFiles, currentPath, packageName,
        failOnFindings: exitOnChange));
  }

  final label = readOnly ? 'Checking' : 'Sorting';
  stdout.write('┏━━ $label ${dartFiles.length} dart files');
  if (dryRun) stdout.write(' (dry run — no files will be written)');

  final stopwatch = Stopwatch()..start();
  final sortedFiles = <String>[];
  var duplicatesRemoved = 0;
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
    final rawContent = file.readAsStringSync();
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

/// Prints what the project's own import graph says about it.
///
/// Returns the exit code: 1 when [failOnFindings] and something was found, so
/// `--report --exit-if-changed` can hold a line in CI, 0 otherwise.
int _report(
  Map<String, File> dartFiles,
  String currentPath,
  String packageName, {
  required bool failOnFindings,
}) {
  final directives = <String, List<String>>{};
  for (final entry in dartFiles.entries) {
    final path = files
        .toPosix(entry.key.replaceFirst(currentPath, ''))
        .replaceFirst(RegExp('^/'), '');
    directives[path] = sort.directiveUris(
        const LineSplitter().convert(entry.value.readAsStringSync()));
  }

  final graph = ImportGraph.build(directives, packageName);
  final cycles = graph.cycles();

  // An entry point is unreferenced by definition. `lib/<package>.dart` is the
  // package's public face, `lib/main.dart` an app's; everything outside `lib/`
  // is already excluded by [ImportGraph.unreferenced].
  final orphans = graph.unreferenced(roots: {
    'lib/$packageName.dart',
    'lib/main.dart',
  });

  stdout.writeln('┏━━ Reading the import graph of ${directives.length} files');

  if (cycles.isEmpty) {
    stdout.writeln('┃  ${'✔'.green()} No import cycles');
  } else {
    stdout.writeln('┃  ${'✖'.red()} ${cycles.length} import '
        '${cycles.length == 1 ? 'cycle' : 'cycles'}:');
    for (final cycle in cycles) {
      stdout.writeln('┃     ${cycle.join(' → ')} → ${cycle.first}');
    }
  }

  if (orphans.isEmpty) {
    stdout.writeln('┃  ${'✔'.green()} Every file under lib/ is referenced');
  } else {
    stdout.writeln('┃  ${'!'.yellow()} ${orphans.length} '
        '${orphans.length == 1 ? 'file' : 'files'} nothing refers to:');
    for (final orphan in orphans) {
      stdout.writeln('┃     $orphan');
    }
    stdout.writeln('┃     (build_runner, reflection and dynamic loading are '
        'invisible here — read before deleting)');
  }

  final findings = cycles.length + orphans.length;
  stdout.writeln('┗━━ ${findings == 0 ? '✔'.green() : '•'} '
      '$findings ${findings == 1 ? 'finding' : 'findings'}');

  return failOnFindings && findings > 0 ? 1 : 0;
}
