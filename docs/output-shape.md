# Shaping the output

## The groups

Every directive is read, classified by **where it comes from**, sorted
alphabetically inside its group, and written back under a label. The
classification reads the import URI — not the raw text of the line — so a
comment that happens to mention `dart:` cannot drag a package import into the
wrong group.

| # | Group | Holds |
|---|---|---|
| 1 | **Dart imports** | `dart:` |
| 2 | **Flutter imports** | `package:flutter/` |
| 3 | **Package imports** | every other `package:` |
| — | *custom tiers* | internal packages, [when configured](#custom-tiers) |
| 4 | **Project imports** | `package:<your_package>/` and relative paths |
| — | *Test imports* | test doubles, [when asked for](#test-doubles) |

```dart
// before                                   // after
import 'package:flutter/material.dart';     // Dart imports:
import 'package:provider/provider.dart';    import 'dart:async';
import 'dart:io';                           import 'dart:io';
import 'package:myapp/home.dart';
import 'dart:async';                        // Flutter imports:
import 'package:intl/intl.dart';            import 'package:flutter/material.dart';
import 'another_file.dart';
                                            // Package imports:
                                            import 'package:intl/intl.dart';
                                            import 'package:provider/provider.dart';

                                            // Project imports:
                                            import 'package:myapp/home.dart';

                                            import 'another_file.dart';
```

Inside the Project group the `package:` form comes first and the relative form
after it, [separated by a blank line](lint-agreement.md#dart-format-313).
[`--flat`](lint-agreement.md#--flat--for-directives_ordering) replaces the
whole taxonomy with one run per section.

## Custom tiers

All third-party packages share the **Package imports** group. A tier splits
internal or shared packages into a group of their own, between the packages and
your project:

```yaml
tidy_imports:
  tiers:
    - name: "Shared imports:"
      pattern: "package:acme_shared"
    - name: "Company imports:"
      pattern: "package:acme_"
```

An import whose line contains a tier's `pattern` goes into that tier. The first
match wins, so list the most specific pattern first:

```dart
// Package imports:
import 'package:http/http.dart';

// Shared imports:
import 'package:acme_shared/utils.dart';

// Company imports:
import 'package:acme_billing/api.dart';

// Project imports:
import 'package:myapp/home.dart';
```

A tier never captures `package:flutter/` or your own package — those are
classified before tiers are looked at.

## Exports

`--sort-exports` (or `sort_exports: true`) collects `export` directives into a
block of their own, right after the imports, with the same taxonomy —
`// Dart exports:`, `// Flutter exports:`, `// Package exports:`,
`// Project exports:`. Custom tiers apply to exports too.

```dart
// before                                   // after
export 'src/widgets/button.dart';           // Dart exports:
export 'package:acme_shared/utils.dart';    export 'dart:async' show Future;
export 'dart:async' show Future;
export 'src/models/user.dart';              // Flutter exports:
export 'package:flutter/material.dart';     export 'package:flutter/material.dart';

                                            // Package exports:
                                            export 'package:acme_shared/utils.dart';

                                            // Project exports:
                                            export 'src/models/user.dart';
                                            export 'src/widgets/button.dart';
```

It is **off by default** on purpose: enabled everywhere, it would rewrite the
barrel file of every existing project on the first run. Barrels are also where
it pays off — a `lib/index.dart` in a large app, or a generated `database.dart`
with hundreds of `export` lines, is the one file no formatter orders for you.

## Grouping by folder

`--group-by-folder` (or `group_project_by_folder: true`) puts a blank line in
the Project group wherever the folder changes:

```dart
// Project imports:
import 'package:myapp/data/user_repository.dart';
import 'package:myapp/data/user_service.dart';

import 'package:myapp/ui/home_page.dart';
import 'package:myapp/ui/settings_page.dart';
```

### Limiting the depth

The grouping key is the whole folder path, which in a feature-first or Clean
Architecture layout splits a file with 25 project imports into a dozen groups of
one or two lines — noise rather than structure. `--group-by-folder-depth=<n>`
(or `group_project_by_folder_depth: <n>`) counts only the first `n` folders
after the package root. **Any value above `0` enables folder grouping on its
own.**

For `package:myapp/features/orders/presentation/widgets/order_card.dart`:

| Depth | Key |
|---|---|
| `0` (default) | `package:myapp/features/orders/presentation/widgets` |
| `1` | `package:myapp/features` |
| `2` | `package:myapp/features/orders` |

```dart
// --group-by-folder-depth=1
// Project imports:
import 'package:myapp/components/app_button.dart';

import 'package:myapp/core/theme/app_theme.dart';
import 'package:myapp/core/util/format_utils.dart';

import 'package:myapp/features/orders/domain/order.dart';
import 'package:myapp/features/orders/presentation/order_page.dart';

import 'package:myapp/providers/session_provider.dart';
```

## Test doubles

`--test-imports` (or `test_imports: true`) pulls fakes and mocks out of the
Project group into a group of their own, written last:

```dart
// Project imports:
import 'package:myapp/client_repository.dart';

// Test imports:
import 'package:myapp/mock_auth_service.dart';

import 'fake_client_repository.dart';
```

A file is a test double when it is **a project import** and its **file name**
starts with one of `test_import_prefixes` — `fake_` and `mock_` by default. A
custom list replaces the defaults rather than extending them.

Third-party packages are never affected: `package:fake_async` and
`package:mock_web_server` stay in **Package imports**. To group a testing
library such as `mockito`, use a [custom tier](#custom-tiers).

## A note that belongs to an import

`// ignore:` travels with its import whatever you configure — leaving it behind
would switch the lint suppression off. A **plain** note above an import is a
different question, and the answer is `--attach-comments`
(or `attach_comments: true`):

```dart
// before                                 // with --attach-comments
import 'package:http/http.dart';          // Package imports:
                                          // the only client that retries
// the only client that retries           import 'package:dio/dio.dart';
import 'package:dio/dio.dart';            import 'package:http/http.dart';
```

Without it the note is not part of the directive, so rebuilding the block
leaves it below the sorted imports, where it now explains whatever follows it.

Three comments are never attached, in either mode:

| Comment | Where it stays | Why |
|---|---|---|
| The note above the **first** directive | On top | It is the file's header — a licence, an authorship note |
| `// ignore_for_file:` | On top | It applies to the whole file |
| `///` doc comments | Where they are | They document a declaration, never a directive |

It is off by default because it moves comments already in your files, and a
project that learned to write around the old behaviour should not have its diff
rewritten by an upgrade.
