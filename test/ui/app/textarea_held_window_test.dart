import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

const launch = Launch(
  name: 'fixture',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: 'project/package',
);

/// The window, connected, over a transcript long enough to scroll.
Future<StartConnection> _window(WidgetTester t, Size size) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  addTearDown(connection.close);
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    transcript: model.Transcript(
      entries: [for (var i = 0; i < 100; i++) model.UserEntry('t$i', 'row $i')],
    ),
  );
  await t.pumpWidget(
    TranscriptWindow(launch: launch, connection: connection),
    size: size,
  );
  return connection;
}

// The prompt reaches of the text area's keys what the original's does:
// its TEXTAREA list and the three cmd keys (CTUI-164); the rest are the
// window's.
void main() {
  _testerHeldPromptCases();
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('ctrl+d on an empty prompt still quits at $size', (t) async {
      await _window(t, size);
      await t.press('ctrl+d');
      expect(t.exitRequested, isTrue);
    });

    testWidgets('shift+home and shift+end still scroll at $size', (t) async {
      final connection = await _window(t, size);
      await t.type('draft');
      await t.press('shift+home');
      expect(connection.app.value.scroll.following, isFalse);
      await t.press('shift+end');
      expect(connection.app.value.scroll.following, isTrue);
      expect(connection.app.value.draft, 'draft');
    });

    testWidgets(
      'keys the original\'s prompt does not reach do nothing at $size',
      (t) async {
        final connection = await _window(t, size);
        await t.type('alpha beta');
        await t.press('left left');
        for (final keys in [
          'shift+left',
          'ctrl+f',
          'ctrl+b',
          'alt+d',
          'ctrl+shift+d',
          'ctrl+left',
          'shift+backspace',
        ]) {
          await t.press(keys);
          expect(connection.app.value.draft, 'alpha beta', reason: keys);
          expect(connection.app.value.cursor, 8, reason: keys);
        }
        // Nothing was selected: a typed key goes in at the cursor.
        await t.type('X');
        expect(connection.app.value.draft, 'alpha beXta');
      },
    );
  }
}

const _testerHeldKeys = [
  'ctrl+b',
  'ctrl+f',
  'ctrl+left',
  'ctrl+right',
  'alt+a',
  'alt+e',
  'ctrl+backspace',
  'alt+d',
  'alt+delete',
  'ctrl+delete',
  'shift+delete',
  'ctrl+shift+d',
  'ctrl+-',
  'ctrl+.',
  'shift+left',
  'shift+right',
  'alt+shift+left',
  'alt+shift+right',
  'alt+shift+b',
  'alt+shift+f',
  'ctrl+shift+a',
  'ctrl+shift+e',
  'alt+shift+a',
  'alt+shift+e',
  'shift+super+left',
  'shift+super+right',
  'shift+super+up',
  'shift+super+down',
];

void _testerHeldPromptCases() {
  group('tester CTUI-164: held prompt Unicode keys', () {
    for (final size in const [Size(120, 40), Size(80, 24), Size(24, 8)]) {
      testWidgets(
        'every new held alias leaves Unicode insertion intact at $size',
        (t) async {
          final c = await _window(t, size);
          await t.paste('界👩‍💻e\u0301 end');
          await t.press('left left left');
          final cursor = c.app.value.cursor;
          for (final key in _testerHeldKeys) {
            await t.press(key);
            expect(
              (c.app.value.draft, c.app.value.cursor),
              ('界👩‍💻e\u0301 end', cursor),
              reason: key,
            );
          }
          await t.resize(const Size(80, 24));
          await t.type('!');
          expect(c.app.value.draft, '界👩‍💻e\u0301 !end');
          await t.press('shift+backspace');
          expect(c.app.value.draft, '界👩‍💻e\u0301 !end');
        },
      );
    }
  });

  group(
    'tester CTUI-164: held keys through fake lifecycle',
    skip: fakeAgentSkip,
    () {
      testWidgets(
        'cancel, hang, late answer and exit keep independent drafts',
        (t) async {
          final other = WidgetTester();
          addTearDown(other.dispose);
          late int firstPid;
          final first = await fixture.connected(
            t,
            const Size(80, 24),
            onPid: (pid) => firstPid = pid,
          );
          final second = await fixture.connected(
            other,
            const Size(40, 12),
            flags: ['--step-ms', '100'],
          );
          await t.type('slow');
          await t.press('enter');
          await fixture.until(
            () => first.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.press('esc');
          await fixture.until(
            () => first.app.value.transcript.turn is model.Idle,
          );
          await t.type('ignorescancel');
          await t.press('enter');
          await fixture.until(
            () => first.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any((entry) => entry.text.text.contains('Holding on.')),
          );
          await t.press('esc');
          await t.paste('界👩‍💻e\u0301 end');
          await t.press('left left left');
          await fixture.sent(other, second, 'late');
          await other.type('other draft');
          await other.press('super+a');
          for (final key in _testerHeldKeys) {
            await t.press(key);
          }
          await t.type('!');
          expect(first.app.value.draft, '界👩‍💻e\u0301 !end');
          await fixture.until(
            () => second.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any((e) => e.text.text.contains('Late, after the answer.')),
          );
          expect(second.app.value.draft, 'other draft');
          Process.killPid(-firstPid, ProcessSignal.sigkill);
          await fixture.until(
            () => first.app.value.start.phase == StartPhase.gone,
          );
          await t.pump();
          await t.press('super+a alt+d');
          await t.type('?');
          expect(first.app.value.draft, '?');
          expect(second.app.value.start.phase, StartPhase.connected);
          expect(second.app.value.draft, 'other draft');
          await other.type('replacement');
          expect(second.app.value.draft, 'replacement');
        },
      );
    },
  );
}
