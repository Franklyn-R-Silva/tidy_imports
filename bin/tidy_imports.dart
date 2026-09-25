// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Package imports:
import 'package:args/args.dart';
import 'package:tint/tint.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:tidy_imports/args.dart' as local_args;
import 'package:tidy_imports/config.dart';
import 'package:tidy_imports/config_edit.dart';
import 'package:tidy_imports/doctor.dart';
import 'package:tidy_imports/files.dart' as files;
import 'package:tidy_imports/graph.dart';
import 'package:tidy_imports/graph_export.dart';
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
    ..addFlag('package-imports')
    ..addFlag('attach-comments')
    ..addFlag('remove-unused')
    ..addFlag('group-by-folder')
    ..addOption('group-by-folder-depth', valueHelp: 'n')
    ..addFlag('separate-relative-imports')
    ..addFlag('test-imports')
    ..addFlag('ignore-config', negatable: false)
    ..addFlag('strict-config', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', abbr: 'v', negatable: false)
    ..addFlag('exit-if-changed', negatable: false)
    ..addFlag('dry-run', negatable: false)
    ..addFlag('report', negatable: false)
    ..addOption(
      'format',
      allowed: const ['text', 'mermaid', 'dot', 'json'],
      defaultsTo: 'text',
      valueHelp: 'text|mermaid|dot|json',
    )
    ..addOption('feature-depth', valueHelp: 'n')
    ..addFlag('doctor', negatable: false)
    ..addFlag('apply', negatable: false);

  // A typo in a flag is the same kind of mistake as a typo in a file pattern,
  // and used to be the one that printed a stack trace: `ArgParserException`
  // reached the top of main() with eight frames of `package:args` under it.
  final ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Run `tidy_imports --help` for the options.');
    exit(1);
  }

  if (argResults['help'] == true) {
    local_args.outputHelp();
  }

  if (argResults['version'] == true) {
    local_args.outputVersion();
  }

  final doctor = argResults['doctor'] == true;
  if (argResults['apply'] == true && !doctor) {
    stderr.writeln(
      'Error: --apply writes what --doctor suggests, so it only works with '
      '--doctor.',
    );
    exit(1);
  }
  if (doctor && argResults['report'] == true) {
    stderr.writeln(
      'Error: --doctor and --report are separate run modes. Pass one of them.',
    );
    exit(1);
  }
  for (final option in const ['format', 'feature-depth']) {
    if (argResults.wasParsed(option) && argResults['report'] != true) {
      stderr.writeln(
        'Error: --$option shapes what --report prints, so it only works with '
        '--report.',
      );
      exit(1);
    }
  }

  final currentPath = Directory.current.path;

  final pubspecYamlFile = File('$currentPath/pubspec.yaml');
  if (!pubspecYamlFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found in $currentPath');
    stderr.writeln('Run tidy_imports from the root of your Dart project.');
    exit(1);
  }

  final dynamic parsedPubspec;
  try {
    parsedPubspec = loadYaml(pubspecYamlFile.readAsStringSync());
  } on Object catch (e) {
    // A YamlException draws the offending snippet over four more lines; the
    // first one carries the position, which is the half worth printing.
    stderr.writeln('Error: pubspec.yaml could not be read: '
        '${'$e'.split('\n').first}');
    exit(1);
  }
  if (parsedPubspec is! YamlMap) {
    stderr.writeln('Error: pubspec.yaml is not a map of keys.');
    exit(1);
  }
  final pubspecYaml = parsedPubspec;

  // The package name is what tells your own imports from everyone else's, so
  // there is no useful run without it. It used to fail as
  // `type 'Null' is not a subtype of type 'String' in type cast`.
  final declaredName = pubspecYaml['name'];
  if (declaredName is! String || declaredName.isEmpty) {
    stderr.writeln('Error: pubspec.yaml declares no `name:`.');
    stderr.writeln(
      'tidy_imports needs it to tell the imports of your own package from '
      'the ones that come from pub.',
    );
    exit(1);
  }
  final packageName = declaredName;

  // pubspec.lock may be absent in pub workspaces / monorepos where a
  // root-level lock file is used instead. Fall back to empty dependencies
  // (flutter plugin registrant skipping is disabled) rather than crashing.
  final pubspecLockFile = File('$currentPath/pubspec.lock');
  final dependencies = <dynamic>[];
  if (pubspecLockFile.existsSync()) {
    try {
      final pubspecLock = loadYaml(pubspecLockFile.readAsStringSync());
      final packages = pubspecLock is YamlMap ? pubspecLock['packages'] : null;
      if (packages is YamlMap) dependencies.addAll(packages.keys);
    } on Object {
      // Same fallback as no lock file at all: the only thing the list feeds is
      // Flutter plugin-registrant skipping, which is not worth a failed run.
    }
  }

  final config = argResults['ignore-config'] == true
      ? TidyConfig.fromYaml(null)
      : TidyConfig.load(currentPath, pubspecYaml);

  // Configuration problems are said out loud, and this is the only place that
  // says them — `lib/` collects them as data and prints nothing.
  //
  // They used to be invisible. A file in the pubspec shape, or a key with a
  // typo in it, was read, understood as nothing, and replaced by defaults: the
  // run reported success while doing the opposite of what the file asked for,
  // and there was no output anywhere to suggest otherwise. So a warning is the
  // default, not an opt-in — a diagnostic nobody turns on would leave the
  // silence exactly where it was.
  //
  // `--strict-config` is for CI, where "it warned" and "nobody read it" are
  // the same thing. It exits before the first file is touched: a refusal that
  // had already rewritten the project would be a strange kind of refusal.
  if (config.issues.isNotEmpty) {
    final strictConfig = argResults['strict-config'] == true;
    for (final issue in config.issues) {
      stderr.writeln('${strictConfig ? 'Error' : 'Warning'}: $issue');
    }
    if (strictConfig) {
      stderr.writeln(
        'Refusing to run under --strict-config. Fix the configuration, or '
        'drop the flag to continue with the defaults it fell back to.',
      );
      exit(1);
    }
  }

  // `--doctor` judges the configuration — what every future run reads — so it
  // runs before any flag is resolved against it, and touches no Dart file.
  if (doctor) {
    final exitOnChange = argResults['exit-if-changed'] == true;
    exit(_doctor(
      currentPath,
      config,
      apply: argResults['apply'] == true,
      readOnly: exitOnChange || argResults['dry-run'] == true,
      failOnFindings: exitOnChange,
    ));
  }

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
  var relativeImports = resolve('relative-imports', config.relativeImports);
  var packageImports = resolve('package-imports', config.packageImports);

  // The two rewrite in opposite directions. A config asking for both already
  // got neither (and an issue saying so), so a clash here involves a flag: one
  // typed flag simply wins over the config for this run, two are a mistake.
  if (relativeImports && packageImports) {
    final typedRelative = argResults.wasParsed('relative-imports');
    final typedPackage = argResults.wasParsed('package-imports');
    if (typedRelative && typedPackage) {
      stderr.writeln(
        'Error: --relative-imports and --package-imports rewrite in opposite '
        'directions. Pass one of them.',
      );
      exit(1);
    }
    if (typedRelative) packageImports = false;
    if (typedPackage) relativeImports = false;
  }

  final attachComments = resolve('attach-comments', config.attachComments);
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
    // Features are counted in folders, so anything but a whole number from 1
    // up is a user error, said the way a bad --group-by-folder-depth is.
    var featureDepth = config.featureDepth;
    final featureDepthArg = argResults['feature-depth'] as String?;
    if (featureDepthArg != null) {
      final parsed = int.tryParse(featureDepthArg);
      if (parsed == null || parsed < 1) {
        stderr.writeln(
          'Error: --feature-depth expects a whole number of folders, 1 or '
          'more, got "$featureDepthArg".',
        );
        exit(1);
      }
      featureDepth = parsed;
    }

    exit(_report(
      currentPath,
      packageName,
      pubspecYaml,
      patterns: argResults.rest,
      ignoreMatchers: ignoreMatchers,
      reportRoots: config.reportRoots,
      failOnFindings: exitOnChange,
      format: argResults['format'] as String,
      featureDepth: featureDepth,
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
      packageImports: packageImports,
      attachComments: attachComments,
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
  required String format,
  required int featureDepth,
}) {
  final text = format == 'text';
  final scanned = files.dartFiles(
    currentPath,
    const [],
    extraDirectories: files.reportDirectories,
  );

  if (scanned.isEmpty) {
    final dirs = [...files.standardDirectories, ...files.reportDirectories];
    if (text) {
      stdout.writeln('┏━━ Reading the import graph');
      stdout.writeln('┗━━ ${'!'.yellow()} No Dart files under '
          '${dirs.join(', ')} — nothing to report');
    } else {
      // The artifact is the whole of stdout, so the sentence goes elsewhere.
      stderr.writeln('No Dart files under ${dirs.join(', ')} — nothing to '
          'report.');
    }
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

  final scope = directives.keys.where(inScope).toList();
  final groups = graph.cycles().where((g) => g.any(inScope)).toList();
  final dead = graph.unreachable(roots: roots).where(inScope).toList();
  final findings = groups.length + dead.length;

  // A drawing is of the library — what the architecture is made of. Tests,
  // tools and examples still count as importers above; drawn, they would bury
  // it.
  final drawn = scope.where(graph.isLibraryFile);
  switch (format) {
    case 'json':
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(reportJson(
        graph,
        packageName: packageName,
        files: scope,
        cycles: groups,
        unreachable: dead,
        featureDepth: featureDepth,
      )));
    case 'dot':
      stdout.write(toDot(
        graph,
        nodes: drawn,
        unreachable: dead.toSet(),
        featureDepth: featureDepth,
      ));
    case 'mermaid':
      final edges = drawnEdges(graph, drawn);
      if (edges > mermaidEdgeLimit) {
        stderr.writeln('Warning: $edges edges is past the $mermaidEdgeLimit '
            'Mermaid draws by default — GitHub shows an error box instead of '
            'the diagram. Narrow it with a pattern (e.g. "lib/features/auth/"), '
            'or use --format=dot.');
      }
      stdout.write(toMermaid(
        graph,
        nodes: drawn,
        unreachable: dead.toSet(),
        featureDepth: featureDepth,
      ));
    default:
      _printReport(
        graph,
        files: directives.length,
        groups: groups,
        dead: dead,
        scope: scope,
        featureDepth: featureDepth,
        findings: findings,
      );
  }

  if (failOnFindings && findings > 0) {
    stderr.writeln('\n🚨 $findings ${findings == 1 ? 'finding' : 'findings'} '
        'in the import graph. Failing because --exit-if-changed was passed.');
    return 1;
  }
  return 0;
}

/// The text form of `--report`: findings first, then what the graph says
/// about the shape of the code.
void _printReport(
  ImportGraph graph, {
  required int files,
  required List<List<String>> groups,
  required List<String> dead,
  required List<String> scope,
  required int featureDepth,
  required int findings,
}) {
  stdout.writeln('┏━━ Reading the import graph of $files files');

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

  _printMetrics(graph, scope: scope, depth: featureDepth);

  stdout.writeln('┗━━ ${findings == 0 ? '✔'.green() : '•'} '
      '$findings ${findings == 1 ? 'finding' : 'findings'}');
}

/// The ranked lists and the feature coupling. Informational: none of it is a
/// finding, so none of it fails `--exit-if-changed`.
void _printMetrics(
  ImportGraph graph, {
  required List<String> scope,
  required int depth,
}) {
  const top = 5;
  final inScope = scope.toSet();

  void ranked(String title, Map<String, int> counts) {
    final entries = counts.entries
        .where((e) => e.value > 0 && inScope.contains(e.key))
        .toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    if (entries.isEmpty) return;
    final shown = entries.take(top).toList();
    final width = '${shown.first.value}'.length;
    stdout.writeln('┃  $title');
    for (final entry in shown) {
      stdout.writeln('┃     ${'${entry.value}'.padLeft(width)}  ${entry.key}');
    }
  }

  ranked('Most imported:', graph.fanIn());
  ranked('Imports the most:', graph.fanOut());

  final features = graph.features(depth);
  if (features.length > 1) {
    final width = features.map((f) => f.name.length).reduce(max);
    stdout.writeln('┃  Features at feature_depth $depth — files, imports in '
        'and out, instability:');
    for (final feature in features) {
      final instability = feature.instability?.toStringAsFixed(2) ?? '—';
      stdout.writeln('┃     ${feature.name.padRight(width)}  '
          '${'${feature.files}'.padLeft(4)} files  '
          'in ${'${feature.afferent}'.padLeft(3)}  '
          'out ${'${feature.efferent}'.padLeft(3)}  I $instability');
    }

    final pairs = graph.coupling(depth).take(top).toList();
    if (pairs.isNotEmpty) {
      stdout.writeln('┃  Strongest coupling:');
      for (final pair in pairs) {
        stdout.writeln('┃     ${pair.from} → ${pair.to}  '
            '(${pair.edges} ${pair.edges == 1 ? 'import' : 'imports'})');
      }
    }
  }

  // One folder holding most of lib/ means the depth is one short of the
  // layout: `lib/features/<name>/` is a single feature called `features` at 1.
  final total = features.fold<int>(0, (sum, f) => sum + f.files);
  if (total >= 10 && features.isNotEmpty) {
    final biggest = features.reduce((a, b) => b.files > a.files ? b : a);
    final splits = graph.edges.keys.any((file) =>
        graph.featureOf(file, depth) == biggest.name &&
        graph.featureOf(file, depth + 1) != biggest.name);
    if (biggest.files / total > 0.6 && splits) {
      stdout.writeln('┃  • ${(100 * biggest.files / total).round()}% of the '
          'library sits in ${biggest.name} — feature_depth: ${depth + 1} '
          'splits it');
    }
  }
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

/// Says whether the configuration agrees with the lints in force, and with
/// `dart format`, and — under [apply] — writes the keys that make it agree.
///
/// Returns the exit code: 1 under [failOnFindings] while a conflict or a fight
/// is left standing, 0 otherwise.
///
/// Every flag in this tool used to be something the user had to know to look
/// for: `--flat` exists because of `directives_ordering`, and nothing said so
/// to someone who had that lint on. This reads `analysis_options.yaml` — the
/// nearest one, as the analyzer does, following its `include:` chain — and
/// says it.
int _doctor(
  String currentPath,
  TidyConfig config, {
  required bool apply,
  required bool readOnly,
  required bool failOnFindings,
}) {
  final options = _findUp(currentPath, 'analysis_options.yaml');
  final packageDirs = _packageDirs(currentPath);
  final lints = options == null
      ? const LintState({})
      : readLints(
          files.toPosix(options.path),
          read: (path) {
            try {
              final file = File(path);
              return file.existsSync() ? file.readAsStringSync() : null;
            } on FileSystemException {
              return null;
            }
          },
          packageDir: (name) => packageDirs[name],
        );

  final findings = diagnose(
    lints,
    config,
    formatterSeparates: _formatterSeparates(Platform.version),
  );

  final shown = options == null
      ? 'analysis_options.yaml'
      : files
          .toPosix(options.path.replaceFirst(currentPath, ''))
          .replaceFirst(RegExp('^/'), '');
  stdout.writeln('┏━━ Checking the tidy_imports configuration against $shown');

  if (options == null) {
    stdout.writeln('┃  • No analysis_options.yaml here or above — no lint to '
        'agree with');
  } else {
    final inForce = importLints.where(lints.has).toList();
    stdout.writeln(inForce.isEmpty
        ? '┃  ${'✔'.green()} None of ${importLints.join(', ')} is on'
        : '┃  Lints that read imports: ${inForce.join(', ')}');
  }
  for (final problem in lints.problems) {
    _say('${'!'.yellow()} $problem');
  }

  for (final finding in findings) {
    final mark = switch (finding.kind) {
      FindingKind.conflict || FindingKind.fight => '✖'.red(),
      FindingKind.suggestion => '!'.yellow(),
      FindingKind.note => '•',
    };
    _say('$mark ${finding.message}');
    if (finding.fix.isNotEmpty) {
      stdout.writeln('┃      → ${_describe(finding.fix)}');
    }
  }

  int count(FindingKind kind) => findings.where((f) => f.kind == kind).length;
  final conflicts = count(FindingKind.conflict);
  final fights = count(FindingKind.fight);
  final suggestions = count(FindingKind.suggestion);
  final tally = [
    if (conflicts > 0) _plural(conflicts, 'conflict'),
    if (fights > 0) _plural(fights, 'fight'),
    if (suggestions > 0) _plural(suggestions, 'suggestion'),
  ];
  stdout.writeln(tally.isEmpty
      ? '┗━━ ${'✔'.green()} Nothing to change'
      : '┗━━ ${conflicts + fights > 0 ? '✖'.red() : '!'.yellow()} '
          '${tally.join(', ')}');

  final fixes = fixesOf(findings);
  var fixed = false;
  if (fixes.isNotEmpty) {
    final standaloneFile = File('$currentPath/tidy_imports.yaml');
    final standalone = standaloneFile.existsSync();
    final target =
        standalone ? standaloneFile : File('$currentPath/pubspec.yaml');
    final name = standalone ? 'tidy_imports.yaml' : 'pubspec.yaml';

    if (apply) {
      fixed = _applyFixes(target, name, fixes,
          standalone: standalone, readOnly: readOnly);
    } else {
      final where = standalone ? name : 'the tidy_imports: block of $name';
      stdout.writeln('\nAdd to $where — or run again with --apply:\n');
      stdout.writeln(_snippet(fixes, wrapped: !standalone));
    }
  }

  final standing = conflicts + (fixed ? 0 : fights);
  if (failOnFindings && standing > 0) {
    stderr.writeln('\n🚨 ${_plural(standing, 'problem')} between the '
        'configuration and the toolchain. Failing because --exit-if-changed '
        'was passed.');
    return 1;
  }
  return 0;
}

/// Writes [fixes] into [target], or says why it did not. Returns whether the
/// file now says what [fixes] says.
///
/// The edit is checked before it is written: the new text is parsed back and
/// every key must read as the value that was meant. A line editor that
/// guessed wrong on a hand-written file must cost a snippet, never a pubspec.
bool _applyFixes(
  File target,
  String name,
  Map<String, Object> fixes, {
  required bool standalone,
  required bool readOnly,
}) {
  final String original;
  try {
    original = target.readAsStringSync();
  } on FileSystemException catch (e) {
    stderr.writeln('Error: could not read $name: '
        '${e.osError?.message ?? e.message}');
    return false;
  }

  final edited = setConfigKeys(original, fixes, standalone: standalone);
  if (edited == null || !_says(edited, fixes, standalone: standalone)) {
    stdout.writeln('\n${'!'.yellow()} $name is laid out in a way --apply '
        'will not edit by guesswork. Add this by hand:\n');
    stdout.writeln(_snippet(fixes, wrapped: !standalone));
    return false;
  }

  if (readOnly) {
    stdout.writeln('\n• Would write ${_describe(fixes)} to $name '
        '(read-only run — nothing written)');
    return false;
  }
  target.writeAsStringSync(edited);
  stdout.writeln('\n${'✔'.green()} Wrote ${_describe(fixes)} to $name');
  return true;
}

/// Whether [text] parses and its tidy_imports options include every entry of
/// [fixes].
bool _says(String text, Map<String, Object> fixes, {required bool standalone}) {
  try {
    final document = loadYaml(text);
    if (document is! YamlMap) return false;
    final wrapped = document['tidy_imports'];
    final block = standalone && !(document.length == 1 && wrapped is YamlMap)
        ? document
        : wrapped;
    return block is YamlMap &&
        fixes.entries.every((entry) => block[entry.key] == entry.value);
  } on Object {
    return false;
  }
}

/// `flat: true, sort_exports: true`.
String _describe(Map<String, Object> fixes) =>
    fixes.entries.map((e) => '${e.key}: ${e.value}').join(', ');

/// [fixes] as YAML to paste.
String _snippet(Map<String, Object> fixes, {required bool wrapped}) => [
      if (wrapped) 'tidy_imports:',
      for (final entry in fixes.entries)
        '${wrapped ? '  ' : ''}${entry.key}: ${entry.value}',
    ].join('\n');

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

/// Prints [text] under the report's left rule, wrapped so a sentence stays
/// readable in an 80-column terminal.
void _say(String text) {
  const width = 72;
  var line = '';
  var first = true;
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      stdout.writeln('┃  ${first ? '' : '  '}$line');
      first = false;
      line = word;
    } else {
      line = line.isEmpty ? word : '$line $word';
    }
  }
  if (line.isNotEmpty) stdout.writeln('┃  ${first ? '' : '  '}$line');
}

/// Whether the `dart format` of the SDK [version] (`3.13.1 (stable) …`)
/// writes a blank line between `package:` and relative imports on its own.
bool _formatterSeparates(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 3 || (major == 3 && minor >= 13);
}

/// The nearest [relative] file at [start] or above it, the way the analyzer
/// finds `analysis_options.yaml` and pub finds a workspace's package config.
File? _findUp(String start, String relative) {
  var dir = Directory(start).absolute;
  while (true) {
    final file = File('${dir.path}/$relative');
    if (file.existsSync()) return file;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Every resolved package, as name -> the directory its `package:` URIs start
/// in, read from the nearest `.dart_tool/package_config.json`. Empty when
/// there is none — `dart pub get` has not run — or it does not parse.
Map<String, String> _packageDirs(String currentPath) {
  final configFile = _findUp(currentPath, '.dart_tool/package_config.json');
  if (configFile == null) return const {};
  try {
    final json = jsonDecode(configFile.readAsStringSync());
    final packages = json is Map ? json['packages'] : null;
    if (packages is! List) return const {};

    final base =
        Uri.directory(configFile.parent.path, windows: Platform.isWindows);
    final dirs = <String, String>{};
    for (final package in packages) {
      if (package is! Map) continue;
      final name = package['name'];
      final root = package['rootUri'];
      final lib = package['packageUri'];
      if (name is! String || root is! String) continue;
      final uri = base
          .resolve(root.endsWith('/') ? root : '$root/')
          .resolve(lib is String ? lib : '');
      dirs[name] = files
          .toPosix(uri.toFilePath(windows: Platform.isWindows))
          .replaceFirst(RegExp(r'/$'), '');
    }
    return dirs;
  } on Object {
    return const {};
  }
}
