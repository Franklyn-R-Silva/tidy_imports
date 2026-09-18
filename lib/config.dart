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

  /// Whether a blank line separates the `package:<self>/…` and relative halves
  /// of the project group.
  ///
  /// **On by default**, and the only option here that is. It is not a matter of
  /// taste: since 3.13 `dart format` inserts that blank line itself, so with
  /// this off the two tools undo each other's work on every single run
  /// (issue #1). Under `blank_lines: false` it is suppressed anyway.
  final bool separateRelativeImports;
  final bool testImports;
  final List<String> testImportPrefixes;
  final List<String> ignoredFiles;
  final List<CustomTier> customTiers;

  /// Extra entry points for `--report`, as regular expressions matched against
  /// the project-relative path (`/lib/app/bootstrap.dart`). An entry point is
  /// unreferenced by definition, so anything the report cannot recognise on
  /// its own — a file run with `dart run lib/tool.dart`, a flavour main in a
  /// subfolder — is declared here rather than reported forever.
  final List<String> reportRoots;

  /// Whether `export` directives are sorted into their own block. Opt-in: on
  /// by default it would rewrite the barrel file of every existing project.
  final bool sortExports;

  /// Whether a directive written identically twice is folded into one.
  /// Opt-in: removing a line is not something a sorter should do uninvited.
  final bool removeDuplicates;

  /// Whether `dart fix --apply --code=unused_import` runs before sorting.
  /// Opt-in for the same reason, and because it costs an analyzer pass.
  final bool removeUnused;

  /// Whether the groups are dropped for one alphabetical run per section —
  /// the shape the `directives_ordering` lint expects. Opt-in: it throws away
  /// the group comments that are this tool's most recognisable output.
  final bool flat;

  /// Whether `package:<self>/…` imports are rewritten as relative paths,
  /// matching the `prefer_relative_imports` lint. Opt-in, and the opposite of
  /// what `always_use_package_imports` wants — the two lints disagree, so the
  /// choice has to be the user's.
  final bool relativeImports;

  /// How many folder segments — counted after the package root — the project
  /// group is broken up by. 0 keeps the whole path, which is the original
  /// behaviour of [groupProjectByFolder]. Any value above 0 also switches
  /// that grouping on, since setting a depth is asking for it.
  final int groupProjectByFolderDepth;

  const TidyConfig({
    required this.emojis,
    required this.noComments,
    required this.noBlankLines,
    required this.sortPubspec,
    required this.groupProjectByFolder,
    required this.ignoredFiles,
    required this.customTiers,
    this.separateRelativeImports = true,
    this.testImports = false,
    this.testImportPrefixes = defaultTestImportPrefixes,
    this.sortExports = false,
    this.groupProjectByFolderDepth = 0,
    this.removeDuplicates = false,
    this.removeUnused = false,
    this.flat = false,
    this.relativeImports = false,
    this.reportRoots = const [],
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

    final reportRoots = <String>[];
    if (config['report_roots'] != null) {
      for (final pattern in config['report_roots'] as YamlList) {
        reportRoots.add(pattern as String);
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
      separateRelativeImports:
          config['separate_relative_imports'] as bool? ?? true,
      testImports: config['test_imports'] as bool? ?? false,
      testImportPrefixes:
          testPrefixes.isEmpty ? defaultTestImportPrefixes : testPrefixes,
      ignoredFiles: ignored,
      customTiers: tiers,
      sortExports: config['sort_exports'] as bool? ?? false,
      removeDuplicates: config['remove_duplicates'] as bool? ?? false,
      removeUnused: config['remove_unused'] as bool? ?? false,
      flat: config['flat'] as bool? ?? false,
      relativeImports: config['relative_imports'] as bool? ?? false,
      reportRoots: reportRoots,
      groupProjectByFolderDepth:
          config['group_project_by_folder_depth'] as int? ?? 0,
    );
  }
}
