// Dart imports:
import 'dart:io';

// Project imports:
import 'package:tidy_imports/config.dart';

/// Sort the imports of a dart file.
///
/// Returns [ImportSortData] containing the sorted file content and whether
/// any changes were made.
ImportSortData sortImports(
  List<String> lines,
  String packageName,
  bool emojis,
  bool exitIfChanged,
  bool noComments, {
  String? filePath,
  bool noBlankLines = false,
  List<CustomTier> customTiers = const [],
  bool groupProjectByFolder = false,
  bool testImports = false,
  List<String> testImportPrefixes = TidyConfig.defaultTestImportPrefixes,
}) {
  String dartImportComment(bool emojis) =>
      '//${emojis ? ' 🎯 ' : ' '}Dart imports:';
  String flutterImportComment(bool emojis) =>
      '//${emojis ? ' 🐦 ' : ' '}Flutter imports:';
  String packageImportComment(bool emojis) =>
      '//${emojis ? ' 📦 ' : ' '}Package imports:';
  String projectImportComment(bool emojis) =>
      '//${emojis ? ' 🌎 ' : ' '}Project imports:';
  String testImportComment(bool emojis) =>
      '//${emojis ? ' 🧪 ' : ' '}Test imports:';

  final beforeImportLines = <String>[];
  final afterImportLines = <String>[];

  final dartImports = <String>[];
  final flutterImports = <String>[];
  final packageImports = <String>[];
  final projectRelativeImports = <String>[];

  // Test doubles (fake_/mock_ files) split out of the project group when
  // [testImports] is enabled. Mirrors the project group's package/relative
  // split so both halves keep the same relative ordering.
  final testDoubleImports = <String>[];
  final testDoubleRelativeImports = <String>[];
  final projectImports = <String>[];

  // Custom tiers (issue import_sorter#81): one bucket per configured tier,
  // filled with package imports whose line contains the tier's pattern.
  final tierImports = {for (final t in customTiers) t: <String>[]};

  String customTierComment(CustomTier tier) =>
      '//${emojis ? ' 🧩 ' : ' '}${tier.name}';

  bool noImports() =>
      dartImports.isEmpty &&
      flutterImports.isEmpty &&
      packageImports.isEmpty &&
      projectImports.isEmpty &&
      projectRelativeImports.isEmpty &&
      testDoubleImports.isEmpty &&
      testDoubleRelativeImports.isEmpty &&
      tierImports.values.every((list) => list.isEmpty);

  var isMultiLineString = false;
  var isConditionalImport = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (_timesContained(line, "'''") == 1 ||
        _timesContained(line, '"""') == 1) {
      isMultiLineString = !isMultiLineString;
    }

    // Conditional imports span multiple lines — skip continuation lines
    if (isConditionalImport) {
      if (line.trimRight().endsWith(';')) {
        isConditionalImport = false;
      }
      if (noImports()) {
        beforeImportLines.add(line);
      } else {
        afterImportLines.add(line);
      }
      continue;
    }

    final isImportLine = line.startsWith('import ') && !isMultiLineString;
    final nextLineIsConditional = i + 1 < lines.length &&
        lines[i + 1].trimLeft().startsWith('if (dart.library.');

    if (isImportLine &&
        !line.trimRight().endsWith(';') &&
        nextLineIsConditional) {
      isConditionalImport = true;
      if (noImports()) {
        beforeImportLines.add(line);
      } else {
        afterImportLines.add(line);
      }
      continue;
    }

    if (isImportLine && line.trimRight().endsWith(';')) {
      if (line.contains('dart:')) {
        dartImports.add(line);
      } else if (line.contains('package:flutter/')) {
        flutterImports.add(line);
      } else if (line.contains('package:$packageName/')) {
        if (testImports && _isTestDouble(line, testImportPrefixes)) {
          testDoubleImports.add(line);
        } else {
          projectImports.add(line);
        }
      } else if (line.contains('package:')) {
        final tier = _matchTier(line, customTiers);
        if (tier != null) {
          tierImports[tier]!.add(line);
        } else {
          packageImports.add(line);
        }
      } else {
        if (testImports && _isTestDouble(line, testImportPrefixes)) {
          testDoubleRelativeImports.add(line);
        } else {
          projectRelativeImports.add(line);
        }
      }
    } else if (!isMultiLineString &&
        i != lines.length - 1 &&
        (line == dartImportComment(false) ||
            line == flutterImportComment(false) ||
            line == packageImportComment(false) ||
            line == projectImportComment(false) ||
            line == dartImportComment(true) ||
            line == flutterImportComment(true) ||
            line == packageImportComment(true) ||
            line == projectImportComment(true) ||
            line == testImportComment(false) ||
            line == testImportComment(true) ||
            line == '// 📱 Flutter imports:' ||
            _isCustomTierComment(line, customTiers)) &&
        lines[i + 1].startsWith('import ') &&
        lines[i + 1].trimRight().endsWith(';')) {
      // Skip existing import group comments — they will be re-added sorted
    } else if (noImports()) {
      beforeImportLines.add(line);
    } else {
      afterImportLines.add(line);
    }
  }

  if (noImports()) {
    var joinedLines = lines.join('\n');
    if (!joinedLines.endsWith('\n')) {
      joinedLines += '\n';
    }
    return ImportSortData(joinedLines, false);
  }

  if (beforeImportLines.isNotEmpty && beforeImportLines.last.trim().isEmpty) {
    beforeImportLines.removeLast();
  }

  final sortedLines = <String>[...beforeImportLines];

  if (beforeImportLines.isNotEmpty) {
    sortedLines.add('');
  }
  void addSeparator(bool hasPrevious) {
    if (!noBlankLines && hasPrevious) sortedLines.add('');
  }

  if (dartImports.isNotEmpty) {
    if (!noComments) sortedLines.add(dartImportComment(emojis));
    dartImports.sort();
    sortedLines.addAll(dartImports);
  }
  if (flutterImports.isNotEmpty) {
    addSeparator(dartImports.isNotEmpty);
    if (!noComments) sortedLines.add(flutterImportComment(emojis));
    flutterImports.sort();
    sortedLines.addAll(flutterImports);
  }
  if (packageImports.isNotEmpty) {
    addSeparator(dartImports.isNotEmpty || flutterImports.isNotEmpty);
    if (!noComments) sortedLines.add(packageImportComment(emojis));
    packageImports.sort();
    sortedLines.addAll(packageImports);
  }
  var hasPrecedingGroup = dartImports.isNotEmpty ||
      flutterImports.isNotEmpty ||
      packageImports.isNotEmpty;
  for (final tier in customTiers) {
    final imports = tierImports[tier]!;
    if (imports.isEmpty) continue;
    addSeparator(hasPrecedingGroup);
    if (!noComments) sortedLines.add(customTierComment(tier));
    imports.sort();
    sortedLines.addAll(imports);
    hasPrecedingGroup = true;
  }
  if (projectImports.isNotEmpty || projectRelativeImports.isNotEmpty) {
    addSeparator(hasPrecedingGroup);
    if (!noComments) sortedLines.add(projectImportComment(emojis));
    projectImports.sort();
    projectRelativeImports.sort();
    final allProject = [...projectImports, ...projectRelativeImports];
    if (groupProjectByFolder && !noBlankLines) {
      String? prevDir;
      for (final line in allProject) {
        final dir = _importDir(line);
        if (prevDir != null && dir != prevDir) sortedLines.add('');
        sortedLines.add(line);
        prevDir = dir;
      }
    } else {
      sortedLines.addAll(allProject);
    }
    hasPrecedingGroup = true;
  }
  if (testDoubleImports.isNotEmpty || testDoubleRelativeImports.isNotEmpty) {
    addSeparator(hasPrecedingGroup);
    if (!noComments) sortedLines.add(testImportComment(emojis));
    testDoubleImports.sort();
    testDoubleRelativeImports.sort();
    sortedLines.addAll(testDoubleImports);
    sortedLines.addAll(testDoubleRelativeImports);
  }

  sortedLines.add('');

  var addedCode = false;
  for (var j = 0; j < afterImportLines.length; j++) {
    if (afterImportLines[j] != '') {
      sortedLines.add(afterImportLines[j]);
      addedCode = true;
    }
    if (addedCode && afterImportLines[j] == '') {
      sortedLines.add(afterImportLines[j]);
    }
  }
  sortedLines.add('');

  final sortedFile = sortedLines.join('\n');
  final original = '${lines.join('\n')}\n';

  if (exitIfChanged && original != sortedFile) {
    if (filePath != null) {
      stdout
          .writeln('\n┗━━🚨 File $filePath does not have its imports sorted.');
    }
    exit(1);
  }

  if (original == sortedFile) {
    return ImportSortData(original, false);
  }

  return ImportSortData(sortedFile, true);
}

int _timesContained(String string, String looking) =>
    string.split(looking).length - 1;

/// Matches the quoted URI of an import line.
final _importUri = RegExp('''['"]([^'"]+)['"]''');

/// Whether [line]'s import points at a test double — a file whose name starts
/// with one of [prefixes] (e.g. `fake_client_repository.dart`).
///
/// Only ever called for project imports, so third-party packages whose name
/// happens to start with a prefix (`package:fake_async/fake_async.dart`,
/// `package:mock_web_server/mock_web_server.dart`) stay in the package group.
bool _isTestDouble(String line, List<String> prefixes) {
  final match = _importUri.firstMatch(line);
  if (match == null) return false;
  final uri = match.group(1)!;
  final fileName = uri.substring(uri.lastIndexOf('/') + 1);
  for (final prefix in prefixes) {
    if (fileName.startsWith(prefix)) return true;
  }
  return false;
}

/// Extracts the directory portion of an import's URI (issue import_sorter#69).
///
/// `import 'package:app/aaa/bbb/foo.dart';` -> `package:app/aaa/bbb`.
/// `import 'foo.dart';` -> `''` (no directory).
String _importDir(String line) {
  final match = _importUri.firstMatch(line);
  if (match == null) return '';
  final uri = match.group(1)!;
  final slash = uri.lastIndexOf('/');
  return slash < 0 ? '' : uri.substring(0, slash);
}

/// Returns the first custom tier whose pattern matches [line], or null.
CustomTier? _matchTier(String line, List<CustomTier> tiers) {
  for (final tier in tiers) {
    if (line.contains(tier.pattern)) return tier;
  }
  return null;
}

/// Whether [line] is a previously written comment for any custom tier
/// (emoji or plain form), so it can be stripped and re-added on sort.
bool _isCustomTierComment(String line, List<CustomTier> tiers) {
  for (final tier in tiers) {
    if (line == '// ${tier.name}' || line == '// 🧩 ${tier.name}') {
      return true;
    }
  }
  return false;
}

/// Result of a sort operation.
class ImportSortData {
  final String sortedFile;
  final bool updated;

  const ImportSortData(this.sortedFile, this.updated);
}
