import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/notices.dart';
import '../../../tool/release/runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

Map<String, Object?> graphOf(Map<String, List<String>> deps) => {
  'roots': ['chord'],
  'packages': [
    for (final MapEntry(:key, :value) in deps.entries)
      {
        'name': key,
        'version': '1.0.0',
        'dependencies': value,
        if (key == 'chord') 'devDependencies': ['test'],
      },
  ],
};

void main() {
  group('compiled packages', () {
    test('are every dependency reached from chord, sorted, dev and own '
        'left out', () {
      final graph = graphOf({
        'chord': ['b', 'chord_tui'],
        'chord_tui': ['a'],
        'a': ['c'],
        'b': ['c'],
        'c': [],
        'test': ['d'],
        'd': [],
      });
      expect(compiledPackages(graph), ['a', 'b', 'c']);
    });

    test('a dependency missing from the graph stops the release', () {
      expect(
        () => compiledPackages(
          graphOf({
            'chord': ['gone'],
          }),
        ),
        dies('gone is not in the package graph'),
      );
    });
  });

  group('retained notices', () {
    test("are the files both READMEs' credits name, each from its folder", () {
      expect(creditedReadmes, ['README.md', 'packages/chord_tui/README.md']);
      expect(creditedFiles(File('README.md').readAsStringSync()), [
        'lib/ui/header/wordmark.dart',
      ]);
      expect(
        creditedFiles(File('packages/chord_tui/README.md').readAsStringSync()),
        ['lib/src/text/fzf.dart', 'lib/src/text/wrap_ansi.dart'],
      );
    });

    test('a README without credits stops the release, named', () {
      expect(() => creditedFiles('# x\n## Name\n'), dies('no Credits'));
      expect(
        () => creditedFiles('# x\n', name: 'packages/chord_tui/README.md'),
        dies('packages/chord_tui/README.md has no Credits section'),
      );
    });

    test('are the leading comment, without its marks', () {
      expect(
        leadingComment('// A port\n//\n// MIT\n\nimport "x";\n// later\n'),
        'A port\n\nMIT',
      );
    });
  });

  test('NOTICES lists the SDK, then the packages, then the retained', () {
    expect(
      renderNotices(
        sdk: 'SDK licence\n',
        packages: [(title: 'args 2.7.0', text: 'BSD')],
        retained: [(title: 'Retained in x.dart', text: 'MIT')],
      ),
      'chord is built with the Dart SDK and the packages below, and retains '
      'the notices of code it ported. Their licences follow.\n\n'
      '${'-' * 78}\nThe Dart SDK\n\nSDK licence\n\n'
      '${'-' * 78}\nargs 2.7.0\n\nBSD\n\n'
      '${'-' * 78}\nRetained in x.dart\n\nMIT\n',
    );
  });

  group('collected from a tree', () {
    late Directory root;
    late String sdk;
    setUp(() {
      root = Directory.systemTemp.createTempSync('notices_test');
      void write(String path, String text) => (File(
        p.join(root.path, path),
      )..createSync(recursive: true)).writeAsStringSync(text);
      final tool = '$portFolder/.dart_tool';
      write(
        '$tool/package_graph.json',
        jsonEncode({
          'roots': ['chord'],
          'packages': [
            {
              'name': 'chord',
              'version': '0.0.1',
              'dependencies': ['args'],
              'devDependencies': ['test'],
            },
            {'name': 'args', 'version': '2.7.0', 'dependencies': []},
            {'name': 'test', 'version': '1.0.0', 'dependencies': []},
          ],
        }),
      );
      write(
        '$tool/package_config.json',
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'chord', 'rootUri': '../'},
            {'name': 'args', 'rootUri': '../cache/args'},
            {
              'name': 'test',
              'rootUri': p.toUri(p.join(root.path, 'cache/test')).toString(),
            },
          ],
        }),
      );
      write('cache/args/LICENSE.md', 'args licence\n');
      write('cache/test/LICENSE', 'test licence\n');
      write('README.md', '# x\n\n## Credits\n\nSee [a](src/a.dart).\n');
      write('src/a.dart', '// ported a\n// MIT\n\nvoid main() {}\n');
      write(
        'packages/chord_tui/README.md',
        '# y\n\n## Credits\n\nSee [b](lib/b.dart).\n',
      );
      write('packages/chord_tui/lib/b.dart', '// ported b\n// BSD\n');
      write('sdk/LICENSE', 'dart licence\n');
      sdk = p.join(root.path, 'sdk');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('holds what is compiled in, and not the dev dependencies', () {
      final notices = collectNotices(root: root.path, sdkDir: sdk);
      expect(notices, contains('The Dart SDK\n\ndart licence'));
      expect(notices, contains('args 2.7.0\n\nargs licence'));
      expect(notices, contains('Retained in src/a.dart\n\nported a\nMIT'));
      expect(
        notices,
        contains('Retained in packages/chord_tui/lib/b.dart\n\nported b\nBSD'),
      );
      expect(notices, isNot(contains('test licence')));
    });

    test('a package without a licence stops the release', () {
      File(p.join(root.path, 'cache/args/LICENSE.md')).deleteSync();
      expect(
        () => collectNotices(root: root.path, sdkDir: sdk),
        dies('args has no licence file'),
      );
    });

    test("the SDK's licence missing stops the release", () {
      expect(
        () => collectNotices(root: root.path, sdkDir: p.join(root.path, 'x')),
        dies("The Dart SDK's licence is missing"),
      );
    });

    void rewrite(String path, String text) =>
        File(p.join(root.path, path)).writeAsStringSync(text);

    test('an empty SDK licence stops the release', () {
      rewrite('sdk/LICENSE', ' \n');
      expect(
        () => collectNotices(root: root.path, sdkDir: sdk),
        dies("The Dart SDK's licence is empty"),
      );
    });

    test("the framework README's Credits missing stops the release", () {
      rewrite('packages/chord_tui/README.md', '# y\n');
      expect(
        () => collectNotices(root: root.path, sdkDir: sdk),
        dies('packages/chord_tui/README.md has no Credits section'),
      );
    });

    test('an empty package licence stops the release', () {
      rewrite('cache/args/LICENSE.md', '');
      expect(
        () => collectNotices(root: root.path, sdkDir: sdk),
        dies("args's licence is empty"),
      );
    });

    for (final (what, text) in [
      ('no leading notice', 'import "x.dart";\n// later\n'),
      ('a blank comment header', '//\n//   \n\nvoid main() {}\n'),
    ]) {
      test('a credited file with $what stops the release', () {
        rewrite('src/a.dart', text);
        expect(
          () => collectNotices(root: root.path, sdkDir: sdk),
          dies('The notice retained in src/a.dart is empty'),
        );
      });
    }
  });

  test("the port's own tree yields NOTICES for every compiled package", () {
    final root = p.normalize(p.absolute('.'));
    final graph =
        jsonDecode(File('.dart_tool/package_graph.json').readAsStringSync())
            as Map<String, Object?>;
    final notices = collectNotices(
      root: root,
      sdkDir: p.dirname(p.dirname(Platform.resolvedExecutable)),
    );
    final compiled = compiledPackages(graph);
    expect(compiled, containsAll(['args', 'pub_semver', 'yaml']));
    expect(compiled, isNot(contains('test')));
    for (final name in compiled) {
      expect(notices, contains('\n$name '), reason: name);
    }
    expect(notices, contains('Copyright (c) 2021 Ajit'));
    expect(notices, contains('Copyright (c) 2025 opentui'));
  });

  group('tester: notice graph and source boundaries', () {
    test('cycles and duplicate paths contribute each dependency once', () {
      expect(
        compiledPackages(
          graphOf({
            'chord': ['a', 'a', 'chord_tui'],
            'chord_tui': ['b'],
            'a': ['b'],
            'b': ['a', 'chord'],
          }),
        ),
        ['a', 'b'],
      );
    });

    test('a dev dependency also reached in production keeps its licence', () {
      expect(
        compiledPackages(
          graphOf({
            'chord': ['bridge'],
            'bridge': ['test'],
            'test': [],
          }),
        ),
        ['bridge', 'test'],
      );
    });

    test('credit links outside the Credits section are not retained', () {
      expect(
        creditedFiles(
          '# x\n[other](before.dart)\n\n## Credits\n'
          '[notice](src/notice.dart)\n\n## Other\n[later](after.dart)\n',
        ),
        ['src/notice.dart'],
      );
    });

    test(
      'CRLF headers preserve Unicode notices and stop before later code',
      () {
        expect(
          leadingComment(
            '// Copyright 界 😀 e\u0301\r\n// MIT\r\n'
            '\r\nvoid main() {}\r\n// later\r\n',
          ),
          'Copyright 界 😀 e\u0301\nMIT',
        );
      },
    );

    test('escaped relative package roots resolve from the config file', () {
      final root = Directory.systemTemp.createTempSync('notice_uri_test');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String file, String text) => (File(
        p.join(root.path, file),
      )..createSync(recursive: true)).writeAsStringSync(text);
      final tool = '$portFolder/.dart_tool';
      write(
        '$tool/package_graph.json',
        jsonEncode(
          graphOf({
            'chord': ['dep'],
            'dep': [],
          }),
        ),
      );
      write(
        '$tool/package_config.json',
        jsonEncode({
          'packages': [
            {'name': 'chord', 'rootUri': '../'},
            {'name': 'dep', 'rootUri': '../cache/space%20package'},
          ],
        }),
      );
      write('cache/space package/COPYING', 'dependency notice');
      write('README.md', '## Credits\n[notice](src/n.dart)\n');
      write('src/n.dart', '// retained notice\n');
      write(
        'packages/chord_tui/README.md',
        '## Credits\n[notice](lib/m.dart)\n',
      );
      write('packages/chord_tui/lib/m.dart', '// retained\n');
      write('sdk/LICENSE', 'SDK notice');
      expect(
        collectNotices(root: root.path, sdkDir: p.join(root.path, 'sdk')),
        contains('dep 1.0.0\n\ndependency notice'),
      );
      File(p.join(root.path, 'src/n.dart')).deleteSync();
      expect(
        () => collectNotices(root: root.path, sdkDir: p.join(root.path, 'sdk')),
        dies('A credited file is missing'),
      );
    });
  });
}
