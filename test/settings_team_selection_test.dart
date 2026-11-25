// `teamSelection` read and merged as the original's settings.ts does with
// budgets.ts TeamSelection: a strict object whose bad keys cost themselves,
// whose constraint lists lose only their bad items, and whose layers merge
// field by field and runtime by runtime. As the original's
// tests/settings_test.ts 'resource selection preferences', 'tester:
// resource preference layering' and the loading halves of 'selected
// policy admission diagnostics' have it; the selection policy itself is
// the teams' own.
import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ParsedSettings _parsed(Object? teamSelection) =>
    parseSettings('f', jsonEncode({'teamSelection': teamSelection}));

Map<String, Object?>? _merged(List<Map<String, Object?>?> layers) =>
    mergeSettings([
      for (final layer in layers) Settings(teamSelection: layer),
    ]).teamSelection;

void main() {
  test('strict nested fields report problems and retain explicit empty '
      'constraints', () {
    final parsed = _parsed({
      'intent': 'balanced',
      'constraints': {
        'agents': <String>[],
        'models': {'codex': <String>[]},
      },
      'unknown': true,
    });
    expect(parsed.problems.map((each) => each.message), [
      'unknown key "teamSelection.unknown", ignored',
    ]);
    expect(parsed.settings.teamSelection, {
      'intent': 'balanced',
      'constraints': {
        'agents': <String>[],
        'models': {'codex': <String>[]},
      },
    });
  });

  test('each bad key costs itself alone, in the words of its check', () {
    final parsed = _parsed({
      'intent': 'anything',
      'prefer': {'agent': '', 'model': 3, 'other': 1},
      'constraints': {'agents': null, 'modes': 'x'},
    });
    expect(parsed.problems.map((each) => each.message), [
      '"teamSelection.intent": invalid option: expected one of '
          '"balanced"|"prefer"|"economy"|"fixed", ignored',
      '"teamSelection.prefer.agent": too small: expected string to have >=1 '
          'characters, ignored',
      '"teamSelection.prefer.model": invalid input: expected string, received '
          'number, ignored',
      'unknown key "teamSelection.prefer.other", ignored',
      '"teamSelection.constraints.agents": invalid input: expected array, '
          'received null, ignored',
      '"teamSelection.constraints.modes": invalid input: expected record, '
          'received string, ignored',
    ]);
    expect(
      parsed.problems.map((each) => (each.kind, each.key)),
      everyElement(
        isA<(SettingsProblemKind?, List<String>?)>().having(
          (each) => each.$1,
          'kind',
          SettingsProblemKind.validation,
        ),
      ),
    );
    expect(parsed.problems[4].key, ['teamSelection', 'constraints', 'agents']);
    expect(parsed.settings.teamSelection, {
      'prefer': <String, Object?>{},
      'constraints': <String, Object?>{},
    });
  });

  test('a null model is a value, kept; a null agent is not', () {
    final parsed = _parsed({
      'prefer': {'agent': null, 'model': null},
    });
    expect(parsed.problems.single.key, ['teamSelection', 'prefer', 'agent']);
    expect(parsed.settings.teamSelection, {
      'prefer': {'model': null},
    });
  });

  test("a bad constraint item leaves its list, and the list's last says "
      'what it now allows', () {
    final long = 'x' * 129;
    final parsed = _parsed({
      'constraints': {
        'agents': ['codex', 7, ''],
        'models': {
          'codex': [null],
        },
        'modes': {
          '': ['plan'],
          'claude': [long],
        },
      },
    });
    expect(parsed.problems.map((each) => each.message), [
      '"teamSelection.constraints.agents": item 2 (7), invalid input: '
          'expected string, received number, left out',
      '"teamSelection.constraints.agents": item 3 (""), too small: expected '
          'string to have >=1 characters, left out',
      '"teamSelection.constraints.models.codex": item 1 (null), invalid '
          'input: expected string, received null, left out',
      '"teamSelection.constraints.models.codex": no item left; the list now '
          'allows no model for codex',
      '"teamSelection.constraints.modes.": too small: expected string to have '
          '>=1 characters, ignored',
      '"teamSelection.constraints.modes.claude": item 1 ("${'x' * 39}…), '
          'too big: expected string to have <=128 characters, left out',
      '"teamSelection.constraints.modes.claude": no item left; the list now '
          'allows no mode for claude',
    ]);
    expect(parsed.problems.map((each) => each.leftOut), [
      SettingsLeftOut.item,
      SettingsLeftOut.item,
      SettingsLeftOut.item,
      SettingsLeftOut.list,
      null,
      SettingsLeftOut.item,
      SettingsLeftOut.list,
    ]);
    expect(parsed.settings.teamSelection, {
      'constraints': {
        'agents': ['codex'],
        'models': {'codex': <String>[]},
        'modes': {'claude': <String>[]},
      },
    });
  });

  test('a list of more than 128 names costs the list', () {
    final parsed = _parsed({
      'constraints': {'agents': List.filled(129, 'a')},
    });
    expect(
      parsed.problems.single.message,
      '"teamSelection.constraints.agents": too big: expected array to have '
      '<=128 items, ignored',
    );
  });

  test('project precedence replaces lists while merging preference fields '
      'and runtime maps', () {
    expect(
      _merged([
        {
          'intent': 'prefer',
          'prefer': {'agent': 'codex', 'model': 'large'},
          'constraints': {
            'agents': ['codex'],
            'models': {
              'codex': ['large'],
              'claude': ['small'],
            },
            'modes': {
              'codex': ['auto'],
            },
          },
        },
        {
          'intent': 'balanced',
          'prefer': {'model': null},
          'constraints': {
            'agents': <String>[],
            'models': {'codex': <String>[]},
            'modes': {
              'claude': ['plan'],
            },
          },
        },
      ]),
      {
        'intent': 'balanced',
        'prefer': {'agent': 'codex', 'model': null},
        'constraints': {
          'agents': <String>[],
          'models': {
            'codex': <String>[],
            'claude': ['small'],
          },
          'modes': {
            'codex': ['auto'],
            'claude': ['plan'],
          },
        },
      },
    );
  });

  test('an empty later map preserves denied runtime lists and an explicit '
      'model reset', () {
    final base = <String, Object?>{
      'intent': 'prefer',
      'prefer': {'agent': 'codex', 'model': 'large'},
      'constraints': {
        'agents': ['codex'],
        'models': {'codex': <String>[]},
        'modes': {'codex': <String>[]},
      },
    };
    expect(
      _merged([
        base,
        {
          'prefer': {'model': null},
        },
        {
          'constraints': {
            'models': <String, Object?>{},
            'modes': <String, Object?>{},
          },
        },
      ]),
      {
        ...base,
        'prefer': {'agent': 'codex', 'model': null},
      },
    );
    expect((base['prefer']! as Map)['model'], 'large');
  });

  group('loaded', () {
    late Directory root;
    late String config, cwd, home;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-team-selection-');
      home = p.join(root.path, 'home');
      config = p.join(home, '.config');
      cwd = p.join(root.path, 'work');
    });
    tearDown(() => root.deleteSync(recursive: true));

    void place({Object? user, Object? project}) {
      for (final (file, value) in [
        (p.join(config, 'chord', 'settings.json'), user),
        (p.join(cwd, '.chord', 'settings.json'), project),
      ]) {
        if (value == null) continue;
        File(file)
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(value));
      }
    }

    Future<LoadedSettings> load() =>
        loadSettings(configHome: config, cwd: cwd, home: home);

    test('an invalid nested policy keeps its structured path and costs '
        'nothing else', () async {
      place(
        project: {
          'agent': 'fake',
          'teamSelection': {
            'constraints': {'agents': null},
          },
        },
      );
      final loaded = await load();
      expect(loaded.settings.agent, 'fake');
      expect(loaded.problems.first.kind, SettingsProblemKind.validation);
      expect(loaded.problems.first.key, [
        'teamSelection',
        'constraints',
        'agents',
      ]);
    });

    test('a valid policy is no problem beside unrelated ones', () async {
      place(
        user: {
          'mouse': false,
          'theme': 7,
          'teamSelection': {
            'constraints': {
              'modes': {
                'fake': ['plan'],
              },
            },
          },
        },
        project: {'mouse': true},
      );
      final loaded = await load();
      expect(loaded.problems.map((each) => (each.kind, each.key?.join('.'))), [
        (SettingsProblemKind.validation, 'theme'),
        (SettingsProblemKind.scope, 'mouse'),
      ]);
      expect(loaded.settings.teamSelection, {
        'constraints': {
          'modes': {
            'fake': ['plan'],
          },
        },
      });
    });

    test(
      'the files merge as layers, an explicit empty list included',
      () async {
        place(
          user: {
            'teamSelection': {
              'intent': 'prefer',
              'prefer': {'agent': 'codex', 'model': 'large'},
              'constraints': {
                'agents': ['codex', 'claude'],
                'modes': {
                  'codex': ['auto'],
                  'claude': ['plan'],
                },
              },
            },
          },
          project: {
            'teamSelection': {
              'prefer': {'model': null},
              'constraints': {
                'agents': ['claude'],
              },
            },
          },
        );
        expect((await load()).settings.teamSelection, {
          'intent': 'prefer',
          'prefer': {'agent': 'codex', 'model': null},
          'constraints': {
            'agents': ['claude'],
            'modes': {
              'codex': ['auto'],
              'claude': ['plan'],
            },
          },
        });
        place(
          project: {
            'teamSelection': {
              'constraints': {
                'agents': <String>[],
                'modes': {'claude': <String>[]},
              },
            },
          },
        );
        expect((await load()).settings.teamSelection, {
          'intent': 'prefer',
          'prefer': {'agent': 'codex', 'model': 'large'},
          'constraints': {
            'agents': <String>[],
            'modes': {
              'codex': ['auto'],
              'claude': <String>[],
            },
          },
        });
      },
    );

    test("a valid project override wins over the user's invalid one", () async {
      place(
        user: {
          'teamSelection': {
            'constraints': {
              'models': {'codex': null},
            },
          },
        },
        project: {
          'teamSelection': {
            'constraints': {
              'models': {
                'codex': ['supported'],
              },
            },
          },
        },
      );
      final loaded = await load();
      expect(loaded.settings.teamSelection, {
        'constraints': {
          'models': {
            'codex': ['supported'],
          },
        },
      });
      expect(loaded.problems.single.key, [
        'teamSelection',
        'constraints',
        'models',
        'codex',
      ]);
    });
  });

  group('CTUI-79 tester: nested settings boundaries', () {
    test('reference bounds count UTF-16 units as the original schema does', () {
      final accepted = _parsed({
        'prefer': {'agent': '🙂' * 64, 'model': '界' * 128},
        'constraints': {'agents': List.filled(128, 'x')},
      });
      expect(accepted.problems, isEmpty);
      expect(
        (accepted.settings.teamSelection!['prefer'] as Map)['agent'],
        '🙂' * 64,
      );
      final rejected = _parsed({
        'prefer': {'agent': '🙂' * 65, 'model': '界' * 129},
      });
      expect(rejected.problems, hasLength(2));
      expect(rejected.settings.teamSelection, {'prefer': <String, Object?>{}});
    });

    test(
      'all rejected items keep an explicit deny list and literal runtime path',
      () {
        final parsed = _parsed({
          'constraints': {
            'agents': [null, 3, ''],
            'models': {
              'runtime.with.dot': [false],
            },
          },
        });
        expect(parsed.settings.teamSelection, {
          'constraints': {
            'agents': <String>[],
            'models': {'runtime.with.dot': <String>[]},
          },
        });
        expect(
          parsed.problems.where((p) => p.leftOut == SettingsLeftOut.list),
          hasLength(2),
        );
        expect(
          parsed.problems
              .where((p) => p.key?.last == 'runtime.with.dot')
              .map((p) => p.key),
          everyElement([
            'teamSelection',
            'constraints',
            'models',
            'runtime.with.dot',
          ]),
        );
      },
    );

    test(
      'invalid override preserves prior values while null and empty reset them',
      () {
        final user = _parsed({
          'prefer': {'agent': 'fake', 'model': 'large'},
          'constraints': {
            'models': {
              'fake': ['large'],
            },
          },
        });
        final invalid = _parsed({
          'prefer': {'model': 7},
          'constraints': {
            'models': {'fake': null},
          },
        });
        final merged = mergeSettings([user.settings, invalid.settings]);
        expect(merged.teamSelection, user.settings.teamSelection);
        final explicit = _parsed({
          'prefer': {'model': null},
          'constraints': {
            'models': {'fake': <String>[]},
          },
        });
        expect(mergeSettings([merged, explicit.settings]).teamSelection, {
          'prefer': {'agent': 'fake', 'model': null},
          'constraints': {
            'models': {'fake': <String>[]},
          },
        });
        expect(
          (user.settings.teamSelection!['prefer'] as Map)['model'],
          'large',
        );
      },
    );
  });
}
