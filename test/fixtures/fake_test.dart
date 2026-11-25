import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake.dart';
import 'fake_agent/main.dart' show portedScenarios, scenarios;

void main() {
  group('the Dart fake', () {
    test('it plays every scenario, and every caller runs it', () {
      expect(portedScenarios, containsAll(scenarios));
      expect(scenarios, containsAll(portedScenarios));
      expect(fakeAgent.reason, isNull);
      expect(fakeAgentCommand('text', ['--no-usage']), [
        dartExecutable(),
        dartFakeSnapshot(),
        '--scenario',
        'text',
        '--no-usage',
      ]);
      expect(fakeAgentCommand(), [dartExecutable(), dartFakeSnapshot()]);
      expect(fakeAgentCommand('text'), dartFakeCommand('text'));
    });

    test('its sources are its entry point and every file it imports by a '
        'relative path, and of the app only the team file reader', () {
      final root = portPackageDir();
      final sources = [
        for (final path in dartFakeSources(root)) p.relative(path, from: root),
      ];
      expect(sources, contains(dartFakeMain));
      expect(
        sources,
        containsAll([
          'test/fixtures/fake_agent/rpc.dart',
          'test/fixtures/fake_agent/scenarios/text.dart',
          'test/fixtures/forms.dart',
          'test/fixtures/markdown.dart',
        ]),
      );
      expect(sources, everyElement(startsWith('test/fixtures/')));
      // As the original's teams.ts reads a --propose-team file with the
      // app's own parser, the Dart teams.dart alone imports the app's.
      final app = RegExp(r"^import 'package:chord/([^']+)'", multiLine: true);
      for (final path in dartFakeSources(root)) {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('package:test/')), reason: path);
        expect(
          [for (final match in app.allMatches(text)) match.group(1)],
          p.relative(path, from: root) ==
                  'test/fixtures/fake_agent/scenarios/teams.dart'
              ? ['teams.dart']
              : isEmpty,
          reason: path,
        );
      }
    });

    test('its snapshot is kept by the hash of its sources, built once, and '
        'an edit builds another', () {
      final root = Directory.systemTemp.createTempSync('chord-fake-cache-');
      addTearDown(() => root.deleteSync(recursive: true));
      final real = portPackageDir();
      // A package of the fake's sources alone, with the port's packages.
      for (final path in [
        ...dartFakeSources(real),
        p.join(real, 'pubspec.yaml'),
        p.join(real, 'pubspec.lock'),
        p.join(real, '.dart_tool', 'package_config.json'),
      ]) {
        final copy = File(p.join(root.path, p.relative(path, from: real)))
          ..createSync(recursive: true);
        copy.writeAsStringSync(
          File(path).readAsStringSync().replaceAll(
            '"rootUri": "../',
            '"rootUri": "${Uri.directory(real)}',
          ),
        );
      }
      final hash = dartFakeHash(root.path);
      final first = dartFakeSnapshot(root.path);
      expect(p.basename(first), '$hash.dill');
      final built = File(first).lastModifiedSync();
      expect(dartFakeSnapshot(root.path), first);
      expect(File(first).lastModifiedSync(), built);
      expect(
        Directory(
          p.join(root.path, dartFakeCache),
        ).listSync().map((e) => p.basename(e.path)).toSet(),
        {p.basename(first), '.lock'},
        reason: 'no partial file is left',
      );

      File(
        p.join(root.path, 'test/fixtures/markdown.dart'),
      ).writeAsStringSync('\n// edited\n', mode: FileMode.append);
      expect(dartFakeHash(root.path), isNot(hash));
      expect(dartFakeSnapshot(root.path), isNot(first));
    });

    test('its key covers the app sources the team file reader imports, '
        'and the framework sources they import', () {
      final root = Directory.systemTemp.createTempSync('chord-fake-key-');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String text) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      write(dartFakeMain, "import 'scenarios/teams.dart';\n");
      write(
        'test/fixtures/fake_agent/scenarios/teams.dart',
        "import 'package:chord/teams.dart';\nimport 'package:yaml/yaml.dart';\n",
      );
      write('lib/teams.dart', "import 'settings.dart';\n");
      write('lib/settings.dart', "import 'package:chord_tui/keys.dart';\n");
      write('packages/chord_tui/lib/keys.dart', "part 'keys_part.dart';\n");
      write('packages/chord_tui/lib/keys_part.dart', '// a part\n');
      write('lib/unused.dart', '// read by nothing\n');
      write('pubspec.lock', 'packages: {}\n');

      expect(
        [
          for (final path in dartFakeBuildSources(root.path))
            p.relative(path, from: root.path),
        ],
        [
          'lib/settings.dart',
          'lib/teams.dart',
          'packages/chord_tui/lib/keys.dart',
          'packages/chord_tui/lib/keys_part.dart',
          dartFakeMain,
          'test/fixtures/fake_agent/scenarios/teams.dart',
        ],
      );
      final before = dartFakeHash(root.path, sdk: 'sdk');
      for (final path in [
        'lib/settings.dart',
        'packages/chord_tui/lib/keys_part.dart',
      ]) {
        File(
          p.join(root.path, path),
        ).writeAsStringSync('// edited\n', mode: FileMode.append);
        expect(
          dartFakeHash(root.path, sdk: 'sdk'),
          isNot(before),
          reason: path,
        );
      }
      final edited = dartFakeHash(root.path, sdk: 'sdk');
      File(
        p.join(root.path, 'lib/unused.dart'),
      ).writeAsStringSync('// edited\n', mode: FileMode.append);
      expect(dartFakeHash(root.path, sdk: 'sdk'), edited);
      expect(
        dartFakeSources(
          root.path,
        ).map((path) => p.relative(path, from: root.path)),
        [dartFakeMain, 'test/fixtures/fake_agent/scenarios/teams.dart'],
        reason: 'the fixture boundary is walked apart',
      );
    });

    test('another SDK keeps its snapshot under another hash', () {
      final root = portPackageDir();
      expect(dartFakeHash(root), dartFakeHash(root, sdk: dartSdkVersion()));
      expect(dartSdkVersion(), contains(Platform.version.split(' ').first));
      expect(
        dartFakeHash(root, sdk: 'Dart SDK version: 0.0.0 (stable)'),
        isNot(dartFakeHash(root)),
      );
    });
  });

  test('gatedCommand runs the command once the gate exists', () {
    expect(gatedCommand('/t/gate', ['x', '-y']), [
      'sh',
      '-c',
      r'i=0; while [ ! -e "$0" ]; do '
          r'[ -d "${0%/*}" ] && [ "$i" -lt 600 ] || exit 1; '
          r'i=$((i + 1)); sleep 0.05; done; exec "$@"',
      '/t/gate',
      'x',
      '-y',
    ]);
  });

  test('the port package directory is the one holding pubspec.yaml', () {
    expect(
      File(p.join(portPackageDir(), 'pubspec.yaml')).readAsStringSync(),
      startsWith('name: chord\n'),
    );
    expect(p.isAbsolute(portPackageDir()), isTrue);
  });
}
