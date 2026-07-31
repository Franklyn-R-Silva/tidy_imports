// Dart imports:
import 'dart:io';

// Package imports:
import 'package:yaml/yaml.dart';

/// A user-defined import tier that sits between generic `package:` imports
/// and project imports. See issue import_sorter#81.
class CustomTier {
  /// The comment label written above the group (without a leading `//`).
  final String name;

  /// Substring matched against an import line to assign it to this tier.
  /// For example `package:ptp_shared` groups all imports from that package.
  final String pattern;

  const CustomTier(this.name, this.pattern);
}

/// Resolved configuration for a tidy_imports run.
///
/// Configuration is read from `tidy_imports.yaml` at the project root if it
/// exists (issue import_sorter#67), otherwise from the `tidy_imports:` block
/// in `pubspec.yaml`. Command-line flags take precedence over both.
class TidyConfig {
  /// File-name prefixes treated as test doubles when [testImports] is on.
  static const defaultTestImportPrefixes = ['fake_', 'mock_'];

  final bool emojis;
  final bool noComments;
  final bool noBlankLines;
  final bool sortPubspec;
  final bool groupProjectByFolder;
  final bool testImports;
  final List<String> testImportPrefixes;
  final List<String> ignoredFiles;
  final List<CustomTier> customTiers;

  const TidyConfig({
    required this.emojis,
    required this.noComments,
    required this.noBlankLines,
    required this.sortPubspec,
    required this.groupProjectByFolder,
    required this.ignoredFiles,
    required this.customTiers,
    this.testImports = false,
    this.testImportPrefixes = defaultTestImportPrefixes,
  });

  /// Loads configuration, preferring `tidy_imports.yaml` over the
  /// `tidy_imports:` block in `pubspec.yaml`.
  factory TidyConfig.load(String currentPath, YamlMap pubspecYaml) {
    final standaloneFile = File('$currentPath/tidy_imports.yaml');
    dynamic config;
    if (standaloneFile.existsSync()) {
      config = loadYaml(standaloneFile.readAsStringSync());
    } else {
      config = pubspecYaml['tidy_imports'];
    }
    return TidyConfig.fromYaml(config);
  }

  /// Builds a config from a parsed YAML node, applying defaults for anything
  /// missing. A `null` node yields all defaults.
  factory TidyConfig.fromYaml(dynamic config) {
    if (config == null) {
      return const TidyConfig(
        emojis: false,
        noComments: false,
        noBlankLines: false,
        sortPubspec: false,
        groupProjectByFolder: false,
        ignoredFiles: [],
        customTiers: [],
      );
    }

    final ignored = <String>[];
    if (config['ignored_files'] != null) {
      for (final pattern in config['ignored_files'] as YamlList) {
        ignored.add(pattern as String);
      }
    }

    final testPrefixes = <String>[];
    if (config['test_import_prefixes'] != null) {
      for (final prefix in config['test_import_prefixes'] as YamlList) {
        testPrefixes.add(prefix as String);
      }
    }

    final tiers = <CustomTier>[];
    if (config['tiers'] != null) {
      for (final tier in config['tiers'] as YamlList) {
        final name = tier['name'] as String?;
        final pattern = tier['pattern'] as String?;
        if (name != null && pattern != null) {
          tiers.add(CustomTier(name, pattern));
        }
      }
    }

    return TidyConfig(
      emojis: config['emojis'] as bool? ?? false,
      noComments:
          config['comments'] == null ? false : !(config['comments'] as bool),
      noBlankLines: config['blank_lines'] == null
          ? false
          : !(config['blank_lines'] as bool),
      sortPubspec: config['sort_pubspec'] as bool? ?? false,
      groupProjectByFolder: config['group_project_by_folder'] as bool? ?? false,
      testImports: config['test_imports'] as bool? ?? false,
      testImportPrefixes:
          testPrefixes.isEmpty ? defaultTestImportPrefixes : testPrefixes,
      ignoredFiles: ignored,
      customTiers: tiers,
    );
  }
}
