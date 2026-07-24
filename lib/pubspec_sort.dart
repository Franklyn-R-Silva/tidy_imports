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
/// Returns the rewritten YAML with a trailing newline. If nothing needs
/// reordering, the content is returned unchanged (trailing newline ensured).
String sortPubspec(String pubspecContent) {
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
        // a leading comment of the *next* entry instead.
        while (i < lines.length &&
            lines[i].startsWith('   ') &&
            lines[i].trim().isNotEmpty) {
          blockLines.add(lines[i]);
          i++;
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

  final result = output.join('\n');
  return result.endsWith('\n') ? result : '$result\n';
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
