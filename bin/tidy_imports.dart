// Dart imports:
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

  final label = dryRun ? 'Checking' : 'Sorting';
  stdout.write('┏━━ $label ${dartFiles.length} dart files');
  if (dryRun) stdout.write(' (dry run — no files will be written)');

  final stopwatch = Stopwatch()..start();
  final sortedFiles = <String>[];
  final success = '✔'.green();

  for (final filePath in dartFiles.keys) {
    final file = dartFiles[filePath];
    if (file == null) continue;

    final result = sort.sortImports(
      file.readAsLinesSync(),
      packageName,
      emojis,
      exitOnChange,
      noComments,
      filePath: filePath.replaceFirst(currentPath, ''),
      noBlankLines: noBlankLines,
      customTiers: customTiers,
    );
    if (!result.updated) continue;

    if (!dryRun) file.writeAsStringSync(result.sortedFile);
    sortedFiles.add(filePath);
  }

  stopwatch.stop();

  if (sortedFiles.length > 1) stdout.write('\n');

  final verb = dryRun ? 'Would sort' : 'Sorted imports for';
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
  final action = dryRun ? 'Would sort' : 'Sorted';
  stdout.writeln(
      '┗━━ $success $action ${sortedFiles.length} files in ${elapsed}s');

  // Optionally sort pubspec.yaml dependency sections (issue import_sorter#89).
  if (sortPubspec) {
    final original = pubspecYamlFile.readAsStringSync();
    final sorted = pubspec_sort.sortPubspec(original);
    if (sorted != original) {
      if (exitOnChange) {
        stdout.writeln(
            '\n┗━━🚨 pubspec.yaml dependencies are not sorted alphabetically.');
        exit(1);
      }
      if (!dryRun) pubspecYamlFile.writeAsStringSync(sorted);
      final pubspecVerb = dryRun ? 'Would sort' : 'Sorted';
      stdout.writeln('$success $pubspecVerb pubspec.yaml dependencies');
    }
  }
}
