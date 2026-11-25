// Writing one key of the user's settings file, from the original's
// tests/settings_test.ts: every other key kept in its place, the file made
// when missing, and a broken file never overwritten.
import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A config home and a project, both temporary, with [user] and [project]
/// written into them.
Future<void> place(
  Future<void> Function(String configHome, String cwd) run, {
  String? user,
  String? project,
}) async {
  final root = await Directory.systemTemp.createTemp('chord-settings-');
  try {
    final configHome = p.join(root.path, 'config');
    final cwd = p.join(root.path, 'work');
    await Directory(cwd).create();
    if (user != null) {
      await File(userSettingsFile(configHome)!).create(recursive: true);
      await File(userSettingsFile(configHome)!).writeAsString(user);
    }
    if (project != null) {
      final file = File(p.join(cwd, '.chord', 'settings.json'));
      await file.create(recursive: true);
      await file.writeAsString(project);
    }
    await run(configHome, cwd);
  } finally {
    await root.delete(recursive: true);
  }
}

List<String> beside(String file) => [
  for (final entry in Directory(p.dirname(file)).listSync())
    p.basename(entry.path),
];

void main() {
  test('saving the theme keeps every other key, in its place', () async {
    await place(
      user: '{\n  "agent": "codex",\n  "theme": "dark",\n  "x": 1\n}\n',
      (home, _) async {
        final user = userSettingsFile(home)!;
        await saveTheme(user, 'light');
        expect(
          await File(user).readAsString(),
          '{\n  "agent": "codex",\n  "theme": "light",\n  "x": 1\n}\n',
        );
        // No temporary file is left beside it.
        expect(beside(user), ['settings.json']);
      },
    );
  });

  test('saving the theme makes the file and its directory', () async {
    await place((home, _) async {
      final user = userSettingsFile(home)!;
      await saveTheme(user, 'dark-daltonized');
      expect(
        await File(user).readAsString(),
        '{\n  "theme": "dark-daltonized"\n}\n',
      );
    });
  });

  test('a file that is not a JSON object is never overwritten', () async {
    for (final text in ['{ "agent": ', '[1, 2]']) {
      await place(user: text, (home, _) async {
        final user = userSettingsFile(home)!;
        await expectLater(
          saveTheme(user, 'light'),
          throwsA(
            isA<SettingRefused>().having(
              (e) => e.message,
              'message',
              text.startsWith('[')
                  ? 'it is not a JSON object'
                  : 'it is not valid JSON',
            ),
          ),
        );
        expect(await File(user).readAsString(), text);
      });
    }
  });

  test(
    '/vim is kept as the editor mode, every other key in its place',
    () async {
      await place(user: '{\n  "theme": "dark",\n  "x": 1\n}\n', (
        home,
        cwd,
      ) async {
        final user = userSettingsFile(home)!;
        await saveEditorMode(user, 'vim');
        expect(
          await File(user).readAsString(),
          '{\n  "theme": "dark",\n  "x": 1,\n  "editorMode": "vim"\n}\n',
        );
        Future<String?> mode() async => (await loadSettings(
          configHome: home,
          cwd: cwd,
        )).settings.editorMode;
        expect(await mode(), 'vim');
        await saveEditorMode(user, 'normal');
        expect(await mode(), 'normal');
      });
    },
  );

  test('saving other preferences keeps auto-copy disabled', () async {
    await place(user: '{ "copyOnSelect": false }', (home, cwd) async {
      final user = userSettingsFile(home)!;
      await saveTheme(user, 'light');
      await saveEditorMode(user, 'vim');
      final loaded = await loadSettings(configHome: home, cwd: cwd);
      expect(loaded.problems, isEmpty);
      expect(loaded.settings.copyOnSelect, isFalse);
      expect(loaded.settings.theme, 'light');
      expect(loaded.settings.editorMode, 'vim');
    });
  });

  test(
    'each write rereads hand edits and refuses a later broken file',
    () async {
      await place(user: '{}', (home, _) async {
        final file = userSettingsFile(home)!;
        await saveSettingAt(file, const ['theme'], const SetSetting('dark'));
        await File(
          file,
        ).writeAsString('{"theme":"light","keep":{"nested":[1,null]}}');
        await saveSettingAt(file, const [
          'agents',
          'my.agent',
          'model',
        ], const SetSetting('m'));
        expect(jsonDecode(await File(file).readAsString()), {
          'theme': 'light',
          'keep': {
            'nested': [1, null],
          },
          'agents': {
            'my.agent': {'model': 'm'},
          },
        });
        const broken = '{"env":{"TOKEN":secret123}}';
        await File(file).writeAsString(broken);
        await expectLater(
          saveSettingAt(file, const ['theme'], const SetSetting('dark')),
          throwsA(isA<SettingRefused>()),
        );
        expect(await File(file).readAsString(), broken);
        expect(beside(file), ['settings.json']);
      });
    },
  );

  test(
    'removing a dotted name keeps its siblings, and the project file',
    () async {
      const project = '{ "agents": {"my.agent":{"model":"project"}} }';
      await place(
        user:
            '{"agents":{"my.agent":{"model":false},"hasOwnProperty":{"model":"keep"}}}',
        project: project,
        (home, cwd) async {
          final user = userSettingsFile(home)!;
          await saveSettingAt(user, const [
            'agents',
            'my.agent',
            'model',
          ], const RemoveSetting());
          expect(jsonDecode(await File(user).readAsString()), {
            'agents': {
              'hasOwnProperty': {'model': 'keep'},
            },
          });
          expect(
            await File(p.join(cwd, '.chord', 'settings.json')).readAsString(),
            project,
          );
        },
      );
    },
  );

  test(
    'forbidden keys are refused at every depth, the file untouched',
    () async {
      const raw = '{ "agents": {"codex":{"model":"m"}} }';
      await place(user: raw, (home, _) async {
        final file = userSettingsFile(home)!;
        for (final key in ['__proto__', 'constructor', 'prototype']) {
          for (final path in [
            [key],
            ['agents', key],
            ['agents', 'codex', key],
          ]) {
            await expectLater(
              saveSettingAt(file, path, const RemoveSetting()),
              throwsA(
                isA<SettingRefused>().having(
                  (e) => e.message,
                  'message',
                  startsWith('No setting '),
                ),
              ),
            );
          }
        }
        expect(await File(file).readAsString(), raw);
      });
    },
  );

  test(
    'a parent that is not an object refuses the write; no home, none',
    () async {
      await place(user: '{"agents":"codex"}', (home, _) async {
        final file = userSettingsFile(home)!;
        await expectLater(
          saveSettingAt(file, const [
            'agents',
            'codex',
            'model',
          ], const SetSetting('m')),
          throwsA(
            isA<SettingRefused>().having(
              (e) => e.message,
              'message',
              'its agents is not an object; edit it by hand',
            ),
          ),
        );
      });
      await expectLater(
        saveSettingAt(null, const ['theme'], const SetSetting('dark')),
        throwsA(
          isA<SettingRefused>().having(
            (e) => e.message,
            'message',
            noSettingsHome,
          ),
        ),
      );
    },
  );
}
