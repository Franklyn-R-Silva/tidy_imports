# Tricky imports

A directive does not have to be one clean line to be sorted. There is nothing to
turn on here — every shape below is recognised, classified and sorted like any
other import, and each one has a test.

## What is sorted

**Imports `dart format` wrapped onto several lines**, usually because of a long
`show` or `as` clause — since Dart 3.7 the tall style puts every name on a line
of its own. They used to slide out of the sorted block and end up loose below
the groups:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Consumer, ProviderContainer;
```

**An `import` whose URI is on the next line.** Legal Dart, and sorted like any
other:

```dart
import
    'package:app/very/long/path/to/a/file.dart';
```

**Conditional imports.** Sorted by their first URI; every `if (dart.library.x)`
target is kept, rewritten by `--relative-imports`/`--package-imports`, and read
as an edge by `--report`:

```dart
import 'stub.dart'
    if (dart.library.io) 'io_impl.dart'
    if (dart.library.js_interop) 'web_impl.dart';
```

**A trailing comment** — line or block, even a block that runs on to the next
line. Sorted normally, with the comment kept where it was; a path quoted inside
it is never read as an import, never rewritten, and never becomes an edge in
the graph:

```dart
import 'package:app/x.dart'; // pinned until #412 lands
import 'package:app/y.dart'; /* was 'package:app/old_y.dart' */
```

**A double-quoted URI** holds whatever single quotes it likes:
`import "it's.dart";` is sorted as `it's.dart`.

**`// ignore:` above an import** travels with it. Sorting used to tear the
comment off and leave it below the block, silently switching the lint
suppression off. `// ignore_for_file:` applies to the whole file, so it stays
at the top.

**Classification by URI.** `import 'package:http/http.dart'; // uses dart:io`
used to be filed under **Dart imports** because of the word in the comment. The
URI decides, so it goes to **Package imports**.

## What is never moved

Text that only *looks* like a directive stays where it is. A commented-out
import stays commented out, and an import inside a string stays in the string:

```dart
/*
import 'package:app/disabled.dart';    // stays disabled
*/

const template = '''
import 'package:app/generated.dart';   // stays in the template
''';
```

The sorter tracks quotes, raw strings and `/* */` blocks — which nest in Dart —
line by line, so only a line that *begins* in executable code can be a
directive at all. Moving one out of a comment would bring dead code back to
life; moving one out of a string would change what the program prints.

The body of the file below the imports is never reordered: exactly one blank
line separates the directives from the first line of code, and every blank line
after that is yours.
