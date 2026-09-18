/// A Dart CLI tool that automatically organizes your import statements.
///
/// Sorts and groups imports in this order:
/// 1. Dart imports (`dart:`)
/// 2. Flutter imports (`package:flutter/`)
/// 3. Package imports (`package:`)
/// 4. Project imports (relative or `package:<your_package>/`)
///
/// Each group is sorted alphabetically.
///
/// ## Usage
///
/// ```
/// dart run tidy_imports
/// ```
///
/// See the [README](https://github.com/Franklyn-R-Silva/tidy_imports) for
/// full documentation and configuration options.
library;

export 'config.dart' show TidyConfig, CustomTier;
export 'src/version.dart' show packageVersion, packageName;
export 'graph.dart' show ImportGraph, resolveUri;
export 'sort.dart' show directiveUris, sortImports, ImportSortData;
export 'files.dart' show compilePatterns, dartFiles, toPosix;
export 'pubspec_sort.dart' show sortPubspec;
