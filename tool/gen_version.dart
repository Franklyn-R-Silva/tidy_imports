// Generates `lib/src/build_info.dart` with version + git metadata.
//
// Run: dart run tool/gen_version.dart
//
// The generated file is gitignored (it's a build artifact).
// If it's missing at runtime, the CLI falls back to the version constant
// in lib/src/version.dart (which IS in git and updated by Release Please).

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:yaml/yaml.dart';

String? _git(String cmd) {
  try {
    final result = Process.runSync('git', cmd.split(' '), runInShell: true);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  } catch (_) {
    return null;
  }
}

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr
        .writeln('Error: Run from the project root (pubspec.yaml not found).');
    exit(1);
  }

  final pubspec = loadYaml(pubspecFile.readAsStringSync());
  final version = pubspec['version'] as String? ?? '0.0.0';

  final gitDescribe = _git('describe --tags --always --dirty') ?? 'no-git';
  final commit = _git('rev-parse --short HEAD');
  final builtAt = DateTime.now().toUtc().toIso8601String();

  final content = '''
// GENERATED — do not edit by hand.
// Run `dart run tool/gen_version.dart` to regenerate.
// This file is gitignored; it is a build artifact.

/// Git describe output (e.g. `v1.0.0-3-gabc1234-dirty`).
const buildGitDescribe = ${_q(gitDescribe)};

/// Short commit hash (e.g. `abc1234`), or null outside a git repo.
const buildCommit = ${commit != null ? _q(commit) : 'null'};

/// ISO-8601 build timestamp in UTC.
const buildTimestamp = ${_q(builtAt)};

/// Full version label combining semver + git describe.
const buildVersionFull = ${_q('$version ($gitDescribe)')};
''';

  final outFile = File('lib/src/build_info.dart');
  outFile.writeAsStringSync(content);

  stdout.writeln('[gen_version] $version  ($gitDescribe)  @ $builtAt');
  stdout.writeln('[gen_version] Written to ${outFile.path}');
}

String _q(String s) => "'${s.replaceAll("'", r"\'")}'";
