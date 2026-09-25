/// Packages a project declares and, by design, never imports.
///
/// `flutter create` adds `cupertino_icons` to every app: it ships a font, and
/// nothing ever says `import 'package:cupertino_icons/…'`. Flagging it would
/// make the check wrong on the first project anyone runs it on.
const usedWithoutImport = {'cupertino_icons'};

/// What the package's own directives say about its `pubspec.yaml`.
class DependencyAudit {
  /// Declared under `dependencies:` and named by no directive anywhere in the
  /// package. Sorted.
  final List<String> unused;

  /// Package -> the `lib/`, `bin/` or `hook/` files that import it while it is
  /// declared only under `dev_dependencies:`. Sorted by package, then file.
  ///
  /// It compiles in the package itself, which is what makes it easy to miss:
  /// the root package resolves its dev dependencies. Pub never resolves them
  /// for a package that depends on this one, so that package cannot build.
  final Map<String, List<String>> devOnly;

  const DependencyAudit(this.unused, this.devOnly);

  /// How many things are wrong: each unused dependency and each dev-only
  /// package counts once, however many files import it.
  int get findings => unused.length + devOnly.length;

  /// The audit as a JSON-ready map.
  Map<String, Object?> toJson() => {
        'unused': unused,
        'devOnly': [
          for (final entry in devOnly.entries)
            {'package': entry.key, 'files': entry.value},
        ],
      };
}

/// Checks the `dependencies:` and `dev_dependencies:` of [pubspec] against
/// the URIs in [directivesByFile] — project-relative path to every URI the
/// file's `import`, `export` and `part` directives name.
///
/// Files under one of [otherPackages] — directories with a pubspec of their
/// own, like `packages/core` or an `example/` app — answer to that pubspec,
/// not this one, and are left out. An entry that is an SDK package
/// (`flutter: {sdk: flutter}`), one of [usedWithoutImport], or listed in
/// [ignored] is never reported: assets, fonts, code generators and platform
/// plugins are used without a Dart import, and this reads only imports.
///
/// A package imported but declared nowhere is not reported either — the
/// analyzer's `depend_on_referenced_packages` already says that, with a fix.
DependencyAudit auditDependencies(
  Map<Object?, Object?> pubspec, {
  required Map<String, List<String>> directivesByFile,
  Iterable<String> ignored = const [],
  Iterable<String> otherPackages = const [],
}) {
  final self = pubspec['name'];
  final dependencies = _section(pubspec['dependencies']);
  final devDependencies = _section(pubspec['dev_dependencies']);
  // `flutter: generate: true` has `flutter gen-l10n` write the code that
  // imports `intl` — which it requires as a dependency — under `.dart_tool/`,
  // where no scan of the project sees it.
  final flutter = pubspec['flutter'];
  final generatesL10n = flutter is Map && flutter['generate'] == true;
  final exempt = {
    ...usedWithoutImport,
    ...ignored,
    if (generatesL10n) 'intl',
  };
  final foreign = [for (final dir in otherPackages) '$dir/'];

  final imported = <String>{};
  final devOnly = <String, Set<String>>{};
  for (final entry in directivesByFile.entries) {
    final file = entry.key;
    if (foreign.any(file.startsWith)) continue;
    // What runs for the packages that depend on this one: its library, its
    // executables, and its build hooks.
    final shipped = file.startsWith('lib/') ||
        file.startsWith('bin/') ||
        file.startsWith('hook/');

    for (final uri in entry.value) {
      final package = _packageOf(uri);
      if (package == null || package == self) continue;
      imported.add(package);
      if (shipped &&
          devDependencies.containsKey(package) &&
          !dependencies.containsKey(package) &&
          !exempt.contains(package)) {
        devOnly.putIfAbsent(package, () => {}).add(file);
      }
    }
  }

  final unused = [
    for (final entry in dependencies.entries)
      if (!imported.contains(entry.key) &&
          !exempt.contains(entry.key) &&
          !_isSdk(entry.value))
        entry.key,
  ]..sort();

  return DependencyAudit(unused, {
    for (final package in devOnly.keys.toList()..sort())
      package: devOnly[package]!.toList()..sort(),
  });
}

/// A dependency section as name -> declaration, or empty when it is missing
/// or not a map.
Map<String, Object?> _section(Object? section) => section is Map
    ? {for (final entry in section.entries) '${entry.key}': entry.value}
    : const {};

/// Whether a declaration is `sdk: …` — `flutter`, `flutter_localizations`,
/// `flutter_test`: part of the SDK, and some are used without an import.
bool _isSdk(Object? declaration) =>
    declaration is Map && declaration.containsKey('sdk');

/// The package a `package:` [uri] names, or null for any other URI.
String? _packageOf(String uri) {
  if (!uri.startsWith('package:')) return null;
  final slash = uri.indexOf('/');
  return slash <= 'package:'.length
      ? null
      : uri.substring('package:'.length, slash);
}
