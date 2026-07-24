// This file demonstrates tidy_imports usage.
//
// Run from the root of any Dart or Flutter project:
//
//   dart run tidy_imports                 # sort every dart file
//   dart run tidy_imports --dry-run       # preview without writing
//   dart run tidy_imports --sort-pubspec  # also sort pubspec.yaml deps
//   dart run tidy_imports --exit-if-changed   # CI check (exit 1 if unsorted)
//
// ---------------------------------------------------------------------------
// Before tidy_imports:
//
//   import 'package:flutter/material.dart';
//   import 'dart:async';
//   import 'package:provider/provider.dart';
//   import 'package:acme_shared/utils.dart';
//   import 'package:myapp/home.dart';
//   import 'dart:io';
//
// After tidy_imports (with a custom "Shared imports:" tier configured):
//
//   // Dart imports:
//   import 'dart:async';
//   import 'dart:io';
//
//   // Flutter imports:
//   import 'package:flutter/material.dart';
//
//   // Package imports:
//   import 'package:provider/provider.dart';
//
//   // Shared imports:
//   import 'package:acme_shared/utils.dart';
//
//   // Project imports:
//   import 'package:myapp/home.dart';
// ---------------------------------------------------------------------------
//
// Configuration (pubspec.yaml or a standalone tidy_imports.yaml):
//
//   tidy_imports:
//     emojis: false
//     sort_pubspec: true
//     tiers:
//       - name: "Shared imports:"
//         pattern: "package:acme_shared"

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:tidy_imports/tidy_imports.dart';

void main() {
  stdout.writeln('tidy_imports $packageVersion');
  stdout.writeln('Run `dart run tidy_imports` from your project root.');
  stdout.writeln('See the README for full usage, options, and configuration.');

  // The public API can also be used programmatically:
  final result = sortImports(
    [
      "import 'package:http/http.dart';",
      "import 'dart:async';",
      '',
      'void main() {}',
    ],
    'my_package',
    false, // emojis
    false, // exitIfChanged
    false, // noComments
  );
  stdout.writeln(
      '\nProgrammatic sort produced ${result.updated ? 'changes' : 'no changes'}:');
  stdout.write(result.sortedFile);
}
