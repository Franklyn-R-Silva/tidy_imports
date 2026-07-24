// Dart imports:
import 'dart:io';

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

  bool noImports() =>
      dartImports.isEmpty &&
      flutterImports.isEmpty &&
      packageImports.isEmpty &&
      projectImports.isEmpty &&
      projectRelativeImports.isEmpty;

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
        packageImports.add(line);
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
            line == '// 📱 Flutter imports:') &&
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
  if (dartImports.isNotEmpty) {
    if (!noComments) sortedLines.add(dartImportComment(emojis));
    dartImports.sort();
    sortedLines.addAll(dartImports);
  }
  if (flutterImports.isNotEmpty) {
    if (dartImports.isNotEmpty) sortedLines.add('');
    if (!noComments) sortedLines.add(flutterImportComment(emojis));
    flutterImports.sort();
    sortedLines.addAll(flutterImports);
  }
  if (packageImports.isNotEmpty) {
    if (dartImports.isNotEmpty || flutterImports.isNotEmpty) {
      sortedLines.add('');
    }
    if (!noComments) sortedLines.add(packageImportComment(emojis));
    packageImports.sort();
    sortedLines.addAll(packageImports);
  }
  if (projectImports.isNotEmpty || projectRelativeImports.isNotEmpty) {
    if (dartImports.isNotEmpty ||
        flutterImports.isNotEmpty ||
        packageImports.isNotEmpty) {
      sortedLines.add('');
    }
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

/// Result of a sort operation.
class ImportSortData {
  final String sortedFile;
  final bool updated;

  const ImportSortData(this.sortedFile, this.updated);
}
