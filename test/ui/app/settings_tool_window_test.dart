// The settings tool in the window, on the original's fake and chord's own
// server: its rows under the call, a read of every key folded until ctrl+o,
// chord's save box asking a change, and what a saved setting changes at
// once, as the original's Tool_test.tsx 'the settings tool on the
// transcript' and setting_picked_up_test.tsx have them.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/setting_picked_up.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch;

/// Main on the fake in the window, with chord's server and the host as the
/// launch wires them, the user's file holding [user] and the project's
/// [project] when given.
Future<({StartConnection connection, String file})> _window(
  WidgetTester t,
  Size size, {
  required String user,
  String? project,
}) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final home = runtimes.home.path;
  final configHome = p.join(home, 'settings-home', '.config');
  final file = p.join(configHome, 'chord', 'settings.json');
  File(file)
    ..createSync(recursive: true)
    ..writeAsStringSync(user);
  if (project != null) {
    File(p.join(home, '.chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(project);
  }
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: home,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => fold.dispatch(AgentOpened(key)),
    closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    server: server,
    cwd: home,
    configHome: configHome,
    home: p.join(home, 'settings-home'),
    settingSaved: (path, change) {
      if (settingPickedUp(path, change) case final picked?) {
        connection.settingPickedUp?.call(picked);
      }
    },
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return (connection: connection, file: file);
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 750 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

Future<void> _shows(WidgetTester t, String text) =>
    _until(t, () => t.screen.text.contains(text));

Future<void> _send(WidgetTester t, String prompt) async {
  await t.type(prompt);
  await t.press('enter');
}

const _secret = 'secret123';
final _settings = jsonEncode({
  'theme': 'dark',
  'nope': 1,
  'mcpServers': {
    'linear': {
      'command': _secret,
      'env': {'TOKEN': _secret},
    },
  },
});

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('a read of every key folds to its files, and ctrl+o opens '
          'it, masked', (t) async {
        await _window(t, size, user: _settings);
        await _send(t, 'settingsread');
        await _shows(t, 'Settings · read (ctrl+o to expand)');
        final folded = t.screen.text;
        expect(folded, contains('· 2 keys'));
        expect(folded, contains('· not there'));
        expect(folded, contains('1 problem'));
        expect(folded, isNot(contains(_secret)));
        await t.press('ctrl+o');
        await _until(t, () => !t.screen.text.contains('to expand'));
        expect(t.screen.text, contains('"***"'));
        expect(t.screen.text, isNot(contains(_secret)));
      }, skip: skip);

      testWidgets("a set asks chord's box, then says where it was saved, and "
          'the theme is taken up at once', (t) async {
        final (:connection, :file) = await _window(
          t,
          size,
          user: '{"mouse":true}',
        );
        await _send(t, 'settingstheme');
        await _shows(t, 'Set theme?');
        final asked = t.screen.text;
        expect(asked, contains('Settings(theme) · set'));
        expect(asked, contains('Now    not set'));
        expect(asked, contains('After  "light"'));
        expect(asked, contains('1. Yes, in '));
        expect(asked, contains('2. No, tell fake what to change'));
        expect(asked, contains('Esc to tell fake what to change'));
        expect(asked, isNot(contains('read the whole change')));
        // chord's own question asks no permission.
        expect(asked, contains('Waiting for you…'));
        expect(asked, isNot(contains('Waiting for permission')));
        await t.press('1');
        await _shows(t, 'takes effect now');
        // The rows say what became of it; no outcome row of its own.
        expect(t.screen.text, isNot(contains('Allowed')));
        expect(t.screen.text, contains('Saved to '));
        expect(jsonDecode(File(file).readAsStringSync()), {
          'mouse': true,
          'theme': 'light',
        });
        expect(connection.app.value.theme, 'light');
      }, skip: skip);

      testWidgets('Esc on the box saves nothing and says so', (t) async {
        final (connection: _, :file) = await _window(
          t,
          size,
          user: '{"theme":"dark"}',
        );
        await _send(t, 'settingstheme');
        await _shows(t, 'Change theme?');
        await t.press('esc');
        await _shows(t, 'Not saved · the person will say what to change');
        expect(t.screen.text, isNot(contains('Rejected')));
        expect(File(file).readAsStringSync(), '{"theme":"dark"}');
      }, skip: skip);

      testWidgets('the same value asks nothing', (t) async {
        await _window(t, size, user: '{"theme":"light"}');
        await _send(t, 'settingstheme');
        await _shows(t, 'Settings(theme) · unchanged');
        expect(t.screen.text, contains('Already "light"; nothing to change'));
        expect(t.screen.text, isNot(contains('Yes, in')));
      }, skip: skip);

      testWidgets('a project value that wins is named under the change', (
        t,
      ) async {
        await _window(
          t,
          size,
          user: '{"agent":"claude"}',
          project: '{"agent":"fake"}',
        );
        await _send(t, 'settingsagent');
        await _shows(t, 'Change agent?');
        expect(
          t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
          contains(
            '${p.join('.chord', 'settings.json')} sets this too, and wins '
            'here',
          ),
        );
      }, skip: skip);

      testWidgets('a read of one key draws its three layers', (t) async {
        await _window(t, size, user: _settings);
        await _send(t, 'settingsreadkey');
        await _shows(t, 'Settings(mcpServers.linear.env.TOKEN) · read');
        final rows = t.screen.text;
        expect(rows, contains('Effective  "***"'));
        expect(rows, contains('User       "***"'));
        expect(rows, contains('Project    not set'));
        expect(rows, isNot(contains(_secret)));
      }, skip: skip);
    });
  }

  testWidgets('a change taller than the room says the key that reads it, at '
      '80x24', (t) async {
    await _window(t, const Size(80, 24), user: '{}');
    await _send(t, 'settingslong');
    await _shows(t, 'read the whole change');
    expect(t.screen.text, contains('Esc to tell fake what to change'));
    expect(t.screen.text, contains('pageup to read the whole change'));
    expect(t.screen.text, isNot(contains('Settings(agents.fake.model)')));
    // PageUp reads the change above the box, the box staying up.
    for (
      var i = 0;
      i < 30 && !t.screen.text.contains('Settings(agents.fake.model) · set');
      i++
    ) {
      await t.press('pageup');
      await t.pump();
    }
    expect(t.screen.text, contains('Settings(agents.fake.model) · set'));
    expect(t.screen.text, contains('1. Yes, in '));
  }, skip: skip);

  testWidgets('a narrow window gives the box the rows its wrapped hint '
      'takes, the prompt still under it', (t) async {
    await _window(t, const Size(40, 24), user: '{}');
    await _send(t, 'settingslong');
    await _shows(t, 'read the whole');
    await t.pump(const Duration(milliseconds: 100));
    final lines = [for (final line in t.screen.lines) line.trimRight()];
    // The box, top border to bottom, as tall as the room it was given: its
    // question, both choices whole, and the hint wrapped to two rows.
    final top =
        lines.indexWhere((line) => line.contains('Set agents.fake.model?')) - 1;
    final hint = lines.indexWhere(
      (line) => line.contains('pageup to read the whole change'),
    );
    expect(lines[top], startsWith('╭'), reason: t.screen.text);
    expect(lines[hint - 1], contains('Esc to tell fake what to change ·'));
    expect(lines[hint + 1], startsWith('╰'), reason: t.screen.text);
    final box = lines.sublist(top, hint + 2).join('\n');
    expect(box, contains('❯ 1. Yes, in '));
    expect(box, contains('2. No, tell fake what to change'));
    // Under it, the prompt and the status line, whole.
    expect(lines[hint + 3], startsWith('╭'));
    expect(lines[hint + 4], startsWith('│ ›'));
    expect(lines[hint + 5], startsWith('╰'));
    expect(lines[hint + 6], contains('for shortcuts'));
  }, skip: skip);

  testWidgets('vim mode is taken up at once', (t) async {
    final (:connection, file: _) = await _window(
      t,
      const Size(120, 40),
      user: '{}',
    );
    await _send(t, 'settingsvim');
    await _shows(t, 'Set editorMode?');
    await t.press('1');
    await _shows(t, 'takes effect now');
    expect(connection.app.value.vim, isNotNull);
  }, skip: skip);

  group('CTUI-79 tester: save box resize and retirement', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'the selected No choice survives wrapped resize and never saves at $size',
        (t) async {
          final (:connection, :file) = await _window(t, size, user: '{}');
          await _send(t, 'settingslong');
          await _shows(t, 'Set agents.fake.model?');
          await t.press('down');
          await t.pump();
          await t.resize(const Size(40, 24));
          await t.pump();
          expect(t.screen.text, contains('❯ 2. No, tell fake what to change'));
          expect(t.screen.text, contains('pageup to read the whole change'));
          expect(t.screen.text, contains('│ ›'));
          await t.press('enter');
          await _shows(t, 'Not saved');
          expect(File(file).readAsStringSync(), '{}');
          await t.resize(size);
          await t.pump();
          await t.type('next draft');
          await t.pump();
          expect(connection.app.value.draft, 'next draft');
        },
        skip: skip,
      );

      testWidgets(
        'clear retires the save box and a late yes cannot save at $size',
        (t) async {
          final (:connection, :file) = await _window(
            t,
            size,
            user: '{"theme":"dark"}',
          );
          await _send(t, 'settingstheme');
          await _shows(t, 'Change theme?');
          final wait =
              (connection.app.value.transcript.turn as model.AwaitingPermission)
                  .permissions
                  .single;
          await connection.conversation.clear();
          await _until(
            t,
            () =>
                connection.app.value.start.phase == StartPhase.connected &&
                !t.screen.text.contains('Change theme?'),
          );
          connection.conversation.choose(wait.id, 'yes');
          await t.pump();
          expect(File(file).readAsStringSync(), '{"theme":"dark"}');
          expect(connection.app.value.theme, isNot('light'));
          await t.type('fresh draft');
          await t.pump();
          expect(connection.app.value.draft, 'fresh draft');
        },
        skip: skip,
      );
    }
  });
}
