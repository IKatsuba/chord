// /model, /config, /effort and /fast typed while the agent starts, as the
// original's commands.ts 171-180 and 237-256 and pickers/state.ts 144-180,
// 265-317: /model and /config are kept and open once the session is up,
// never after a failed start nor once closing; /effort with no value notes
// at once that there is no effort yet; /effort <id> and /fast do nothing.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import 'resume_window_test.dart' show launch;
import 'window_fake_test.dart' show until;

typedef _Held = ({StartConnection connection, File gate});

/// A window on the fake, held starting until its gate is opened.
Future<_Held> _held(
  WidgetTester t,
  Size size, {
  List<String> flags = const [],
}) async {
  final directory = Directory.systemTemp.createTempSync('chord-held-start-');
  final gate = File('${directory.path}/open');
  final pids = <int>[];
  final connection = StartConnection(
    command: gatedCommand(
      gate.path,
      fakeAgentCommand(null, flags),
    ).map(shellWord).join(' '),
    cwd: directory.path,
    env: {'XDG_STATE_HOME': directory.path},
    agent: 'fake',
    owner: Owned(),
    open: fakeSessionOpener(pids.add),
  )..start();
  addTearDown(() async {
    await connection.close();
    expect(
      pids.where(
        (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
      ),
      isEmpty,
    );
    directory.deleteSync(recursive: true);
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: launch,
      connection: connection,
      readSessionRecords: ({cancellationToken}) async => [],
    ),
    size: size,
  );
  await t.pump();
  expect(connection.app.value.start.phase, StartPhase.starting);
  return (connection: connection, gate: gate);
}

Future<void> _command(WidgetTester t, String text) async {
  await t.type(text);
  await t.pump();
  await t.press('enter');
  await t.pump();
}

Future<void> _open(WidgetTester t, _Held held, StartPhase phase) async {
  held.gate.createSync();
  await until(() => held.connection.app.value.start.phase == phase);
  await t.pump();
  await t.pump();
}

void main() {
  group('tester CTUI-162: pending picker ownership', skip: fakeAgentSkip, () {
    for (final (command, heading) in [
      ('/model fake-small', 'Select model'),
      ('/config ignored', 'Settings'),
    ]) {
      testWidgets('$command keeps the original picker form through a resize', (
        t,
      ) async {
        final held = await _held(t, const Size(120, 40));
        await _command(t, command);
        await t.resize(const Size(80, 24));
        expect(held.connection.app.value.transcript.entries, isEmpty);
        expect(t.screen, isNot(shows(heading)));
        await _open(t, held, StartPhase.connected);
        expect(t.screen, shows(heading));
        await t.press('escape');
        await t.pump();
        expect(t.screen, isNot(shows(heading)));
        await t.type('draft 界👩‍💻é');
        await t.pump();
        expect(held.connection.app.value.draft, 'draft 界👩‍💻é');
      });
    }

    testWidgets(
      'two held sessions keep their own request and focus after opening',
      (t) async {
        final other = WidgetTester();
        addTearDown(other.dispose);
        final first = await _held(t, const Size(120, 40));
        final second = await _held(other, const Size(80, 24));
        await _command(t, '/model');
        await _command(other, '/config');
        await _open(other, second, StartPhase.connected);
        expect(other.screen, shows('Settings'));
        expect(t.screen, isNot(shows('Settings')));
        await _open(t, first, StartPhase.connected);
        expect(t.screen, shows('Select model'));
        expect(other.screen, shows('Settings'));
        await t.press('escape');
        await other.press('escape');
        await t.pump();
        await other.pump();
        expect(t.screen, isNot(shows('Select model')));
        expect(other.screen, isNot(shows('Settings')));
      },
    );

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('clear retires pending config at $size', (t) async {
        final held = await _held(t, size);
        await _command(t, '/config');
        await _command(t, '/clear');
        await _open(t, held, StartPhase.connected);
        expect(t.screen, isNot(shows('Settings')));
        await t.type('draft');
        await t.pump();
        expect(held.connection.app.value.draft, 'draft');
      });
    }
  });
  group(
    'CTUI-162: settings typed while the agent starts',
    skip: fakeAgentSkip,
    () {
      for (final size in const [Size(120, 40), Size(80, 24)]) {
        testWidgets('/model opens its picker once the session is up at $size', (
          t,
        ) async {
          final held = await _held(t, size);
          await _command(t, '/model');
          expect(held.connection.app.value.draft, '');
          expect(t.screen, isNot(shows('Select model')));
          await _open(t, held, StartPhase.connected);
          expect(t.screen, shows('Select model'));
        });

        testWidgets(
          '/config opens its picker once the session is up at $size',
          (t) async {
            final held = await _held(t, size);
            await _command(t, '/config');
            expect(t.screen, isNot(shows('Settings')));
            await _open(t, held, StartPhase.connected);
            expect(t.screen, shows('Settings'));
          },
        );

        testWidgets(
          '/effort notes at once that there is no effort yet at $size',
          (t) async {
            final held = await _held(t, size);
            await _command(t, '/effort');
            expect(t.screen, shows('fake offers no effort.'));
            expect(t.screen, isNot(shows('for .')));
            expect(
              held.connection.app.value.transcript.entries.single,
              isA<model.NotedEntry>(),
            );
            await _open(t, held, StartPhase.connected);
            expect(t.screen, isNot(shows('Effort')));
          },
        );

        testWidgets('/effort <id> and /fast do nothing, then or once up, at '
            '$size', (t) async {
          final held = await _held(t, size);
          await _command(t, '/effort high');
          await _command(t, '/fast');
          expect(held.connection.app.value.transcript.entries, isEmpty);
          expect(held.connection.app.value.draft, '');
          await _open(t, held, StartPhase.connected);
          expect(held.connection.app.value.transcript.entries, isEmpty);
          expect(t.screen, isNot(shows('Effort')));
          expect(t.screen, isNot(shows('fast')));
        });

        testWidgets('a start that fails never opens what was asked at $size', (
          t,
        ) async {
          final held = await _held(t, size, flags: ['--start-fails', 'alias']);
          await _command(t, '/model');
          await _command(t, '/config');
          await _open(t, held, StartPhase.failed);
          expect(t.screen, shows('fake did not start'));
          expect(t.screen, isNot(shows('Select model')));
          expect(t.screen, isNot(shows('Settings')));
        });
      }

      for (final (first, last, shown, other) in const [
        ('/model', '/config', 'Settings', 'Select model'),
        ('/config', '/model', 'Select model', 'Settings'),
      ]) {
        testWidgets('$first then $last while starting: the last asked opens, '
            'alone, and the first does not follow it', (t) async {
          final held = await _held(t, const Size(80, 24));
          await _command(t, first);
          await _command(t, last);
          await _open(t, held, StartPhase.connected);
          expect(t.screen, shows(shown));
          expect(t.screen, isNot(shows(other)));
          await t.press('esc');
          await t.pump();
          await t.pump();
          expect(t.screen, isNot(shows(shown)));
          expect(t.screen, isNot(shows(other)));
        });
      }

      testWidgets('/clear while starting lets go of what was asked', (t) async {
        final held = await _held(t, const Size(80, 24));
        await _command(t, '/model');
        await _command(t, '/clear');
        await _open(t, held, StartPhase.connected);
        expect(t.screen, isNot(shows('Select model')));
      });

      testWidgets('closing while starting lets go of what was asked', (
        t,
      ) async {
        final held = await _held(t, const Size(80, 24));
        await _command(t, '/model');
        await t.press('ctrl+d');
        expect(t.exitRequested, isTrue);
        held.gate.createSync();
        await t.pump(const Duration(milliseconds: 300));
        expect(t.screen, isNot(shows('Select model')));
      });
    },
  );
}
