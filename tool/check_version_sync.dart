// Dart imports:
import 'dart:io';

/// Fails when the places a version lives disagree, or when CHANGELOG.md is out
/// of order.
///
/// `pubspec.yaml`, `lib/src/version.dart`, the top CHANGELOG.md section and the
/// two version numbers the README tells people to copy are all bumped by hand,
/// so nothing but this check keeps `--version` from reporting a release that
/// never happened. Ordering is checked too: 1.2.0 once sat above 1.3.0, and
/// 1.4.1 below 1.4.0 — pub.dev renders the file top-down, so the wrong version
/// reads as the current one.
///
/// The README is in here because it drifted: its install snippet still said
/// `^1.5.0` at 2.4.0, and the pre-commit `rev:` still said `v1.1.0`. Both are
/// lines a reader copies verbatim, which makes a stale one worse than no
/// example at all.
///
/// Run: `dart run tool/check_version_sync.dart`
void main() {
  final version = _pubspecVersion();
  final constant = _versionConstant();
  final headings = _changelogVersions();
  final readme = File('README.md').readAsStringSync();

  if (constant != version) {
    _fail(
      'lib/src/version.dart says $constant, but pubspec.yaml says $version. '
      'Both move together.',
    );
  }

  if (headings.isEmpty) {
    _fail('CHANGELOG.md has no `## <version>` heading.');
  }

  if (headings.first != version) {
    _fail(
      'CHANGELOG.md opens on ${headings.first}, but pubspec.yaml says '
      '$version. Move the $version section to the top of the file.',
    );
  }

  final snippet = RegExp(r'tidy_imports: \^(\d+\.\d+\.\d+)').firstMatch(readme);
  if (snippet == null) {
    _fail('README.md has no `tidy_imports: ^x.y.z` install snippet.');
  }
  if (snippet.group(1) != version) {
    _fail(
      'README.md tells people to install ^${snippet.group(1)}, but '
      'pubspec.yaml says $version. It is a line readers copy.',
    );
  }

  final rev = RegExp(r"rev: 'v(\d+\.\d+\.\d+)'").firstMatch(readme);
  if (rev == null) {
    _fail("README.md has no pre-commit `rev: 'vx.y.z'` line.");
  }
  if (rev.group(1) != version) {
    _fail(
      'README.md pins the pre-commit hook at v${rev.group(1)}, but '
      'pubspec.yaml says $version.',
    );
  }

  for (var i = 1; i < headings.length; i++) {
    if (_compare(headings[i - 1], headings[i]) <= 0) {
      _fail(
        'CHANGELOG.md is out of order: ${headings[i]} is listed below '
        '${headings[i - 1]}. Sections run newest first.',
      );
    }
  }

  stdout.writeln(
    '✔ $version in pubspec.yaml, lib/src/version.dart, CHANGELOG.md and both '
    'README snippets; ${headings.length} sections, newest first.',
  );
}

String _pubspecVersion() {
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync());
  if (match == null) _fail('pubspec.yaml has no `version:` line.');
  return match.group(1)!;
}

/// The `packageVersion` constant `--version` prints.
String _versionConstant() {
  final match = RegExp(r"packageVersion\s*=\s*'([^']+)'")
      .firstMatch(File('lib/src/version.dart').readAsStringSync());
  if (match == null) _fail('lib/src/version.dart has no packageVersion.');
  return match.group(1)!;
}

/// Every `## 1.2.3` / `## [1.2.3](…)` heading, in the order they appear.
List<String> _changelogVersions() =>
    RegExp(r'^## \[?(\d+\.\d+\.\d+)', multiLine: true)
        .allMatches(File('CHANGELOG.md').readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();

/// Compares two versions numerically, so 1.10.0 sorts above 1.9.0.
int _compare(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (left[i] != right[i]) return left[i] - right[i];
  }
  return 0;
}

Never _fail(String message) {
  stderr.writeln('✖ $message');
  exit(1);
}
