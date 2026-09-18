// Dart imports:
import 'dart:io';

/// Fails when line coverage drops below a floor, and prints where it went.
///
/// Usage: `dart run tool/check_coverage.dart [lcov file] [floor percent]`
///
/// Only the pure libraries under `lib/` are measured. `bin/` runs as a real
/// subprocess in the CLI tests, which the coverage collector does not see, so
/// a low number there would be noise rather than a signal.
void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'lcov.info';
  final floor = double.parse(args.length > 1 ? args[1] : '85');

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('✖ No coverage report at $path.');
    exit(1);
  }

  final perFile = <String, List<int>>{};
  var current = '';
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).split(RegExp(r'[/\\]')).last;
      perFile[current] = [0, 0];
    } else if (line.startsWith('LF:')) {
      perFile[current]![0] = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      perFile[current]![1] = int.parse(line.substring(3));
    }
  }

  var total = 0;
  var hit = 0;
  for (final counts in perFile.values) {
    total += counts[0];
    hit += counts[1];
  }
  if (total == 0) {
    stderr.writeln('✖ $path covers no lines at all.');
    exit(1);
  }

  final names = perFile.keys.toList()..sort();
  for (final name in names) {
    final counts = perFile[name]!;
    stdout.writeln('  ${_percent(counts[1], counts[0])}  $name');
  }

  final overall = 100 * hit / total;
  final summary = '${_percent(hit, total)} of $total lines (floor $floor%)';
  if (overall < floor) {
    stderr.writeln('✖ Coverage fell to $summary.');
    exit(1);
  }
  stdout.writeln('✔ Coverage $summary.');
}

String _percent(int hit, int total) =>
    '${(100 * hit / total).toStringAsFixed(1).padLeft(5)}%';
