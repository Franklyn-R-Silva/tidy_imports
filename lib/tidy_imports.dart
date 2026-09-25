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
export 'config_edit.dart' show setConfigKeys;
export 'dependencies.dart'
    show DependencyAudit, auditDependencies, usedWithoutImport;
export 'doctor.dart'
    show
        DoctorFinding,
        FindingKind,
        LintState,
        diagnose,
        fixesOf,
        importLints,
        readLints;
export 'src/version.dart' show packageVersion, packageName;
export 'graph.dart' show Coupling, FeatureMetrics, ImportGraph, resolveUri;
export 'graph_export.dart'
    show
        drawnEdges,
        mermaidEdgeLimit,
        ranked,
        reportJson,
        reportSchemaVersion,
        toDot,
        toMermaid;
export 'sort.dart'
    show declaresMain, directiveUris, sortImports, ImportSortData;
export 'files.dart'
    show
        compilePatterns,
        dartFiles,
        filesNamed,
        reportDirectories,
        standardDirectories,
        toPosix;
export 'pubspec_sort.dart' show sortPubspec;
