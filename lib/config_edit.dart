/// [source] with each of [values] set as a tidy_imports option, or null when
/// the file is in a shape this editor will not guess at.
///
/// With [standalone] the options are the document itself — a
/// `tidy_imports.yaml` — unless it wraps them in a `tidy_imports:` key, which
/// is then edited in place like the pubspec block. Otherwise [source] is a
/// `pubspec.yaml` and the options live in its `tidy_imports:` block, which is
/// created at the end of the file when there is none.
///
/// An existing key keeps its line and its trailing comment and only has its
/// value replaced; a new key goes after the last line of the block, at the
/// block's own indentation. Everything else is left byte for byte, CRLF line
/// endings included. That is why this edits lines instead of re-serialising
/// the YAML: a pubspec is written by hand, and its comments and order are the
/// author's.
///
/// Null means: a flow-style or scalar block (`tidy_imports: {flat: true}`), a
/// key whose value is a nested block, or indentation made of tabs. The caller
/// is expected to print the snippet instead of writing anything.
String? setConfigKeys(
  String source,
  Map<String, Object> values, {
  required bool standalone,
}) {
  final crlf = source.contains('\r\n');
  final lines = source.replaceAll('\r\n', '\n').split('\n');

  // A trailing newline is an empty last element; new lines go above it.
  var end = lines.length;
  while (end > 0 && lines[end - 1].trim().isEmpty) {
    end--;
  }

  final header = lines.indexWhere(_blockHeader.hasMatch);
  final String indent;
  final int first;
  var last = -1;

  if (standalone && header < 0) {
    indent = '';
    first = 0;
    last = end - 1;
  } else if (header < 0) {
    // No block yet: open one at the end of the pubspec.
    lines.insertAll(end, [
      if (end > 0) '',
      'tidy_imports:',
      for (final entry in values.entries)
        '  ${entry.key}: ${_yaml(entry.value)}',
    ]);
    return _join(lines, crlf);
  } else {
    final inline = _blockHeader.firstMatch(lines[header])!.group(1);
    if (inline != null && inline.trim().isNotEmpty) {
      return null; // `tidy_imports: {...}` or a scalar: not a block of lines.
    }
    first = header + 1;
    String? found;
    for (var i = first; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) break;
      last = i;
      if (found == null && !line.trimLeft().startsWith('#')) {
        found = line.substring(0, line.length - line.trimLeft().length);
      }
    }
    if (last < 0) last = header;
    indent = found ?? '  ';
    if (indent.contains('\t')) return null;
  }

  for (final entry in values.entries) {
    final key = RegExp(
      '^${RegExp.escape(indent)}${RegExp.escape(entry.key)}\\s*:(.*)\$',
    );
    var replaced = false;
    for (var i = first; i <= last; i++) {
      final match = key.firstMatch(lines[i]);
      if (match == null) continue;
      final rest = match.group(1)!;
      final comment = _trailingComment.firstMatch(rest)?.group(0) ?? '';
      if (rest.substring(0, rest.length - comment.length).trim().isEmpty) {
        return null; // The value is a nested block below this line.
      }
      lines[i] = '$indent${entry.key}: ${_yaml(entry.value)}$comment';
      replaced = true;
      break;
    }
    if (replaced) continue;

    last++;
    lines.insert(last, '$indent${entry.key}: ${_yaml(entry.value)}');
  }

  return _join(lines, crlf);
}

/// `tidy_imports:` at column 0; group 1 holds whatever follows the colon
/// before any comment.
final _blockHeader = RegExp(r'^tidy_imports\s*:([^#]*)(?:#.*)?$');

/// A ` # comment` at the end of a value.
final _trailingComment = RegExp(r'\s+#.*$');

String _yaml(Object value) =>
    value is String ? '"${value.replaceAll('"', r'\"')}"' : '$value';

String _join(List<String> lines, bool crlf) => lines.join(crlf ? '\r\n' : '\n');
