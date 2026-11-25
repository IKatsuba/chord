// chord's `settings` tool without the server or the window, as the
// original's tests/settings_tool_test.ts has it; the parts that draw its
// row come with the row.
import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:chord/settings_tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _known = ['claude', 'codex', 'my.agent'];
SetSetting _set(Object? value) => SetSetting(value);
const _remove = RemoveSetting();

/// A home and a project under a temporary root, with the files given, as
/// text or as JSON.
Future<void> _placed(
  ({Object? user, Object? project}) files,
  Future<void> Function(SettingsWhere where, String userFile, String root) run,
) async {
  final root = Directory.systemTemp.createTempSync('chord-settings-tool-');
  final home = p.join(root.path, 'home');
  final where = SettingsWhere(
    home: home,
    configHome: p.join(home, '.config'),
    cwd: p.join(root.path, 'work'),
  );
  final userFile = p.join(where.configHome!, 'chord', 'settings.json');
  try {
    Directory(p.dirname(userFile)).createSync(recursive: true);
    Directory(p.join(where.cwd, '.chord')).createSync(recursive: true);
    for (final (file, value) in [
      (userFile, files.user),
      (p.join(where.cwd, '.chord', 'settings.json'), files.project),
    ]) {
      if (value == null) continue;
      File(file).writeAsStringSync(value is String ? value : jsonEncode(value));
    }
    await run(where, userFile, root.path);
  } finally {
    root.deleteSync(recursive: true);
  }
}

final _shownFile = '~${p.join('/', '.config', 'chord', 'settings.json')}';
final _projectShown = p.join('.chord', 'settings.json');

Future<SettingsReadAnswer> _read(
  SettingsWhere where, [
  List<String> path = const [],
]) async => await readSettingsTool(where, path) as SettingsReadAnswer;

Future<SettingsChanged> _planned(
  SettingsWhere where,
  List<String> path,
  SettingChange change, [
  List<String> known = _known,
]) async =>
    (await plannedSetting(where, path, change, known) as PlannedSetting).answer;

Future<String> _refused(
  SettingsWhere where,
  List<String> path,
  SettingChange change,
) async =>
    (await plannedSetting(where, path, change, _known) as SettingsToolRefused)
        .error;

/// Everything a read or a change gives, as the agent is told it.
String _everything(Object answer, [SettingsReadAnswer? read]) => jsonEncode([
  switch (answer) {
    SettingsRead() => answer.toJson(),
    SettingsChanged() => answer.toJson(),
    _ => answer,
  },
  if (read != null) [read.user, read.project],
]);

void main() {
  group('validation boundaries', () {
    test('a malformed list is refused before any unknown agent is '
        'considered', () {
      final offered = ['unknown-first', null, 'codex'];
      expect(
        settingRefusal(['offeredAgents'], _set(offered), _known),
        startsWith('offeredAgents cannot be ["unknown-first",null,"codex"]: '),
      );
      expect(
        settingRefusal(
          ['offeredAgents'],
          _set(['codex', 'unknown-second']),
          _known,
        ),
        'chord knows no agent named "unknown-second"; list_agents names '
        'every one',
      );
    });

    test('known own agent names may resemble object methods or contain '
        'terminal controls', () {
      const names = ['toString', 'hasOwnProperty', 'agent.\u009b\u202e'];
      for (final name in names) {
        expect(
          settingRefusal(['agents', name, 'model'], _set('m'), names),
          isNull,
        );
        expect(settingRefusal(['agent'], _set(name), names), isNull);
        expect(
          settingRefusal(
            ['teamSelection', 'prefer', 'agent'],
            _set(name),
            names,
          ),
          isNull,
        );
      }
      final refused = settingRefusal(
        ['agents', names[2], 'effort'],
        _set('external-effort'),
        const [],
      );
      expect(refused, contains(r'agent.\u009b\u202e'));
      expect(
        refused,
        isNot(matches(RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true))),
      );
    });

    test('forbidden keys stay unknown even below hand-edit branches', () {
      for (final key in ['__proto__', 'constructor', 'prototype']) {
        for (final path in [
          ['mcpServers', 'server', 'env', key],
          ['agents', 'codex', 'command', key],
          ['teamSelection', 'constraints', 'models', key],
        ]) {
          expect(classifySetting(path), isA<UnknownSetting>());
          expect(
            settingRefusal(path, _remove, _known),
            startsWith('No setting '),
          );
          expect(
            settingRefusal(path, _set(null), _known),
            startsWith('No setting '),
          );
        }
      }
    });

    test('null resets only the nullable preference, and removal accepts an '
        'unknown effort owner', () {
      expect(
        settingRefusal(['teamSelection', 'prefer', 'model'], _set(null), []),
        isNull,
      );
      for (final path in [
        ['agents', 'codex', 'model'],
        ['agents', 'codex', 'effort'],
        ['teamSelection', 'prefer', 'agent'],
        ['teamSelection', 'intent'],
      ]) {
        expect(
          settingRefusal(path, _set(null), _known),
          contains('cannot be null:'),
        );
      }
      expect(
        settingRefusal(['agents', 'gone.agent', 'effort'], _remove, []),
        isNull,
      );
      expect(
        settingRefusal(
          ['agents', 'codex', 'model'],
          _set('unknown.model'),
          _known,
        ),
        isNull,
      );
    });
  });

  group('classifySetting', () {
    for (final (path, userOnly, takesEffect) in [
      (['theme'], true, 'now'),
      (['editorMode'], true, 'now'),
      (['mouse'], true, 'next start'),
      (['copyOnSelect'], true, 'next start'),
      (['offeredAgents'], true, 'now'),
      (['preferredNotifChannel'], false, 'next start'),
      (['agent'], false, 'next start'),
      (['agents', 'codex', 'model'], false, 'next start'),
      (['agents', 'codex', 'effort'], false, 'next start'),
      (['teamSelection', 'intent'], false, 'now'),
      (['teamSelection', 'prefer', 'agent'], false, 'now'),
      (['teamSelection', 'prefer', 'model'], false, 'now'),
    ]) {
      test('$path is writable', () {
        final named = classifySetting(path) as WritableSetting;
        expect(
          (named.userOnly, named.takesEffect.words),
          (userOnly, takesEffect),
        );
      });
    }

    for (final path in [
      ['agents', 'codex', 'command'],
      ['agents', 'codex', 'command', '0'],
      ['agents', 'codex', 'permissionMode'],
      ['agents', 'codex', 'mcpServers'],
      ['mcpServers'],
      ['mcpServers', 'linear'],
      ['mcpServers', 'linear', 'env', 'TOKEN'],
      ['teamSelection', 'constraints'],
      ['teamSelection', 'constraints', 'agents'],
      ['teamSelection', 'constraints', 'models', 'codex'],
    ]) {
      test('$path stays a hand edit', () {
        expect(classifySetting(path), isA<HandSetting>());
      });
    }

    for (final path in [
      ['nope'],
      ['theme', 'deeper'],
      ['toString'],
      ['agents', 'codex', 'modle'],
      ['agents', 'codex', 'model', 'deeper'],
      ['agents', 'codex', 'toString'],
      ['teamSelection', 'nope'],
      ['teamSelection', 'intent', 'deeper'],
      ['teamSelection', 'prefer', 'nope'],
      ['teamSelection', 'prefer', 'toString'],
      ['teamSelection', 'prefer', 'model', 'deeper'],
      ['__proto__'],
      ['constructor'],
      ['prototype'],
      ['agents', '__proto__', 'model'],
      ['agents', 'constructor', 'model'],
      ['theme', '__proto__'],
      <String>[],
    ]) {
      test('$path is no setting', () {
        expect(classifySetting(path), isA<UnknownSetting>());
      });
    }
  });

  group('settingRefusal', () {
    for (final (path, line) in [
      (['agents', 'claude', 'modle'], 'No setting agents.claude.modle'),
      (['__proto__'], 'No setting __proto__'),
      (['agents', 'my.agent', 'x'], 'No setting agents."my.agent".x'),
      (
        ['agents', 'claude', 'command'],
        'chord does not write agents.claude.command; edit the settings file '
            'by hand',
      ),
      (
        ['mcpServers', 'x'],
        'chord does not write mcpServers.x; edit the settings file by hand',
      ),
      (
        ['agents', 'codex'],
        'agents.codex is not one setting; name agents.codex.model or '
            'agents.codex.effort',
      ),
      (
        ['agents'],
        'agents is not one setting; name agents.<name>.model or '
            'agents.<name>.effort',
      ),
      (
        ['teamSelection'],
        'teamSelection is not one setting; name teamSelection.intent, '
            'teamSelection.prefer.agent or teamSelection.prefer.model',
      ),
      (
        ['teamSelection', 'prefer'],
        'teamSelection.prefer is not one setting; name '
            'teamSelection.prefer.agent or teamSelection.prefer.model',
      ),
    ]) {
      test('$path is refused on set and remove alike', () {
        expect(settingRefusal(path, _set('x'), _known), line);
        expect(settingRefusal(path, _remove, _known), line);
      });
    }

    test('the path is checked before the value', () {
      expect(settingRefusal(['nope'], _set(absent), []), 'No setting nope');
    });

    for (final (path, value, line) in [
      (
        ['editorMode'],
        'emacs',
        'editorMode cannot be "emacs": Invalid option: expected one of '
            '"normal"|"vim"',
      ),
      (
        ['mouse'],
        'yes',
        'mouse cannot be "yes": Invalid input: expected boolean, received '
            'string',
      ),
      (
        ['agent'],
        '',
        'agent cannot be "": Too small: expected string to have >=1 '
            'characters',
      ),
      (
        ['offeredAgents'],
        ['claude', 3],
        'offeredAgents cannot be ["claude",3]: expected a list of one or more '
            'agent names',
      ),
      (
        ['offeredAgents'],
        <String>[],
        'offeredAgents cannot be []: expected a list of one or more agent '
            'names',
      ),
      (
        ['agents', 'claude', 'model'],
        null,
        'agents.claude.model cannot be null: Invalid input: expected string, '
            'received null',
      ),
    ]) {
      test('$path with $value is refused by its own schema', () {
        expect(settingRefusal(path, _set(value), _known), line);
      });
    }

    test('a value left out is refused, not written as nothing', () {
      expect(
        settingRefusal(['theme'], _set(absent), _known),
        startsWith('theme cannot be left out: '),
      );
      expect(
        settingRefusal(
          ['teamSelection', 'prefer', 'model'],
          _set(absent),
          _known,
        ),
        startsWith('teamSelection.prefer.model cannot be left out: '),
      );
    });

    test('a value that holds a control reads escaped in the refusal', () {
      expect(
        settingRefusal(['theme'], _set('\u009b31m'), _known),
        startsWith(r'theme cannot be "\u009b31m": '),
      );
    });

    for (final (path, value) in [
      (['theme'], 'dark'),
      (['editorMode'], 'vim'),
      (['mouse'], false),
      (['copyOnSelect'], true),
      (['offeredAgents'], ['claude', 'codex']),
      (['preferredNotifChannel'], 'bell'),
      (['agent'], 'claude'),
      (['agents', 'my.agent', 'model'], 'any-id-at-all'),
      (['agents', 'codex', 'effort'], 'unheard-of'),
      (['teamSelection', 'intent'], 'economy'),
      (['teamSelection', 'prefer', 'agent'], 'codex'),
      (['teamSelection', 'prefer', 'model'], 'any-id'),
      (['teamSelection', 'prefer', 'model'], null),
    ]) {
      test('$path takes $value', () {
        expect(settingRefusal(path, _set(value), _known), isNull);
      });
    }

    for (final (path, value, name) in [
      (['agents', 'nope', 'model'], 'm', 'nope'),
      (['agent'], 'nope', 'nope'),
      (['offeredAgents'], ['claude', 'nope', 'other'], 'nope'),
      (['teamSelection', 'prefer', 'agent'], 'nope', 'nope'),
      (['agents', 'a"b', 'effort'], 'm', r'a\"b'),
    ]) {
      test('$path with $value names an agent chord lacks', () {
        expect(
          settingRefusal(path, _set(value), _known),
          'chord knows no agent named "$name"; list_agents names every one',
        );
      });
    }

    test('the schema is checked before the names', () {
      expect(
        settingRefusal(['agents', 'nope', 'model'], _set(''), _known),
        startsWith('agents.nope.model cannot be "": '),
      );
    });

    test('a remove checks no name and no value', () {
      for (final path in [
        ['agents', 'stale', 'model'],
        ['agent'],
        ['offeredAgents'],
        ['theme'],
      ]) {
        expect(settingRefusal(path, _remove, _known), isNull);
      }
    });

    test('a file refusal ends with what the writer said', () {
      expect(
        notSavedLine('~/.config/chord/settings.json', 'it is not valid JSON'),
        '~/.config/chord/settings.json was not saved: it is not valid JSON',
      );
    });
  });

  test('repeated reads observe repairs and removal without writing either '
      'file', () async {
    await _placed(
      (
        user: '{ "agent":"claude", "theme":"dark" }',
        project: '{ "agent":"codex" }',
      ),
      (where, user, _) async {
        final project = p.join(where.cwd, '.chord', 'settings.json');
        final first = (await _read(where, ['agent'])).answer;
        expect(
          (first.user, first.project, first.effective),
          ('claude', 'codex', 'codex'),
        );
        File(
          project,
        ).writeAsStringSync('{"mcpServers":{"x":{"env":secret-fresh}}}');
        final broken = await _read(where, ['agent']);
        expect(
          (broken.answer.user, broken.answer.effective),
          ('claude', 'claude'),
        );
        expect(
          _everything(broken.answer, broken),
          isNot(contains('secret-fresh')),
        );
        expect(
          _everything(broken.answer, broken),
          contains('not valid JSON; ignored'),
        );
        File(project).deleteSync();
        final removed = (await _read(where, ['agent'])).answer;
        expect(
          (removed.user, removed.effective, removed.problems.length),
          ('claude', 'claude', 0),
        );
        expect(
          File(user).readAsStringSync(),
          '{ "agent":"claude", "theme":"dark" }',
        );
      },
    );
  });

  group('planning a settings change', () {
    test('a set on an unset key, on a held key, and a remove', () async {
      await _placed(
        (
          user: {
            'agents': {
              'fake': {'model': 'old'},
            },
          },
          project: null,
        ),
        (where, file, _) async {
          final unset =
              await plannedSetting(where, ['theme'], _set('dark'), _known)
                  as PlannedSetting;
          expect(unset.file, file);
          expect(unset.answer.toJson(), {
            'path': ['theme'],
            'after': 'dark',
            'file': _shownFile,
            'takesEffect': 'now',
          });
          final fresh = await _planned(where, [
            'agents',
            'claude',
            'model',
          ], _set('m'));
          expect(fresh.takesEffect, TakesEffect.nextStart);
          final held = await _planned(
            where,
            ['agents', 'fake', 'model'],
            _set('new'),
            ['fake'],
          );
          expect(
            (held.before, held.after, changeWord(held)),
            ('old', 'new', 'change'),
          );
          final gone = await _planned(
            where,
            ['agents', 'fake', 'model'],
            _remove,
            [],
          );
          expect(gone.before, 'old');
          expect(gone.toJson().containsKey('after'), isFalse);
          expect(changeWord(gone), 'remove');
          expect(changeWord(unset.answer), 'set');
        },
      );
    });

    test('the same value and a remove of an absent key do nothing', () async {
      await _placed((user: {'theme': 'dark'}, project: null), (
        where,
        _,
        _,
      ) async {
        for (final answer in [
          await _planned(where, ['theme'], _set('dark')),
          await _planned(where, ['mouse'], _remove),
        ]) {
          expect((answer.saved, answer.unchanged), (false, true));
        }
      });
    });

    test('null is a value, not an absent key', () async {
      const path = ['teamSelection', 'prefer', 'model'];
      await _placed(
        (
          user: {
            'teamSelection': {
              'prefer': {'model': null},
            },
          },
          project: null,
        ),
        (where, _, _) async {
          final same = await _planned(where, path, _set(null));
          expect((same.unchanged, same.before), (true, null));
          expect(same.toJson().containsKey('before'), isTrue);
          expect((await _planned(where, path, _set('m'))).unchanged, isFalse);
          expect((await _planned(where, path, _remove)).unchanged, isFalse);
        },
      );
    });

    test('a refusal comes first, then no home, then the file, then its '
        'parent', () async {
      await _placed((user: '{ broken', project: null), (where, _, _) async {
        expect(await _refused(where, ['nope'], _set(1)), 'No setting nope');
        expect(
          await _refused(
            SettingsWhere(configHome: null, cwd: where.cwd, home: where.home),
            ['theme'],
            _set('dark'),
          ),
          'No settings file without a home directory; nothing was saved',
        );
        expect(
          await _refused(where, ['theme'], _set('dark')),
          '$_shownFile was not saved: it is not valid JSON',
        );
      });
      await _placed((user: '["a list"]', project: null), (where, _, _) async {
        expect(
          await _refused(where, ['theme'], _remove),
          '$_shownFile was not saved: it is not a JSON object',
        );
      });
      await _placed((user: '{"agents":3}', project: null), (where, _, _) async {
        for (final change in [_set('m'), _remove]) {
          expect(
            await _refused(where, ['agents', 'claude', 'model'], change),
            '$_shownFile was not saved: its agents is not an object; edit it '
            'by hand',
          );
        }
      });
    });

    test('a file that cannot be read names no home', () async {
      await _placed((user: null, project: null), (where, file, _) async {
        Directory(file).createSync();
        final error = await _refused(where, ['theme'], _set('dark'));
        expect(error, startsWith('$_shownFile was not saved: '));
        expect(error, isNot(contains(where.home!)));
      });
    });

    test('a project holding a key both files may set shadows it, changed or '
        'unchanged', () async {
      await _placed(
        (
          user: {'agent': 'claude'},
          project: {
            'agent': 'codex',
            'teamSelection': {
              'prefer': {'model': null},
            },
          },
        ),
        (where, _, _) async {
          expect(
            (await _planned(where, ['agent'], _set('codex'))).shadowedBy,
            _projectShown,
          );
          final unchanged = await _planned(where, ['agent'], _set('claude'));
          expect(
            (unchanged.unchanged, unchanged.shadowedBy),
            (true, _projectShown),
          );
          expect(
            (await _planned(where, [
              'teamSelection',
              'prefer',
              'model',
            ], _set('m'))).shadowedBy,
            _projectShown,
          );
        },
      );
    });

    test("nothing shadows a user-only key, or a value the project's check "
        'dropped', () async {
      await _placed((user: null, project: '{"theme":"dark","agent":3}'), (
        where,
        _,
        _,
      ) async {
        expect(
          (await _planned(where, ['theme'], _set('light'))).shadowedBy,
          isNull,
        );
        expect(
          (await _planned(where, ['agent'], _set('codex'))).shadowedBy,
          isNull,
        );
      });
    });

    test('a save that fails says the file, without the home', () {
      expect(
        saveFailure(
          '~/x.json',
          const FileSystemException(
            'Cannot open file',
            '/h/o/me/x.json',
            OSError('Permission denied', 13),
          ),
          '/h/o/me',
        ),
        '~/x.json was not saved: Permission denied, ~/x.json',
      );
      expect(
        saveFailure(
          '~/x.json',
          const SettingRefused('it is not valid JSON'),
          '/h',
        ),
        '~/x.json was not saved: it is not valid JSON',
      );
    });
  });

  group('a read answers only from what the check passed', () {
    const canary = 'canary-value-9f';
    const canaryKey = 'canaryKey9f';

    /// Reads every key, one key and one change, each checked for the
    /// canaries.
    Future<SettingsReadAnswer> nothingShows(SettingsWhere where) async {
      final whole = await _read(where);
      final key = await _read(where, ['agent']);
      final planned = await _planned(where, ['agent'], _set('codex'));
      for (final said in [
        _everything(whole.answer, whole),
        _everything(key.answer, key),
        _everything(planned),
      ]) {
        expect(said, isNot(contains(canary)));
        expect(said, isNot(contains(canaryKey)));
      }
      return whole;
    }

    final unknowns = jsonEncode({
      canaryKey: canary,
      'other': {
        canaryKey: [canary],
      },
      'agents': {
        'fake': {canaryKey: canary, 'model': 'm'},
      },
      'teamSelection': {canaryKey: canary},
      'agent': 'kept',
    });

    test(
      'a link to a file of unknown keys and values shows none of them',
      () async {
        await _placed((user: null, project: null), (where, _, root) async {
          final target = p.join(root, 'target.json');
          File(target).writeAsStringSync(unknowns);
          Link(p.join(where.cwd, '.chord', 'settings.json')).createSync(target);
          final answer = (await nothingShows(where)).answer;
          // A start follows links, so this is an ordinary read of what is
          // checked.
          expect((answer.project as Map)['agent'], 'kept');
          expect((answer.effective as Map)['agent'], 'kept');
          expect(
            answer.problems.map((each) => each.message),
            contains('4 keys ignored'),
          );
        });
      },
    );

    test('a broken file with a canary token shows no parser word', () async {
      await _placed((user: null, project: '{"agent":$canary}'), (
        where,
        _,
        _,
      ) async {
        final read = await nothingShows(where);
        expect(read.answer.project, isNull);
        expect(read.answer.problems, [
          (file: _projectShown, message: 'not valid JSON; ignored'),
        ]);
        expect(read.project, endsWith(' · not valid JSON'));
      });
    });

    test('wrong-typed values under real keys show neither value', () async {
      await _placed(
        (
          user: {
            'theme': canary,
            'mouse': canary,
            'agent': 7,
            'preferredNotifChannel': canary,
          },
          project: null,
        ),
        (where, _, _) async {
          final answer = (await nothingShows(where)).answer;
          expect(answer.user, <String, Object?>{});
          expect(answer.problems, [
            (file: _shownFile, message: '4 keys ignored'),
          ]);
        },
      );
    });

    test('a write over a bad value reads not set, in the answer', () async {
      await _placed((user: {'theme': canary}, project: null), (
        where,
        _,
        _,
      ) async {
        final planned = await _planned(where, ['theme'], _set('light'));
        expect(identical(planned.before, absent), isTrue);
        expect(_everything(planned), isNot(contains(canary)));
        final removed = await _planned(where, ['theme'], _remove);
        expect(removed.unchanged, isTrue);
        expect(_everything(removed), isNot(contains(canary)));
      });
    });

    test('a server keeps only its shape: token and Env are gone with their '
        'values', () async {
      final server = {
        'mcpServers': {
          'local': {
            'command': canary,
            'args': [canary],
            'env': {'TOKEN': canary},
            'Env': {'TOKEN': canary},
            'token': canary,
          },
          'remote': {
            'type': 'http',
            'url': 'https://example.test/x',
            'headers': {'Auth': canary},
            'token': canary,
          },
          'broken': {'token': canary},
          'text': canary,
        },
      };
      await _placed((user: server, project: server), (where, _, _) async {
        final answer = (await _read(where)).answer;
        const shown = {
          'mcpServers': {
            'local': {
              'command': '***',
              'args': ['***'],
              'env': {'TOKEN': '***'},
            },
            'remote': {
              'type': 'http',
              'url': '***',
              'headers': {'Auth': '***'},
            },
          },
        };
        expect(_everything(answer), isNot(contains(canary)));
        expect(
          [answer.user, answer.project, answer.effective],
          [shown, shown, shown],
        );
        // A server's own shape is not a settings problem.
        expect(answer.problems, isEmpty);
      });
    });

    test('a file that cannot be used is null, one with all its keys dropped '
        'is empty, and a key in either is not set', () async {
      await _placed((user: '{ broken', project: null), (where, _, _) async {
        expect((await _read(where)).answer.user, isNull);
        expect(
          identical((await _read(where, ['agent'])).answer.user, absent),
          isTrue,
        );
      });
      await _placed((user: {'nope': 1}, project: null), (where, _, _) async {
        expect((await _read(where)).answer.user, <String, Object?>{});
        expect(
          identical((await _read(where, ['agent'])).answer.user, absent),
          isTrue,
        );
      });
      await _placed((user: '{}', project: null), (where, _, _) async {
        expect((await _read(where)).answer.user, <String, Object?>{});
      });
    });

    test('a path reads what is masked, and below a leaf is not set', () async {
      await _placed(
        (
          user: {
            'mcpServers': {
              'x': {
                'command': canary,
                'env': {'TOKEN': canary},
              },
            },
            'agents': {
              'url': {'model': 'm', 'mcpServers': false},
              'a': {'command': canary},
            },
          },
          project: null,
        ),
        (where, _, _) async {
          Future<Object?> at(List<String> path) async =>
              (await _read(where, path)).answer.user;
          expect(await at(['mcpServers', 'x', 'env', 'TOKEN']), '***');
          expect(
            identical(
              await at(['mcpServers', 'x', 'env', 'TOKEN', 'more']),
              absent,
            ),
            isTrue,
          );
          expect(await at(['agents', 'a', 'command']), '***');
          // An agent merely named url is masked whole.
          expect(await at(['agents', 'url']), {
            'model': '***',
            'mcpServers': '***',
          });
        },
      );
    });

    test("a read keeps the settings' order, the servers last, whatever "
        "the file's", () async {
      await _placed(
        (
          user:
              '{"mcpServers":{"x":{"command":"c"}},"theme":"dark","agent":"a"}',
          project: null,
        ),
        (where, _, _) async {
          final answer = (await _read(where)).answer;
          expect((answer.user as Map).keys, ['agent', 'theme', 'mcpServers']);
          expect((answer.effective as Map).keys, [
            'agent',
            'theme',
            'mcpServers',
          ]);
        },
      );
    });

    test('a boolean agents.<name>.mcpServers stays', () async {
      await _placed(
        (
          user: {
            'agents': {
              'a': {'mcpServers': false, 'model': 'm'},
            },
          },
          project: null,
        ),
        (where, _, _) async {
          expect((await _read(where)).answer.user, {
            'agents': {
              'a': {'model': 'm', 'mcpServers': false},
            },
          });
        },
      );
    });

    test(
      'a project key only the user may set is counted, naming nothing',
      () async {
        await _placed(
          (user: null, project: {'theme': 'dark', 'mouse': false}),
          (where, _, _) async {
            final answer = (await _read(where)).answer;
            expect(answer.project, <String, Object?>{});
            expect(answer.problems, [
              (
                file: _projectShown,
                message: "2 keys only the user's file may set; ignored",
              ),
            ]);
          },
        );
      },
    );

    test('one key ignored, and a path read carries the whole list', () async {
      await _placed((user: {'nope': 1, 'agent': 'a'}, project: null), (
        where,
        _,
        _,
      ) async {
        final answer = (await _read(where, ['agent'])).answer;
        expect(answer.user, 'a');
        expect(answer.problems.map((each) => each.message), ['1 key ignored']);
      });
    });

    test('absent, not an object, unreadable, no home and a name no key '
        'has', () async {
      await _placed((user: null, project: null), (where, _, _) async {
        final read = await _read(where);
        expect((read.answer.user, read.answer.project), (null, null));
        expect(read.answer.effective, <String, Object?>{});
        expect(read.answer.problems, isEmpty);
        expect(read.user, endsWith(' · not there'));
      });
      await _placed((user: null, project: '["x"]'), (where, _, _) async {
        final read = await _read(where);
        expect(read.answer.project, isNull);
        expect(
          read.answer.problems.first.message,
          'not a JSON object; ignored',
        );
        expect(read.project, endsWith(' · not a JSON object'));
      });
      await _placed((user: null, project: null), (where, file, _) async {
        Directory(file).createSync();
        final read = await _read(where);
        expect(read.answer.user, isNull);
        expect(read.answer.problems.first.message, 'cannot be read; ignored');
        expect(_everything(read.answer), isNot(contains(where.home!)));
        expect(read.user, endsWith(' · cannot be read'));
      });
      await _placed((user: null, project: {'agent': 'a'}), (where, _, _) async {
        final read = await _read(
          SettingsWhere(configHome: null, cwd: where.cwd, home: null),
        );
        expect(read.answer.user, isNull);
        expect(read.answer.effective, {'agent': 'a'});
        expect(read.user, 'no home directory');
      });
      await _placed((user: null, project: null), (where, _, _) async {
        expect(
          (await readSettingsTool(where, ['__proto__']) as SettingsToolRefused)
              .error,
          'No setting __proto__',
        );
      });
    });

    test('with no home, paths show as they are, found through '
        'XDG_CONFIG_HOME', () async {
      for (final home in [null, '']) {
        await _placed((user: {'theme': 'dark'}, project: {'agent': 'a'}), (
          where,
          file,
          _,
        ) async {
          final homeless = SettingsWhere(
            configHome: where.configHome,
            cwd: where.cwd,
            home: home,
          );
          expect(shownHome(homeless), isNull);
          final read = await _read(homeless);
          expect(read.user, '$file · 1 key');
          expect(read.project, '$_projectShown · 1 key');
          final planned = await _planned(homeless, ['theme'], _set('light'));
          expect(planned.file, file);
          expect(
            _everything(planned) + _everything(read.answer, read),
            isNot(contains('~')),
          );
        });
      }
      expect(
        saveFailure('/x/s.json', const SettingRefused('at /x/s.json'), null),
        '/x/s.json was not saved: at /x/s.json',
      );
    });

    test('the project shadows from its checked layer alone', () async {
      await _placed((user: {'agent': 'claude'}, project: {'agent': 'codex'}), (
        where,
        _,
        _,
      ) async {
        expect(
          (await _planned(
            where,
            ['agent'],
            _set('fake'),
            ['fake', ..._known],
          )).shadowedBy,
          _projectShown,
        );
      });
      await _placed((user: null, project: '{"agent":7,"theme":"dark"}'), (
        where,
        _,
        _,
      ) async {
        for (final path in [
          ['agent'],
          ['theme'],
        ]) {
          final planned = await _planned(
            where,
            path,
            _set(path.first == 'agent' ? 'codex' : 'light'),
          );
          expect(planned.shadowedBy, isNull);
        }
      });
    });
  });

  group('checked plans and linked reads', () {
    test('a malformed leaf is absent from a set plan and unchanged on '
        'removal', () async {
      final text = jsonEncode({
        'agents': {
          'claude': {
            'model': {
              'env': {
                'LIST': [
                  'env-canary',
                  {'nested': 'env-canary'},
                ],
              },
              'command': ['command-canary'],
              'mcpServers': {'token': 'mcp-canary'},
              'keep': 3,
            },
          },
        },
      });
      await _placed((user: text, project: null), (where, user, _) async {
        for (final change in [_set('new-model'), _remove]) {
          final result = await _planned(where, [
            'agents',
            'claude',
            'model',
          ], change);
          expect(identical(result.before, absent), isTrue);
          if (change is RemoveSetting) {
            expect(result.unchanged, isTrue);
          } else {
            expect(result.after, 'new-model');
          }
          expect(_everything(result), isNot(contains('canary')));
          expect(File(user).readAsStringSync(), text);
        }
      });
    });

    test('linked unknown fields and server tokens stay out of every '
        'answer', () async {
      final text = jsonEncode({
        'UNKNOWN_KEY_CANARY': 'UNKNOWN_VALUE_CANARY',
        'agents': {
          'worker': {'model': 'kept', 'FIELD_CANARY': 'AGENT_CANARY'},
        },
        'teamSelection': {'intent': 'economy', 'FIELD_CANARY': 'TEAM_CANARY'},
        'mcpServers': {
          'linear': {
            'command': 'COMMAND_CANARY',
            'args': ['ARGS_CANARY'],
            'env': {'TOKEN': 'ENV_CANARY'},
            'token': 'TOKEN_CANARY',
            'Env': {'TOKEN': 'WRONG_CASE_CANARY'},
          },
          'invalid': {'token': 'INVALID_SERVER_CANARY'},
        },
      });
      await _placed((user: {'agent': 'claude'}, project: null), (
        where,
        user,
        root,
      ) async {
        final target = p.join(where.home!, 'checked-target.json');
        File(target).writeAsStringSync(text);
        Link(p.join(where.cwd, '.chord', 'settings.json')).createSync(target);
        for (final path in [
          <String>[],
          ['mcpServers'],
          ['mcpServers', 'linear', 'token'],
          ['mcpServers', 'linear', 'env', 'TOKEN'],
          ['agents', 'worker'],
        ]) {
          final read = await _read(where, path);
          expect(_everything(read.answer, read), isNot(contains('CANARY')));
        }
        expect(File(target).readAsStringSync(), text);
        expect(File(user).readAsStringSync(), '{"agent":"claude"}');
      });
    });

    test('two broken layers expose only fixed parse words, including a '
        'linked project', () async {
      await _placed((user: '{"theme":USER_BROKEN_CANARY}', project: null), (
        where,
        _,
        _,
      ) async {
        final target = p.join(where.home!, 'broken-target.json');
        File(target).writeAsStringSync('{"KEY_CANARY":PROJECT_BROKEN_CANARY}');
        Link(p.join(where.cwd, '.chord', 'settings.json')).createSync(target);
        for (final path in [
          <String>[],
          ['theme'],
        ]) {
          final read = await _read(where, path);
          expect(read.answer.problems.map((each) => each.message), [
            'not valid JSON; ignored',
            'not valid JSON; ignored',
          ]);
          expect(_everything(read.answer, read), isNot(contains('CANARY')));
        }
      });
    });

    test('completed reads follow a link, then observe a regular file and '
        'dangling replacement', () async {
      await _placed((user: {'agent': 'claude'}, project: null), (
        where,
        _,
        _,
      ) async {
        final target = p.join(where.home!, 'target.json');
        final project = p.join(where.cwd, '.chord', 'settings.json');
        File(
          target,
        ).writeAsStringSync('{"agent":"codex","linked-canary":1,"theme":3}');
        Link(project).createSync(target);
        final linked = await _read(where, ['agent']);
        expect(
          (linked.answer.project, linked.answer.effective),
          ('codex', 'codex'),
        );
        expect(
          _everything(linked.answer, linked),
          isNot(contains('linked-canary')),
        );
        expect(linked.answer.problems, hasLength(1));
        Link(project).deleteSync();
        File(project).writeAsStringSync('{"agent":"claude"}');
        final regular = (await _read(where, ['agent'])).answer;
        expect(
          (regular.project, regular.effective, regular.problems.length),
          ('claude', 'claude', 0),
        );
        File(project).deleteSync();
        Link(project).createSync(p.join(where.home!, 'absent-target'));
        final dangling = await _read(where, ['agent']);
        expect(identical(dangling.answer.project, absent), isTrue);
        expect(dangling.answer.effective, 'claude');
        expect(dangling.project, endsWith(' · not there'));
        expect(dangling.answer.problems, isEmpty);
      });
    });
  });

  group('CTUI-79 tester: nested checked views', () {
    test(
      'rejected constraint payloads stay out of linked reads and plans',
      () async {
        final text = jsonEncode({
          'teamSelection': {
            'constraints': {
              'agents': [
                {'token': 'nested-canary-secret'},
              ],
              'models': {
                'codex': [
                  {'env': 'nested-canary-secret'},
                ],
              },
            },
          },
        });
        await _placed((user: text, project: null), (where, userFile, _) async {
          final read = await _read(where);
          final nested = await _read(where, ['teamSelection', 'constraints']);
          final plan = await _planned(where, ['agent'], _set('codex'));
          for (final answer in [
            _everything(read.answer, read),
            _everything(nested.answer, nested),
            _everything(plan),
          ]) {
            expect(answer, isNot(contains('nested-canary-secret')));
            expect(answer, isNot(contains('"token"')));
          }
          expect(nested.answer.user, {
            'agents': <String>[],
            'models': {'codex': <String>[]},
          });
          expect(File(userFile).readAsStringSync(), text);
        });
      },
    );

    test(
      'an empty project constraint reads as empty and rejects tool writes',
      () async {
        await _placed(
          (
            user: {
              'teamSelection': {
                'constraints': {
                  'agents': ['claude'],
                },
              },
            },
            project: {
              'teamSelection': {
                'constraints': {'agents': <String>[]},
              },
            },
          ),
          (where, userFile, _) async {
            final before = File(userFile).readAsStringSync();
            final path = ['teamSelection', 'constraints', 'agents'];
            final read = await _read(where, path);
            expect(read.answer.user, ['claude']);
            expect(read.answer.project, isEmpty);
            expect(read.answer.effective, isEmpty);
            final plan = await plannedSetting(
              where,
              path,
              _set(['codex']),
              _known,
            );
            expect(
              (plan as SettingsToolRefused).error,
              'chord does not write teamSelection.constraints.agents; '
              'edit the settings file by hand',
            );
            expect(File(userFile).readAsStringSync(), before);
          },
        );
      },
    );
  });
}
