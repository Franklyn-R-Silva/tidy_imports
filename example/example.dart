// tidy_imports by example.
//
// From the command line, in any Dart or Flutter project:
//
//   dart run tidy_imports              # sort the project
//   dart run tidy_imports --dry-run    # preview, write nothing
//   dart run tidy_imports --help       # every option, with its default
//
// Each option is also a `tidy_imports:` key in pubspec.yaml, and each flag is
// negatable — `--no-emojis` overrides `emojis: true` for one run.
//
// This file tours the library API the CLI is built on. Run it:
//
//   dart run example/example.dart

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:tidy_imports/tidy_imports.dart';

void main() {
  stdout.writeln('tidy_imports $packageVersion');

  _demo(
    'Grouped by origin: dart, flutter, package, project',
    [
      "import 'package:flutter/material.dart';",
      "import 'dart:async';",
      "import 'package:provider/provider.dart';",
      "import 'package:my_app/home.dart';",
      "import 'dart:io';",
      '',
      'void main() {}',
    ],
  );

  _demo(
    'A tier of your own, between package and project',
    [
      "import 'package:acme_shared/utils.dart';",
      "import 'package:provider/provider.dart';",
      "import 'package:my_app/home.dart';",
      '',
      'void main() {}',
    ],
    customTiers: const [CustomTier('Shared imports:', 'package:acme_shared')],
  );

  _demo(
    'Exports get their own block, after the imports',
    [
      "export 'package:my_app/models.dart';",
      "import 'dart:convert';",
      "export 'package:my_app/api.dart';",
      '',
      'void main() {}',
    ],
    sortExports: true,
  );

  _demo(
    'Duplicates fold; an aliased import of the same library does not',
    [
      "import 'dart:math';",
      "import 'package:http/http.dart';",
      "import 'dart:math';",
      "import 'package:http/http.dart' as http;",
      '',
      'void main() {}',
    ],
    removeDuplicates: true,
  );

  _demo(
    'Test doubles last — and only the project ones',
    [
      "import 'package:my_app/repo.dart';",
      "import 'fake_repo.dart';",
      "import 'package:mockito/mockito.dart';",
      '',
      'void main() {}',
    ],
    testImports: true,
  );

  stdout.writeln(
    '\nRemoving imports that are merely *unused* is a different question: it\n'
    'needs a resolved element model, so the CLI hands that one to the SDK.\n'
    'Run `dart run tidy_imports --remove-unused` to have it do both.',
  );
}

/// Runs one demonstration and prints the lines before and after.
///
/// [sortImports] is pure — it takes lines, returns lines, reads no file, writes
/// no file and never exits. What an unsorted file *means* is the caller's call,
/// which is why `bin/` and not `lib/` decides to fail a CI run.
void _demo(
  String title,
  List<String> lines, {
  List<CustomTier> customTiers = const [],
  bool sortExports = false,
  bool removeDuplicates = false,
  bool testImports = false,
}) {
  final result = sortImports(
    lines,
    'my_app',
    false, // emojis
    // The fourth positional is `exitIfChanged`: deprecated, inert since 1.4.2,
    // and gone in 2.0.0. Passed once, here, so the demos below stay readable.
    // ignore: deprecated_member_use_from_same_package
    false,
    false, // noComments
    customTiers: customTiers,
    sortExports: sortExports,
    removeDuplicates: removeDuplicates,
    testImports: testImports,
  );

  stdout.writeln('\n── $title');
  _block('before', lines);
  _block('after', result.sortedFile.trimRight().split('\n'));

  if (result.duplicatesRemoved > 0) {
    stdout.writeln('   (${result.duplicatesRemoved} duplicate dropped)');
  }
}

void _block(String label, List<String> lines) {
  stdout.writeln('  $label:');
  for (final line in lines) {
    stdout.writeln(line.isEmpty ? '' : '    $line');
  }
}
