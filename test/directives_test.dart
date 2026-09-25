// Dart imports:
import 'dart:convert';

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

    test('a directive whose keyword ends the line is sorted like any other',
        () {
      final lines = [
        'import',
        "    'package:demo/b.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import
    'package:demo/b.dart';

void main() {}
''',
        reason: 'legal Dart, and directiveUris already read it — the sorter '
            'matched `import ` with a trailing space, so the directive slid '
            'out of the block instead',
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

  group('block comments inside a directive', () {
    test('a block comment after the semicolon keeps it a directive', () {
      // The terminator test looked at the last character of the line, which
      // here is `/`: the import never ended, and slid out of the block.
      final result = sortImports(
        [
          "import 'package:demo/z.dart'; /* why z */",
          "import 'dart:io';",
          '',
          'void main() {}',
        ],
        'demo',
        false,
        false,
        false,
      );

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/z.dart'; /* why z */

void main() {}
''',
      );
    });

    test('a block comment still open at the semicolon travels whole', () {
      final result = sortImports(
        [
          "import 'package:demo/z.dart'; /* a note",
          '   that goes on */',
          "import 'dart:io';",
          '',
          'void main() {}',
        ],
        'demo',
        false,
        false,
        false,
      );

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/z.dart'; /* a note
   that goes on */

void main() {}
''',
        reason: 'leaving the tail behind would turn `that goes on */` into '
            'code',
      );
    });

    test('a path quoted in a block comment is not rewritten', () {
      final result = sortImports(
        ["import 'b.dart' /* was 'gone.dart' */;", '', 'void main() {}'],
        'demo',
        false,
        false,
        true,
        packageImports: true,
        libRelativePath: 'a.dart',
      );

      expect(
        result.sortedFile,
        startsWith("import 'package:demo/b.dart' /* was 'gone.dart' */;"),
      );
    });

    test('a path quoted in a block comment is not a graph edge', () {
      expect(
        directiveUris([
          "import 'a.dart' /* was 'b.dart' */;",
          "import 'c.dart' /* see",
          "    'd.dart' */ show C;",
        ]),
        ['a.dart', 'c.dart'],
      );
    });

    test('an apostrophe inside a double-quoted uri is part of it', () {
      expect(directiveUris(['import "it\'s.dart";']), ["it's.dart"]);

      final result = sortImports(
        ['import "it\'s.dart";', "import 'b.dart';", '', 'void main() {}'],
        'demo',
        false,
        false,
        true,
      );
      expect(
        result.sortedFile,
        startsWith('import \'b.dart\';\nimport "it\'s.dart";\n'),
        reason: "sorted by it's.dart, not by a truncated `it`",
      );
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

    test('a note above an import is left behind by default', () {
      final lines = [
        "import 'dart:async';",
        '',
        '// Package imports:',
        '// por que este import existe',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        contains("import 'package:http/http.dart';\n"
            '\n'
            '// por que este import existe'),
        reason: 'the comment ends up below the block unless asked otherwise',
      );
      expect(
        result.sortedFile.split('// Package imports:').length - 1,
        1,
        reason: 'and the header above it is not left behind with it. A second '
            'copy below the block used to be exactly what happened',
      );
    });

    test('--attach-comments keeps a note with its import', () {
      final lines = [
        "import 'dart:async';",
        '',
        '// Package imports:',
        '// por que este import existe',
        '// e a segunda linha',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result =
          sortImports(lines, 'demo', false, false, false, attachComments: true);

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:async';

// Package imports:
// por que este import existe
// e a segunda linha
import 'package:http/http.dart';

void main() {}
''',
      );
    });

    test('the note above the first import stays a file header', () {
      final lines = [
        '// Copyright 2026.',
        "import 'package:http/http.dart';",
        "import 'dart:async';",
        '',
        'void main() {}',
      ];

      final result =
          sortImports(lines, 'demo', false, false, false, attachComments: true);

      expect(result.sortedFile, startsWith('// Copyright 2026.\n\n// Dart'));
    });

    test('a doc comment is never attached', () {
      final lines = [
        "import 'dart:async';",
        '',
        '/// Documenta a declaração abaixo.',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result =
          sortImports(lines, 'demo', false, false, false, attachComments: true);

      expect(
        result.sortedFile,
        isNot(contains('/// Documenta a declaração abaixo.\n'
            "import 'package:http/http.dart';")),
      );
    });

    test('re-running an attached file makes no change', () {
      const sorted = '''
// Dart imports:
import 'dart:async';

// Package imports:
// por que este import existe
import 'package:http/http.dart';

void main() {}
''';

      final result = sortImports(
          sorted.split('\n'), 'demo', false, false, false,
          attachComments: true);

      expect(result.updated, isFalse);
    });

    test('turning --attach-comments back off does not duplicate the header',
        () {
      final attached = [
        '// Dart imports:',
        "import 'dart:async';",
        '',
        '// Package imports:',
        '// http client',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(attached, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:async';

// Package imports:
import 'package:http/http.dart';

// http client

void main() {}
''',
        reason: 'the note falling below the block is what the option being '
            'off means. What must not happen is the header staying behind as '
            'body text while a second copy is written above the import',
      );
      expect(
        result.sortedFile.split('// Package imports:').length - 1,
        1,
        reason: 'one header, not two',
      );
    });

    test('the block a toggled run leaves behind is not a corrupt fixed point',
        () {
      final attached = [
        '// Dart imports:',
        "import 'dart:async';",
        '',
        '// Package imports:',
        '// http client',
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final once = sortImports(attached, 'demo', false, false, false);
      final twice = sortImports(const LineSplitter().convert(once.sortedFile),
          'demo', false, false, false);

      expect(
        twice.updated,
        isFalse,
        reason: 'the duplicated header used to read as already sorted, so '
            'nothing ever repaired the file',
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

  group('comments and string literals', () {
    test('an import inside a block comment stays commented out', () {
      final lines = [
        "import 'package:demo/b.dart';",
        '',
        '/*',
        "import 'package:demo/disabled.dart';",
        '*/',
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// Project imports:
import 'package:demo/b.dart';

/*
import 'package:demo/disabled.dart';
*/

void main() {}
''',
      );
    });

    test('block comments nest, so the inner close does not reopen code', () {
      final lines = [
        "import 'package:demo/b.dart';",
        '',
        '/* outer',
        '/* inner */',
        "import 'package:demo/still_disabled.dart';",
        '*/',
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        contains(
            "/* outer\n/* inner */\nimport 'package:demo/still_disabled.dart';\n*/"),
      );
    });

    test('a group header inside a block comment is not stripped', () {
      final lines = [
        "import 'package:demo/b.dart';",
        '',
        '/*',
        '// Project imports:',
        "import 'package:demo/disabled.dart';",
        '*/',
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.sortedFile, contains('/*\n// Project imports:\n'));
    });

    test('an import inside a raw triple-quoted string is left alone', () {
      // Built from a constant instead of written inline: a literal triple
      // quote inside a triple-quoted fixture has to be escaped, and the escape
      // is easy to break.
      const tq = "'''";
      final lines = [
        "import 'package:demo/b.dart';",
        '',
        'void main() {',
        '  const sql = r$tq',
        "import 'package:demo/inside_string.dart';",
        '$tq;',
        '  print(sql);',
        '}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        contains(
          "  const sql = r$tq\nimport 'package:demo/inside_string.dart';\n$tq;",
        ),
        reason: 'the import inside the string must not move',
      );
      expect(
        result.sortedFile,
        isNot(contains("import 'package:demo/inside_string.dart';\n\n")),
        reason: 'and must not be hoisted into the sorted block',
      );
    });

    test('a // comment never opens a block comment', () {
      final lines = [
        '// mind the /* in this sentence',
        "import 'package:demo/z.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
// mind the /* in this sentence

// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('a /* */ in a string does not swallow the rest of the file', () {
      final lines = [
        "import 'package:demo/z.dart';",
        "import 'dart:io';",
        '',
        'void main() {',
        "  print('a /* b');",
        '}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        startsWith("// Dart imports:\nimport 'dart:io';"),
      );
    });

    test('directives after a closed block comment are still sorted', () {
      final lines = [
        '/* header',
        '   spanning lines */',
        "import 'package:demo/z.dart';",
        "import 'dart:io';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(
        result.sortedFile,
        '''
/* header
   spanning lines */

// Dart imports:
import 'dart:io';

// Project imports:
import 'package:demo/z.dart';

void main() {}
''',
      );
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

  group('remove duplicates (--remove-duplicates)', () {
    test('is off by default', () {
      final lines = [
        "import 'dart:math';",
        "import 'dart:math';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false);

      expect(result.duplicatesRemoved, 0);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:math';
import 'dart:math';

void main() {}
''',
      );
    });

    test('folds an identical directive into the first one', () {
      final lines = [
        "import 'package:demo/z.dart';",
        "import 'dart:math';",
        "import 'package:demo/z.dart';",
        "import 'dart:math';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 2);
      expect(
        result.sortedFile,
        '''
// Dart imports:
import 'dart:math';

// Project imports:
import 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('matches a wrapped directive against its one-line twin', () {
      final lines = [
        "import 'package:collection/collection.dart' show IterableExtension;",
        "import 'package:collection/collection.dart'",
        '    show IterableExtension;',
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 1);
    });

    test('keeps imports that differ by prefix', () {
      final lines = [
        "import 'package:demo/z.dart' as a;",
        "import 'package:demo/z.dart' as b;",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 0);
      expect(result.sortedFile, contains("as a;"));
      expect(result.sortedFile, contains("as b;"));
    });

    test('keeps imports that differ by show clause', () {
      final lines = [
        "import 'package:demo/z.dart' show Foo;",
        "import 'package:demo/z.dart' show Bar;",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 0);
    });

    test('keeps a duplicate whose trailing comment differs', () {
      final lines = [
        "import 'dart:math'; // for max",
        "import 'dart:math';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(
        result.duplicatesRemoved,
        0,
        reason: 'dropping one would drop what its comment says',
      );
    });

    test('an import inside a block comment is not a duplicate of a real one',
        () {
      final lines = [
        "import 'dart:math';",
        '',
        '/*',
        "import 'dart:math';",
        '*/',
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        false,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 0);
      expect(result.sortedFile, contains("/*\nimport 'dart:math';\n*/"));
    });

    test('deduplicates exports too', () {
      final lines = [
        "export 'package:demo/a.dart';",
        "export 'package:demo/a.dart';",
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        sortExports: true,
        removeDuplicates: true,
      );

      expect(result.duplicatesRemoved, 1);
      expect(result.sortedFile, "export 'package:demo/a.dart';\n");
    });
  });

  group('flat ordering (--flat)', () {
    final mixed = [
      "import 'package:flutter/material.dart';",
      "import 'package:args/args.dart';",
      "import 'dart:io';",
      "import 'helper.dart';",
      "import 'package:demo/app.dart';",
      '',
      'void main() {}',
    ];

    test('is off by default', () {
      final result = sortImports(mixed, 'demo', false, false, false);

      expect(result.sortedFile, contains('// Flutter imports:'));
    });

    test('emits dart, then package, then relative — alphabetical', () {
      final result =
          sortImports(mixed, 'demo', false, false, false, flat: true);

      expect(
        result.sortedFile,
        '''
import 'dart:io';

import 'package:args/args.dart';
import 'package:demo/app.dart';
import 'package:flutter/material.dart';

import 'helper.dart';

void main() {}
''',
      );
    });

    test('writes a blank line where the section changes, like dart format', () {
      final result =
          sortImports(mixed, 'demo', false, false, false, flat: true);
      final blanks = result.sortedFile
          .trimRight()
          .split('\n')
          .asMap()
          .entries
          .where((e) => e.value.isEmpty)
          .map((e) => e.key)
          .toList();

      expect(
        blanks.first,
        1,
        reason: 'dart format 3.13+ writes that line itself. With none here it '
            'added all three and the next run took them away again, so the '
            'two tools undid each other every run — issue #1, in the one mode '
            'that had no separator at all',
      );
      expect(
        blanks,
        hasLength(3),
        reason: 'dart:/package:, package:/relative, and the body below',
      );
    });

    test('--no-blank-lines gives the tight run back', () {
      final result = sortImports(
        mixed,
        'demo',
        false,
        false,
        false,
        flat: true,
        noBlankLines: true,
      );

      expect(
        result.sortedFile,
        '''
import 'dart:io';
import 'package:args/args.dart';
import 'package:demo/app.dart';
import 'package:flutter/material.dart';
import 'helper.dart';

void main() {}
''',
        reason: 'the lint reads order, not spacing, so asking for no blank '
            'lines is still an answer it accepts',
      );
    });

    test('does not single out flutter, which is what breaks the lint', () {
      final result =
          sortImports(mixed, 'demo', false, false, false, flat: true);
      final body = result.sortedFile;

      expect(
        body.indexOf("package:args"),
        lessThan(body.indexOf("package:flutter")),
        reason: 'alphabetical among package: imports, flutter included',
      );
    });

    test('writes no group comments at all', () {
      final result = sortImports(
        mixed,
        'demo',
        true, // emojis, which would otherwise show up in the headers
        false,
        false,
        flat: true,
      );

      expect(result.sortedFile, isNot(contains('//')));
    });

    test('puts exports in their own block below the imports', () {
      final lines = [
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
        flat: true,
        sortExports: true,
      );

      expect(
        result.sortedFile,
        '''
import 'dart:io';

export 'package:demo/a.dart';
export 'package:demo/z.dart';

void main() {}
''',
      );
    });

    test('re-running a flat file makes no change', () {
      const sorted = '''
import 'dart:io';

import 'package:args/args.dart';

import 'helper.dart';

void main() {}
''';

      final result = sortImports(
        sorted.split('\n'),
        'demo',
        false,
        false,
        false,
        flat: true,
      );

      expect(result.updated, isFalse);
    });

    test('grouping options are ignored rather than half-applied', () {
      final result = sortImports(
        mixed,
        'demo',
        false,
        false,
        false,
        flat: true,
        groupProjectByFolder: true,
        testImports: true,
        separateRelativeImports: true,
      );

      expect(result.sortedFile, isNot(contains('//')));
      expect(
        result.sortedFile,
        sortImports(mixed, 'demo', false, false, false, flat: true).sortedFile,
        reason: 'grouping options shape groups, and flat has none — switching '
            'them on has to change nothing at all, rather than half of it',
      );
    });
  });

  group('relative imports (--relative-imports)', () {
    test('is off by default', () {
      final lines = [
        "import 'package:demo/src/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(lines, 'demo', false, false, false,
          libRelativePath: 'a.dart');

      expect(
          result.sortedFile, contains("import 'package:demo/src/foo.dart';"));
    });

    test('rewrites a package: uri as a path from this file', () {
      final lines = [
        "import 'package:demo/src/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(result.sortedFile, startsWith("import 'src/foo.dart';"));
    });

    test('walks up out of a sibling folder', () {
      final lines = [
        "import 'package:demo/src/foo.dart';",
        "import 'package:demo/src/p2/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'src/p2/bar.dart',
      );

      expect(result.sortedFile, contains("import '../foo.dart';"));
      expect(result.sortedFile, contains("import 'foo.dart';"));
    });

    test('leaves another package alone', () {
      final lines = [
        "import 'package:http/http.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(result.sortedFile, contains("import 'package:http/http.dart';"));
    });

    test('does nothing without a path to be relative to', () {
      final lines = [
        "import 'package:demo/src/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
      );

      expect(
          result.sortedFile, contains("import 'package:demo/src/foo.dart';"));
    });

    test('keeps the prefix and the trailing comment', () {
      final lines = [
        "import 'package:demo/src/foo.dart' as foo; // why",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(
        result.sortedFile,
        startsWith("import 'src/foo.dart' as foo; // why"),
      );
    });

    test('a rewritten uri can then be seen as a duplicate', () {
      final lines = [
        "import 'package:demo/src/foo.dart';",
        "import 'src/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        removeDuplicates: true,
        libRelativePath: 'a.dart',
      );

      expect(result.duplicatesRemoved, 1);
    });

    test('rewrites a uri written on the line after the keyword', () {
      // The text used to keep the package: uri while the sort key became the
      // relative one, so the import was filed among the relative imports.
      final lines = [
        "import 'package:http/http.dart';",
        'import',
        "    'package:demo/src/foo.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(
        result.sortedFile,
        "import 'package:http/http.dart';\n"
        '\n'
        'import\n'
        "    'src/foo.dart';\n"
        '\n'
        'void main() {}\n',
      );
    });

    test('rewrites every target of a conditional import', () {
      final lines = [
        "import 'package:demo/src/stub.dart'",
        "    if (dart.library.io) 'package:demo/src/io.dart'",
        "    if (dart.library.js_interop) 'package:demo/src/web.dart';",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(
        result.sortedFile,
        startsWith(
          "import 'src/stub.dart'\n"
          "    if (dart.library.io) 'src/io.dart'\n"
          "    if (dart.library.js_interop) 'src/web.dart';\n",
        ),
      );
    });

    test('refuses to run beside --package-imports', () {
      expect(
        () => sortImports(
          ["import 'a.dart';"],
          'demo',
          false,
          false,
          true,
          relativeImports: true,
          packageImports: true,
          libRelativePath: 'b.dart',
        ),
        throwsArgumentError,
      );
    });

    test('never rewrites a uri quoted in the trailing comment', () {
      final lines = [
        "import 'package:demo/src/foo.dart'; // was 'package:demo/old.dart'",
        '',
        'void main() {}',
      ];

      final result = sortImports(
        lines,
        'demo',
        false,
        false,
        true,
        relativeImports: true,
        libRelativePath: 'a.dart',
      );

      expect(
        result.sortedFile,
        startsWith("import 'src/foo.dart'; // was 'package:demo/old.dart'"),
      );
    });
  });

  group('package imports (--package-imports)', () {
    String sortPackaged(List<String> lines, String from) => sortImports(
          [...lines, '', 'void main() {}'],
          'demo',
          false,
          false,
          true,
          packageImports: true,
          libRelativePath: from,
        ).sortedFile;

    test('is off by default', () {
      final result = sortImports(
        ["import 'src/foo.dart';", '', 'void main() {}'],
        'demo',
        false,
        false,
        true,
        libRelativePath: 'a.dart',
      );

      expect(result.sortedFile, startsWith("import 'src/foo.dart';"));
    });

    test('rewrites a relative uri as a package: uri of this package', () {
      expect(
        sortPackaged(["import '../foo.dart';"], 'src/p2/bar.dart'),
        startsWith("import 'package:demo/src/foo.dart';"),
      );
    });

    test('resolves a sibling and a ./ path', () {
      expect(
        sortPackaged(
          ["import './widgets/card.dart';", "import 'theme.dart';"],
          'features/home/view.dart',
        ),
        startsWith(
          "import 'package:demo/features/home/theme.dart';\n"
          "import 'package:demo/features/home/widgets/card.dart';\n",
        ),
      );
    });

    test('leaves a uri that climbs out of lib/ as written', () {
      // `../../test/x.dart` from lib/a.dart is not in any package: form.
      expect(
        sortPackaged(["import '../test/fake.dart';"], 'a.dart'),
        startsWith("import '../test/fake.dart';"),
      );
    });

    test('leaves dart:, package: and root-relative uris alone', () {
      final sorted = sortPackaged(
        [
          "import 'dart:io';",
          "import 'package:http/http.dart';",
          "import '/features/x.dart';",
        ],
        'a.dart',
      );

      expect(sorted, contains("import 'dart:io';"));
      expect(sorted, contains("import 'package:http/http.dart';"));
      expect(sorted, contains("import '/features/x.dart';"));
    });

    test('does nothing outside lib/', () {
      final result = sortImports(
        ["import 'helpers.dart';", '', 'void main() {}'],
        'demo',
        false,
        false,
        true,
        packageImports: true,
      );

      expect(result.sortedFile, startsWith("import 'helpers.dart';"));
    });

    test('keeps the prefix, the show clause and the trailing comment', () {
      expect(
        sortPackaged(
          ["import 'src/foo.dart' as foo show Foo; // why"],
          'a.dart',
        ),
        startsWith(
            "import 'package:demo/src/foo.dart' as foo show Foo; // why"),
      );
    });

    test('rewrites every target of a conditional import', () {
      expect(
        sortPackaged(
          [
            "import 'stub.dart'",
            "    if (dart.library.io) 'io.dart'",
            "    if (dart.library.js_interop == 'true') 'web.dart';",
          ],
          'src/a.dart',
        ),
        startsWith(
          "import 'package:demo/src/stub.dart'\n"
          "    if (dart.library.io) 'package:demo/src/io.dart'\n"
          "    if (dart.library.js_interop == 'true') "
          "'package:demo/src/web.dart';\n",
        ),
        reason: "the `== 'true'` value is quoted too, but it is not a path",
      );
    });

    test('rewrites a uri written on the line after the keyword', () {
      expect(
        sortPackaged(['import', "    '../foo.dart';"], 'src/a.dart'),
        startsWith("import\n    'package:demo/foo.dart';\n"),
      );
    });

    test('a rewritten uri can then be seen as a duplicate', () {
      final result = sortImports(
        [
          "import 'package:demo/src/foo.dart';",
          "import 'src/foo.dart';",
          '',
          'void main() {}',
        ],
        'demo',
        false,
        false,
        true,
        packageImports: true,
        removeDuplicates: true,
        libRelativePath: 'a.dart',
      );

      expect(result.duplicatesRemoved, 1);
    });

    test('is stable: a second run changes nothing', () {
      final once = sortPackaged(
        ["import '../foo.dart';", "import 'package:http/http.dart';"],
        'src/a.dart',
      );
      final twice = sortImports(
        const LineSplitter().convert(once),
        'demo',
        false,
        false,
        true,
        packageImports: true,
        libRelativePath: 'src/a.dart',
      );

      expect(twice.updated, isFalse);
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
