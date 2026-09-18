// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:tidy_imports/sort.dart';

void main() {
  group('multi-line directives', () {
    test('a wrapped import keeps its group and sorts by uri', () {
      final lines = [
        "import 'package:flutter/material.dart';",
        "import 'package:collection/collection.dart'",
        '    show IterableExtension, ListEquality;',
        "import 'dart:math';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:collection/collection.dart'
    show IterableExtension, ListEquality;

void main() {}
''',
      );
    });

    test('a directive wrapped over four lines stays intact', () {
      final lines = [
        "import 'package:collection/collection.dart'",
        '    show',
        '        IterableExtension,',
        '        ListEquality;',
        "import 'dart:math';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:math';

// Package imports:
import 'package:collection/collection.dart'
    show
        IterableExtension,
        ListEquality;

void main() {}
''',
      );
    });

    test('sorts a wrapped import by uri among its group peers', () {
      final lines = [
        "import 'package:provider/provider.dart';",
        "import 'package:collection/collection.dart'",
        '    show IterableExtension;',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Package imports:
import 'package:collection/collection.dart'
    show IterableExtension;
import 'package:http/http.dart';
import 'package:provider/provider.dart';

void main() {}
''',
      );
    });

    test('re-running a file with a wrapped import makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:collection/collection.dart'
    show IterableExtension, ListEquality;

void main() {}
''';

      final result =
          sortImports(sorted.split('\n'), 'demo', false, false, false);

      expect(result.updated, isFalse);
    });
  });

  group('conditional imports', () {
    test('a conditional import is sorted by its first uri', () {
      final lines = [
        "import 'package:demo/app.dart';",
        "import 'stub.dart'",
        "    if (dart.library.io) 'io_impl.dart'",
        "    if (dart.library.html) 'html_impl.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/app.dart';
import 'stub.dart'
    if (dart.library.io) 'io_impl.dart'
    if (dart.library.html) 'html_impl.dart';

void main() {}
''',
      );
    });

    test('sorts among relative peers by the first uri', () {
      final lines = [
        "import 'zebra.dart';",
        "import 'stub.dart'",
        "    if (dart.library.io) 'io_impl.dart';",
        "import 'alpha.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'alpha.dart';
import 'stub.dart'
    if (dart.library.io) 'io_impl.dart';
import 'zebra.dart';

void main() {}
''',
      );
    });

    test('classifies by the first uri, not by a conditional one', () {
      final lines = [
        "import 'stub_platform.dart'",
        "    if (dart.library.io) 'package:demo/io_platform.dart';",
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Package imports:
import 'package:http/http.dart';

// Project imports:
import 'stub_platform.dart'
    if (dart.library.io) 'package:demo/io_platform.dart';

void main() {}
''',
      );
    });

    test('re-running a file with a conditional import makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/app.dart';
import 'stub.dart'
    if (dart.library.io) 'io_impl.dart'
    if (dart.library.html) 'html_impl.dart';

void main() {}
''';

      final result =
          sortImports(sorted.split('\n'), 'demo', false, false, false);

      expect(result.updated, isFalse);
    });
  });

  group('trailing line comments', () {
    test('keeps a trailing comment glued to its import', () {
      final lines = [
        "import 'package:demo/x.dart'; // motivo",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/x.dart'; // motivo

void main() {}
''',
      );
    });

    test('classifies by the uri, not by "dart:" inside the comment', () {
      final lines = [
        "import 'package:http/http.dart'; // wraps dart:io sockets",
        "import 'package:demo/app.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Package imports:
import 'package:http/http.dart'; // wraps dart:io sockets

// Project imports:
import 'package:demo/app.dart';

void main() {}
''',
      );
    });

    test('sorts by the uri, not by a quoted path inside the comment', () {
      final lines = [
        "import 'package:demo/x.dart'; // veja 'outro.dart'",
        "import 'package:demo/b.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/b.dart';
import 'package:demo/x.dart'; // veja 'outro.dart'

void main() {}
''',
      );
    });

    test('re-running a file with trailing comments makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/x.dart'; // motivo

void main() {}
''';

      final result =
          sortImports(sorted.split('\n'), 'demo', false, false, false);

      expect(result.updated, isFalse);
    });
  });

  group('leading // ignore: pragmas', () {
    test('an // ignore: pragma travels with its import', () {
      final lines = [
        "import 'package:demo/app.dart';",
        '// ignore: implementation_imports',
        "import 'package:foo/src/internal.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Package imports:
// ignore: implementation_imports
import 'package:foo/src/internal.dart';

// Project imports:
import 'package:demo/app.dart';

void main() {}
''',
      );
    });

    test('an // ignore_for_file: pragma stays above the import block', () {
      final lines = [
        '// ignore_for_file: implementation_imports',
        "import 'package:foo/src/internal.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// ignore_for_file: implementation_imports

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:foo/src/internal.dart';

void main() {}
''',
      );
    });

    test('a plain comment above an import does not travel with it', () {
      final lines = [
        '// explicação qualquer',
        "import 'package:foo/bar.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// explicação qualquer

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:foo/bar.dart';

void main() {}
''',
      );
    });

    test('re-running a file with an // ignore: pragma makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:io';

// Package imports:
// ignore: implementation_imports
import 'package:foo/src/internal.dart';

// Project imports:
import 'package:demo/app.dart';

void main() {}
''';

      final result =
          sortImports(sorted.split('\n'), 'demo', false, false, false);

      expect(result.updated, isFalse);
    });
  });

  group('sort exports (--sort-exports)', () {
    test('is off by default', () {
      final lines = [
        '// Project imports:',
        "import 'package:demo/app.dart';",
        '',
        "export 'package:demo/z.dart';",
        "export 'package:demo/a.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.updated, isFalse);
      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/app.dart';

export 'package:demo/z.dart';
export 'package:demo/a.dart';

void main() {}
''',
      );
    });

    test('sorts a barrel file of exports only', () {
      final lines = [
        "export 'package:demo/app.dart';",
        "export 'package:http/http.dart';",
        "export 'dart:async';",
        "export 'package:flutter/material.dart';",
        "export 'helpers.dart';",
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(result.updated, isTrue);
      expect(
        result.sortedFile,
        '''
// Dart exports:
export 'dart:async';

// Flutter exports:
export 'package:flutter/material.dart';

// Package exports:
export 'package:http/http.dart';

// Project exports:
export 'package:demo/app.dart';
export 'helpers.dart';
''',
      );
    });

    test('writes the export block after the import block', () {
      final lines = [
        "import 'package:demo/app.dart';",
        "export 'package:demo/z.dart';",
        "import 'dart:io';",
        "export 'package:demo/a.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/app.dart';

// Project exports:
export 'package:demo/a.dart';
export 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('sorts a wrapped export', () {
      final lines = [
        "export 'package:demo/z.dart';",
        "export 'package:demo/a.dart'",
        '    show Foo;',
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project exports:
export 'package:demo/a.dart'
    show Foo;
export 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('writes the emoji labels when emojis are on', () {
      final lines = [
        "export 'package:demo/a.dart';",
        "export 'dart:async';",
      ];

      final result = sortImports(
        lines,
        'demo',
        true,
        false,
        false,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
// 🎯 Dart exports:
export 'dart:async';

// 🌎 Project exports:
export 'package:demo/a.dart';
''',
      );
    });

    test('drops the labels but keeps the order when comments are off', () {
      final lines = [
        "export 'package:demo/z.dart';",
        "export 'dart:async';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
export 'dart:async';

export 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('re-running a sorted import + export file makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/app.dart';

// Project exports:
export 'package:demo/a.dart';
export 'package:demo/z.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(result.updated, isFalse);
    });

    test('leaves no blank line below the last export (issue #6)', () {
      final lines = ["export 'a.dart';"];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        sortExports: true,
      );

      expect(result.sortedFile, "export 'a.dart';\n");
    });

    test('drops the blank line an earlier run left below the last export', () {
      final lines = [
        '// Project exports:',
        "export 'a.dart';",
        '',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
// Project exports:
export 'a.dart';
''',
      );
    });

    test('re-running a barrel file of exports only makes no change', () {
      final lines = [
        '// Dart exports:',
        "export 'dart:async';",
        '',
        '// Project exports:',
        "export 'package:demo/app.dart';",
        "export 'helpers.dart';",
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        sortExports: true,
      );

      expect(result.updated, isFalse);
      expect(result.sortedFile, '${lines.join('\n')}\n');
    });
  });

  group('group_project_by_folder_depth', () {
    test('depth 0 keeps one group per full folder path', () {
      final lines = [
        "import 'package:demo/features/pedidos/presentation/a.dart';",
        "import 'package:demo/features/clientes/domain/b.dart';",
        "import 'package:demo/core/util/c.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/core/util/c.dart';

import 'package:demo/features/clientes/domain/b.dart';

import 'package:demo/features/pedidos/presentation/a.dart';

void main() {}
''',
      );
    });

    test('depth 1 groups by the first segment after the package root', () {
      final lines = [
        "import 'package:demo/features/pedidos/presentation/a.dart';",
        "import 'package:demo/features/clientes/domain/b.dart';",
        "import 'package:demo/core/util/c.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
        groupProjectByFolderDepth: 1,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/core/util/c.dart';

import 'package:demo/features/clientes/domain/b.dart';
import 'package:demo/features/pedidos/presentation/a.dart';

void main() {}
''',
      );
    });

    test('depth 2 splits the two feature folders apart', () {
      final lines = [
        "import 'package:demo/features/pedidos/presentation/a.dart';",
        "import 'package:demo/features/clientes/domain/b.dart';",
        "import 'package:demo/core/util/c.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
        groupProjectByFolderDepth: 2,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/core/util/c.dart';

import 'package:demo/features/clientes/domain/b.dart';

import 'package:demo/features/pedidos/presentation/a.dart';

void main() {}
''',
      );
    });

    test('a depth above zero turns folder grouping on by itself', () {
      final lines = [
        "import 'package:demo/features/pedidos/presentation/a.dart';",
        "import 'package:demo/features/clientes/domain/b.dart';",
        "import 'package:demo/core/util/c.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolderDepth: 1,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/core/util/c.dart';

import 'package:demo/features/clientes/domain/b.dart';
import 'package:demo/features/pedidos/presentation/a.dart';

void main() {}
''',
      );
    });

    test('a relative import with no folder has an empty key', () {
      final lines = [
        "import 'package:demo/features/pedidos/a.dart';",
        "import 'vizinho.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        groupProjectByFolderDepth: 1,
      );

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/features/pedidos/a.dart';

import 'vizinho.dart';

void main() {}
''',
      );
    });

    test('re-running a depth-grouped file makes no change', () {
      const sorted = '''
// Project imports:
import 'package:demo/core/util/c.dart';

import 'package:demo/features/clientes/domain/b.dart';
import 'package:demo/features/pedidos/presentation/a.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        groupProjectByFolder: true,
        groupProjectByFolderDepth: 1,
      );

      expect(result.updated, isFalse);
    });
  });
}
