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
}) {
  String dartImportComment(bool emojis) =>
      '//${emojis ? ' 🎯 ' : ' '}Dart imports:';
  String flutterImportComment(bool emojis) =>
      '//${emojis ? ' 🐦 ' : ' '}Flutter imports:';
  String packageImportComment(bool emojis) =>
      '//${emojis ? ' 📦 ' : ' '}Package imports:';
  String projectImportComment(bool emojis) =>
      '//${emojis ? ' 🌎 ' : ' '}Project imports:';

  final beforeImportLines = <String>[];
  final afterImportLines = <String>[];

  final dartImports = <String>[];
  final flutterImports = <String>[];
  final packageImports = <String>[];
  final projectRelativeImports = <String>[];
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
        projectImports.add(line);
      } else if (line.contains('package:')) {
        final tier = _matchTier(line, customTiers);
        if (tier != null) {
          tierImports[tier]!.add(line);
        } else {
          packageImports.add(line);
        }
      } else {
        projectRelativeImports.add(line);
      }
    } else if (i != lines.length - 1 &&
        (line == dartImportComment(false) ||
            line == flutterImportComment(false) ||
            line == packageImportComment(false) ||
            line == projectImportComment(false) ||
            line == dartImportComment(true) ||
            line == flutterImportComment(true) ||
            line == packageImportComment(true) ||
            line == projectImportComment(true) ||
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
    sortedLines.addAll(projectImports);
    sortedLines.addAll(projectRelativeImports);
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
