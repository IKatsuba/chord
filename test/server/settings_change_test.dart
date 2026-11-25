// chord's `settings` tool served: a read answered from the checked files,
// a change drawn as it waits, asked in chord's box whatever the mode, and
// written by chord on a yes, one change waiting at a time; refused from a
// fork. As the original's tests/server/tools_test.ts 'the settings tool
// writes'.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/rpc.dart' show OnCancel;
import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/server/tools.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/settings.dart';
import 'package:chord/settings_tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'fake_window.dart';
import 'mcp_wire.dart';

/// A window whose user's file is under a temporary home, holding [text]
/// when given.
({FakeWindow window, String file, Caller caller}) _placed({String? text}) {
  final root = Directory.systemTemp.createTempSync('chord-settings-change-');
  addTearDown(() => root.deleteSync(recursive: true));
  final home = p.join(root.path, 'home');
  final file = p.join(home, '.config', 'chord', 'settings.json');
  if (text != null) {
    File(file)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  final window = FakeWindow()
    ..where = SettingsWhere(
      configHome: p.join(home, '.config'),
      cwd: p.join(root.path, 'work'),
      home: home,
    );
  return (
    window: window,
    file: file,
    caller: Caller(role: Role.person, key: 0, window: window),
  );
}

String? _held(String file) =>
    File(file).existsSync() ? File(file).readAsStringSync() : null;

final _shownFile = '~${p.join('/', '.config', 'chord', 'settings.json')}';

/// A `set` or `remove` as the tool asks it, its drawn waits in [shown].
Future<Object> _change(
  Caller caller,
  List<String> path,
  SettingChange change, [
  List<SettingsChanged>? shown,
]) => changeSetting(
  caller,
  path,
  change,
  CancellationToken(),
  (one) => shown?.add(one),
  'the-call',
);

ToolSpec _tool(Caller caller) =>
    toolsOf(caller).singleWhere((tool) => tool.tool == ChordTool.settings);

void main() {
  test('main is offered settings after open_agent; a child is not', () {
    expect(
      toolNames(Role.person).map((tool) => tool.wire),
      containsAllInOrder(['open_agent', 'settings', 'send_message']),
    );
    expect(toolNames(Role.child), isNot(contains(ChordTool.settings)));
    final window = FakeWindow();
    for (final caller in [
      Caller(role: Role.child, key: 0, window: window, agent: 'a1'),
      Caller(role: Role.child, key: 0, window: window, task: 't1'),
    ]) {
      expect(
        toolsOf(caller).map((tool) => tool.tool),
        isNot(contains(ChordTool.settings)),
      );
    }
  });

  test('a fork is refused in the words its other refusals use, asking and '
      'reading nothing', () async {
    final placed = _placed(text: '{"theme":"dark"}');
    final fork = Caller(
      role: Role.person,
      key: 1,
      window: placed.window,
      fork: true,
    );
    for (final input in [
      {'action': 'read'},
      {
        'action': 'set',
        'path': ['theme'],
        'value': 'light',
      },
    ]) {
      final result = await _tool(fork).call(input);
      expect((result.text, result.isError), (forkRefused.error, true));
    }
    expect(placed.window.questions, isEmpty);
    expect(_held(placed.file), '{"theme":"dark"}');
  });

  test('a yes draws the change, asks the box, then chord writes it', () async {
    final placed = _placed();
    placed.window.picks = (_, _, _) async => 'yes';
    final shown = <SettingsChanged>[];
    final answer =
        await _change(
              placed.caller,
              ['theme'],
              const SetSetting('light'),
              shown,
            )
            as SettingsChanged;
    expect(
      [for (final one in shown) one.toJson()],
      [
        {
          'path': ['theme'],
          'after': 'light',
          'file': _shownFile,
          'takesEffect': 'now',
        },
      ],
    );
    final (title, detail, options, save) = placed.window.questions.single;
    expect(
      (title, detail),
      ('Settings(theme)', 'In $_shownFile: not set becomes "light".'),
    );
    expect(
      [for (final o in options) (o.optionId, o.name, o.kind)],
      [
        ('yes', 'Yes, in $_shownFile', 'allow_once'),
        ('no', 'No, tell fake what to change', 'reject_once'),
      ],
    );
    expect(
      (save.question, save.files.length, save.escape, save.asked),
      ('Set theme?', 0, 'tell fake what to change', 'the-call'),
    );
    expect(answer.toJson(), {...shown.single.toJson(), 'saved': true});
    expect(jsonDecode(_held(placed.file)!), {'theme': 'light'});
  });

  test("the box names a change and a remove by the row's note", () async {
    Future<String> question(SettingChange change) async {
      final placed = _placed(text: '{"theme":"dark"}');
      placed.window.picks = (_, _, _) async => 'no';
      await _change(placed.caller, ['theme'], change);
      return placed.window.questions.single.$4.question;
    }

    expect(await question(const SetSetting('light')), 'Change theme?');
    expect(await question(const RemoveSetting()), 'Remove theme?');
  });

  test('a no writes nothing and says saved false', () async {
    const text = '{"theme":"dark"}';
    final placed = _placed(text: text);
    placed.window.picks = (_, _, _) async => 'no';
    final shown = <SettingsChanged>[];
    final answer =
        await _change(
              placed.caller,
              ['theme'],
              const SetSetting('light'),
              shown,
            )
            as SettingsChanged;
    expect(answer.toJson(), {...shown.single.toJson(), 'saved': false});
    expect(_held(placed.file), text);
    expect(placed.window.saved, isEmpty);
  });

  test('the window hears of a write once it is saved, and only then', () async {
    Future<int> heard(
      String? pick, {
      String? text,
      void Function(String file)? mid,
    }) async {
      final placed = _placed(text: text);
      placed.window.picks = (_, _, _) async {
        mid?.call(placed.file);
        return pick;
      };
      await _change(placed.caller, ['theme'], const SetSetting('light'));
      return placed.window.saved.length;
    }

    expect(await heard('yes'), 1);
    expect(await heard(null), 0);
    expect(
      await heard(
        'yes',
        text: '{"theme":"dark"}',
        mid: (file) => File(file).writeAsStringSync('{ broken'),
      ),
      0,
    );
    expect(await heard('yes', text: '{"theme":"light"}'), 0);
  });

  test('a withdrawn box writes nothing, as a refusal', () async {
    final placed = _placed();
    final answer = await _change(placed.caller, [
      'theme',
    ], const SetSetting('light'));
    expect(
      (answer as Refused).error,
      'The person was not asked to the end; nothing was saved',
    );
    expect(_held(placed.file), isNull);
  });

  test('nothing to do asks nothing and writes nothing', () async {
    const text = '{ "theme":   "dark" }';
    final placed = _placed(text: text);
    placed.window.picks = (_, _, _) async => 'yes';
    final shown = <SettingsChanged>[];
    final same =
        await _change(placed.caller, ['theme'], const SetSetting('dark'), shown)
            as SettingsChanged;
    expect((same.saved, same.unchanged), (false, true));
    final absentKey =
        await _change(placed.caller, ['mouse'], const RemoveSetting(), shown)
            as SettingsChanged;
    expect((absentKey.saved, absentKey.unchanged), (false, true));
    expect(placed.window.questions, isEmpty);
    expect(shown, isEmpty);
    expect(_held(placed.file), text);
  });

  test('a refusal asks nothing and writes nothing', () async {
    const text = '{"agents":{"claude":{"command":"x"}}}';
    for (final (path, change, error) in [
      (['nope'], const SetSetting(1), 'No setting nope'),
      (
        ['agents', 'claude', 'command'],
        const SetSetting('y'),
        'chord does not write agents.claude.command; edit the settings file '
            'by hand',
      ),
    ]) {
      final placed = _placed(text: text);
      placed.window.picks = (_, _, _) async => 'yes';
      final refused = await _change(placed.caller, path, change);
      expect((refused as Refused).error, error);
      expect(placed.window.questions, isEmpty);
      expect(_held(placed.file), text);
    }
  });

  group('one change waits at a time', () {
    test('of two parallel changes one waits and the other is refused, asking '
        'and writing nothing', () async {
      final placed = _placed(text: '{"theme":"dark"}');
      final answer = Completer<String?>();
      placed.window.picks = (_, _, _) => answer.future;
      final both = [
        _change(placed.caller, ['theme'], const SetSetting('light')),
        _change(placed.caller, ['mouse'], const SetSetting(false)),
      ];
      final first = await Future.any(both);
      expect((first as Refused).error, settingsBoxHeld);
      expect(placed.window.questions, hasLength(1));
      answer.complete('yes');
      final answers = await Future.wait(both);
      final saved = answers.indexWhere(
        (one) => one is SettingsChanged && one.saved == true,
      );
      expect((answers[1 - saved] as Refused).error, settingsBoxHeld);
      expect(
        jsonDecode(_held(placed.file)!),
        saved == 0 ? {'theme': 'light'} : {'theme': 'dark', 'mouse': false},
      );
    });

    test('a change after the first was answered, withdrawn or failed is '
        'asked', () async {
      final placed = _placed(text: '{"theme":"dark"}');
      for (final pick in ['no', null]) {
        placed.window.picks = (_, _, _) async => pick;
        await _change(placed.caller, ['theme'], const SetSetting('light'));
      }
      placed.window.picks = (_, _, _) async {
        File(placed.file).writeAsStringSync('{ broken');
        return 'yes';
      };
      final failing = await _change(placed.caller, [
        'theme',
      ], const SetSetting('light'));
      expect((failing as Refused).error, contains('was not saved'));
      File(placed.file).writeAsStringSync('{}');
      placed.window.picks = (_, _, _) async => 'no';
      final next =
          await _change(placed.caller, ['mouse'], const SetSetting(true))
              as SettingsChanged;
      expect(next.saved, isFalse);
      expect(placed.window.questions, hasLength(4));
    });
  });

  group('served', () {
    test('a read is served with what its row says of each file, and answers '
        'the checked settings', () async {
      final placed = _placed(text: '{"theme":"dark","nope":1}');
      final result = await _tool(placed.caller).call({'action': 'read'});
      expect(result.isError, isFalse);
      final answer = jsonDecode(result.text) as Map<String, Object?>;
      expect(answer['user'], {'theme': 'dark'});
      expect(answer['problems'], [
        {'file': _shownFile, 'message': '1 key ignored'},
      ]);
      final served = placed.window.calls.single;
      expect(served.tool, ChordTool.settings);
      expect(served.answer, answer);
      expect(served.settingsFiles?.user, '$_shownFile · 1 key');
      expect(served.settingsFiles?.project, endsWith(' · not there'));
    });

    test('a change is served pending as the box waits, then answered under '
        'the same asked', () async {
      final placed = _placed();
      final heard = <ChordCall>[];
      placed.window.picks = (_, _, _) async {
        heard.addAll(placed.window.calls);
        return 'yes';
      };
      final input = {
        'action': 'set',
        'path': ['theme'],
        'value': 'light',
      };
      final result = await _tool(placed.caller).call(input);
      expect(result.isError, isFalse);
      expect(jsonDecode(result.text), {
        'path': ['theme'],
        'after': 'light',
        'file': _shownFile,
        'saved': true,
        'takesEffect': 'now',
      });
      final pending = heard.single;
      final answered = placed.window.calls.last;
      expect(
        (pending.pending, answered.pending, pending.asked),
        (true, false, answered.asked),
      );
      expect(Uuid.isValidUUID(fromString: pending.asked!), isTrue);
      expect(placed.window.calls, hasLength(2));
    });

    test('a set with no value is refused as left out; a refusal is the '
        "call's failure", () async {
      final placed = _placed();
      final left = await _tool(placed.caller).call({
        'action': 'set',
        'path': ['theme'],
      });
      expect(left.isError, isTrue);
      expect(left.text, startsWith('theme cannot be left out: '));
      final read = await _tool(placed.caller).call({
        'action': 'read',
        'path': ['__proto__'],
      });
      expect((read.text, read.isError), ('No setting __proto__', true));
      expect(placed.window.calls.last.error, 'No setting __proto__');
    });

    test('an MCP request its client cancels withdraws the box, saves '
        'nothing and gives the box back', () async {
      final server = await serveChord();
      addTearDown(server.close);
      final placed = _placed(text: '{"theme":"dark"}');
      final signalled = Completer<void>();
      placed.window.picks = (_, _, signal) {
        final picked = Completer<String?>();
        OnCancel((_) {
          picked.complete(null);
          signalled.complete();
        }).listen(signal);
        return picked.future;
      };
      final token = server.admit(placed.caller).token;
      final opened = await open(server.url, token);
      final request = rpc('tools/call', {
        'name': 'settings',
        'arguments': {
          'action': 'set',
          'path': ['theme'],
          'value': 'light',
        },
      });
      // A cancelled request is answered by nobody.
      post(server.url, request, token: token, session: opened.session).ignore();
      while (placed.window.questions.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await post(
        server.url,
        {
          'jsonrpc': '2.0',
          'method': 'notifications/cancelled',
          'params': {'requestId': request['id'], 'reason': 'gave up'},
        },
        token: token,
        session: opened.session,
      );
      await signalled.future.timeout(const Duration(seconds: 5));
      while (placed.window.calls.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        placed.window.calls.last.error,
        'The person was not asked to the end; nothing was saved',
      );
      expect(_held(placed.file), '{"theme":"dark"}');
      expect(placed.window.saved, isEmpty);
      // The box is free for the next change.
      placed.window.picks = (_, _, _) async => 'no';
      final next =
          await _change(placed.caller, ['theme'], const SetSetting('light'))
              as SettingsChanged;
      expect(next.saved, isFalse);
      expect(placed.window.questions, hasLength(2));
    });
  });
}
