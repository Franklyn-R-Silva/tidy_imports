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
import 'package:tidy_imports/pubspec_sort.dart' as pubspec_sort;
import 'package:tidy_imports/sort.dart' as sort;

void main(List<String> args) {
  final parser = ArgParser()
    ..addFlag('emojis', abbr: 'e', negatable: false)
    ..addFlag('ignore-config', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', abbr: 'v', negatable: false)
    ..addFlag('exit-if-changed', negatable: false)
    ..addFlag('no-comments', negatable: false)
    ..addFlag('no-blank-lines', negatable: false)
    ..addFlag('sort-pubspec', negatable: false)
    ..addFlag('group-by-folder', negatable: false)
    ..addFlag('dry-run', negatable: false);

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

  final emojis = config.emojis || argResults['emojis'] == true;
  final noComments = config.noComments || argResults['no-comments'] == true;
  final noBlankLines =
      config.noBlankLines || argResults['no-blank-lines'] == true;
  final sortPubspec = config.sortPubspec || argResults['sort-pubspec'] == true;
  final groupByFolder =
      config.groupProjectByFolder || argResults['group-by-folder'] == true;
  final customTiers = config.customTiers;
  final ignoredFiles = config.ignoredFiles;
  final exitOnChange = argResults['exit-if-changed'] == true;
  final dryRun = argResults['dry-run'] == true;

  final dartFiles = files.dartFiles(currentPath, argResults.rest);

  final containsFlutter = dependencies.contains('flutter');
  final registrantPath = '$currentPath/lib/generated_plugin_registrant.dart';
  if (containsFlutter && dartFiles.containsKey(registrantPath)) {
    dartFiles.remove(registrantPath);
  }

  for (final pattern in ignoredFiles) {
    dartFiles.removeWhere(
      (key, _) => RegExp(pattern).hasMatch(key.replaceFirst(currentPath, '')),
    );
  }

  // Both dry-run and exit-if-changed are read-only: they never write files.
  final readOnly = dryRun || exitOnChange;

  final label = readOnly ? 'Checking' : 'Sorting';
  stdout.write('┏━━ $label ${dartFiles.length} dart files');
  if (dryRun) stdout.write(' (dry run — no files will be written)');

  final stopwatch = Stopwatch()..start();
  final sortedFiles = <String>[];
  final success = '✔'.green();

  for (final filePath in dartFiles.keys) {
    final file = dartFiles[filePath];
    if (file == null) continue;

    // Preserve the file's original line ending (CRLF on Windows) instead of
    // silently rewriting to LF, which creates spurious diffs and git noise.
    final rawContent = file.readAsStringSync();
    final usesCrlf = rawContent.contains('\r\n');

    // Pass exitIfChanged: false so the whole project is checked in one pass —
    // every unsorted file is reported instead of aborting on the first one
    // (issue import_sorter#87).
    final result = sort.sortImports(
      const LineSplitter().convert(rawContent),
      packageName,
      emojis,
      false,
      noComments,
      filePath: filePath.replaceFirst(currentPath, ''),
      noBlankLines: noBlankLines,
      customTiers: customTiers,
      groupProjectByFolder: groupByFolder,
    );
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
  stdout.writeln(
      '┗━━ $success $action ${sortedFiles.length} files in ${elapsed}s');

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
