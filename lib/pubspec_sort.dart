/// Sections of a pubspec whose entries are sorted alphabetically.
const _sortableSections = {
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
};

/// Alphabetically sorts the dependency sections of a `pubspec.yaml`.
///
/// Sorts `dependencies`, `dev_dependencies`, and `dependency_overrides` by key
/// (case-insensitive). This is a line-based sort: each dependency keeps its
/// nested value lines (e.g. a `git:`/`version:` block) and any comment lines
/// directly above it, so comments and formatting are preserved. See issue
/// import_sorter#89.
///
/// Returns the rewritten YAML. If nothing needs reordering, the content is
/// returned unchanged — byte for byte, so a file without a final newline is
/// not reported as unsorted for the lack of one. A CRLF file stays CRLF on
/// every line, including the one that used to be last.
String sortPubspec(String pubspecContent) {
  final crlf = pubspecContent.contains('\r\n');
  final lf = crlf ? pubspecContent.replaceAll('\r\n', '\n') : pubspecContent;
  final sorted = _sortLines(lf);
  if (sorted == lf) return pubspecContent;
  return crlf ? sorted.replaceAll('\n', '\r\n') : sorted;
}

String _sortLines(String pubspecContent) {
  final lines = pubspecContent.split('\n');
  final output = <String>[];

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final section = _sectionHeader(line);

    if (section == null) {
      output.add(line);
      i++;
      continue;
    }

    // Keep the `dependencies:` header line itself.
    output.add(line);
    i++;

    // Gather entry blocks until the section ends (a non-indented, non-blank
    // line) or the file ends.
    final blocks = <_Entry>[];
    final pendingComments = <String>[];

    while (i < lines.length) {
      final current = lines[i];

      // Blank line: attach to pending comments so it travels with the next
      // entry, unless we are at the very start (then it separates sections).
      if (current.trim().isEmpty) {
        // A blank line ends the section only if the next meaningful line is
        // not part of this section's entries.
        if (_endsSection(lines, i)) break;
        pendingComments.add(current);
        i++;
        continue;
      }

      // A line that is not indented ends the section.
      if (!current.startsWith('  ')) break;

      final key = _entryKey(current);
      if (key != null) {
        // Start of a new entry: collect its continuation lines.
        final blockLines = <String>[...pendingComments, current];
        pendingComments.clear();
        i++;
        // Continuation lines are nested values, indented deeper than the key
        // (3+ spaces). A comment aligned with entries (2 spaces) is treated as
        // a leading comment of the *next* entry instead — unless more of this
        // entry's values follow it. The same goes for a blank line: stopping
        // at one used to hand the `ref:` below it to the next entry, which
        // carried it off and left a pubspec that no longer parsed.
        while (i < lines.length) {
          if (_isNested(lines[i])) {
            blockLines.add(lines[i]);
            i++;
            continue;
          }
          final resume = _nestedResumesAt(lines, i);
          if (resume == null) break;
          blockLines.addAll(lines.sublist(i, resume));
          i = resume;
        }
        blocks.add(_Entry(key, blockLines));
      } else {
        // Indented but not a recognizable entry key — leave as-is.
        pendingComments.add(current);
        i++;
      }
    }

    blocks.sort(
      (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
    );
    for (final block in blocks) {
      output.addAll(block.lines);
    }
    // Re-emit any trailing comments/blank lines that were not attached.
    output.addAll(pendingComments);
  }

  return output.join('\n');
}

/// Whether [line] is a nested value of the entry above it.
bool _isNested(String line) => line.startsWith('   ') && line.trim().isNotEmpty;

/// When the blank and comment lines starting at [index] are followed by more
/// nested values, the index of the first of those values; otherwise null.
int? _nestedResumesAt(List<String> lines, int index) {
  for (var j = index; j < lines.length; j++) {
    final trimmed = lines[j].trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    return j > index && _isNested(lines[j]) ? j : null;
  }
  return null;
}

/// Returns the section name if [line] is a sortable top-level section header.
String? _sectionHeader(String line) {
  final trimmed = line.trimRight();
  for (final section in _sortableSections) {
    if (trimmed == '$section:') return section;
  }
  return null;
}

/// Extracts the dependency key from a `  key:` entry line, or null if the line
/// is not a top-level (2-space indented) mapping key.
String? _entryKey(String line) {
  if (!line.startsWith('  ') || line.startsWith('   ')) return null;
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('#')) return null;
  final colon = trimmed.indexOf(':');
  if (colon <= 0) return null;
  return trimmed.substring(0, colon).trim();
}

/// Whether a blank line at [index] marks the end of the current section
/// (i.e. the next non-blank line is not a 2-space indented entry).
bool _endsSection(List<String> lines, int index) {
  for (var j = index + 1; j < lines.length; j++) {
    if (lines[j].trim().isEmpty) continue;
    return !lines[j].startsWith('  ');
  }
  return true;
}

/// A single dependency entry: its sort key plus the raw lines it owns
/// (leading comments, the key line, and any nested value lines).
class _Entry {
  final String key;
  final List<String> lines;

  const _Entry(this.key, this.lines);
}
