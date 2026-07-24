// This file demonstrates tidy_imports usage.
// Run from the root of any Dart project:
//   dart run tidy_imports
//
// Before tidy_imports:
//
//   import 'package:flutter/material.dart';
//   import 'dart:async';
//   import 'package:provider/provider.dart';
//   import 'package:myapp/home.dart';
//   import 'dart:io';
//
// After tidy_imports:
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
//   // Project imports:
//   import 'package:myapp/home.dart';

// Dart imports:
import 'dart:io';

void main() {
  stdout.writeln('Run `dart run tidy_imports` from your project root.');
  stdout.writeln('See README for full usage and options.');
}
