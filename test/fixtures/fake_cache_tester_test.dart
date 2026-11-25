import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake.dart';

const _graph = {
  dartFakeMain: "import 'loop.dart';\nimport 'package:chord/teams.dart';\n",
  'test/fixtures/fake_agent/loop.dart': "export 'main.dart';\n",
  'lib/teams.dart':
      "export 'teams_helper.dart';\nimport 'package:chord_tui/core.dart';\n",
  'lib/teams_helper.dart': "import 'package:chord/teams.dart';\n",
  'packages/chord_tui/lib/core.dart': "part 'core_part.dart';\n",
  'packages/chord_tui/lib/core_part.dart': "part of 'core.dart';\n",
  'pubspec.lock': 'packages: {}\n',
};

void _writeGraph(Directory root) {
  for (final entry in _graph.entries) {
    File(p.join(root.path, entry.key))
      ..createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
}

void main() {
  group('tester: CTUI-147 snapshot dependency graph boundaries', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-cache-graph-');
      _writeGraph(root);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'relative and package cycles terminate with each part exactly once',
      () {
        expect(
          [
            for (final source in dartFakeBuildSources(root.path))
              p.relative(source, from: root.path),
          ],
          _graph.keys.where((path) => path.endsWith('.dart')).toList()..sort(),
        );
      },
    );

    test('relocating the same local source graph keeps the cache key', () {
      final other = Directory.systemTemp.createTempSync(
        'chord-cache-relocated-',
      );
      addTearDown(() => other.deleteSync(recursive: true));
      _writeGraph(other);
      expect(
        dartFakeHash(other.path, sdk: 'fixture SDK'),
        dartFakeHash(root.path, sdk: 'fixture SDK'),
      );
    });

    test(
      'a dependency lock change invalidates an otherwise identical graph',
      () {
        final before = dartFakeHash(root.path, sdk: 'fixture SDK');
        File(
          p.join(root.path, 'pubspec.lock'),
        ).writeAsStringSync('packages: {fixture: 2}\n');
        expect(dartFakeHash(root.path, sdk: 'fixture SDK'), isNot(before));
      },
    );
  });
}
