@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  _testerCursorWindowCases();
  group('terminal prompt cursor', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('completion keeps cursor and picker restores it at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        final empty = t.screen.buffer.cursor!;
        expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
        await t.type('/sta');
        await t.pump();
        expect(t.screen, shows('Show the agent, model'));
        expect(t.screen.buffer.cursor, Offset(empty.x + 4, empty.y));
        expect(t.screen.styleAt(empty.x + 4, empty.y).isInverse, isFalse);
        await t.press('esc');
        expect(connection.app.value.draft, '/sta');
        expect(t.screen.buffer.cursor, Offset(empty.x + 4, empty.y));
        await t.press('ctrl+u');
        await t.type('/model');
        await t.press('enter');
        await t.pump();
        expect(t.screen, shows('Select model'));
        expect(t.screen.buffer.cursor, isNull);
        await t.press('esc');
        await t.pump();
        expect(t.screen.buffer.cursor, empty);
        expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
        await t.type('界e\u0301🙂');
        expect(t.screen.buffer.cursor, Offset(empty.x + 5, empty.y));
        await t.press('left left');
        expect(t.screen.buffer.cursor, Offset(empty.x + 2, empty.y));
        await t.resize(Size.zero);
        expect(t.screen.buffer.cursor, isNull);
        await t.resize(size);
        expect(t.screen.buffer.cursor, Offset(empty.x + 2, empty.y));
      });
    }
  });
}

void _testerCursorWindowCases() {
  group('tester: terminal cursor session lifecycle', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'hung and late sessions keep independent draft cursors at $size',
        (t) async {
          final other = WidgetTester();
          addTearDown(other.dispose);
          late int pid;
          final first = await fixture.connected(
            t,
            size,
            onPid: (value) => pid = value,
          );
          final second = await fixture.connected(
            other,
            const Size(40, 12),
            flags: ['--step-ms', '100'],
          );
          await t.type('ignorescancel');
          await t.press('enter');
          await fixture.until(
            () => first.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.press('esc');
          await t.type('界e\u0301🙂');
          final before = t.screen.buffer.cursor!;
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          await fixture.sent(other, second, 'late');
          await other.type('independent');
          await fixture.until(
            () => second.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any(
                  (entry) =>
                      entry.text.text.contains('Late, after the answer.'),
                ),
          );
          await other.pump();
          expect(other.screen.buffer.cursor, isNotNull);
          expect(other.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          expect(second.app.value.draft, 'independent');
          await t.pump();
          expect(first.app.value.draft, '界e\u0301🙂');
          expect(t.screen.buffer.cursor, before);
          await t.press('left left');
          expect(t.screen.buffer.cursor, Offset(before.x - 3, before.y));
          Process.killPid(-pid, ProcessSignal.sigkill);
          await fixture.until(
            () => first.app.value.start.phase == StartPhase.gone,
          );
          await t.pump();
          expect(t.screen.buffer.cursor, isNotNull);
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          expect(second.app.value.start.phase, StartPhase.connected);
        },
      );

      testWidgets('cancelled turn restores editable prompt cursor at $size', (
        t,
      ) async {
        final connection = await fixture.connected(t, size);
        await t.type('slow');
        await t.press('enter');
        await fixture.until(
          () => connection.app.value.transcript.entries
              .whereType<model.AssistantEntry>()
              .isNotEmpty,
        );
        await t.press('esc');
        await fixture.until(
          () => connection.app.value.transcript.turn is model.Idle,
        );
        await t.pump();
        expect(
          connection.app.value.transcript.entries
              .whereType<model.CancelledEntry>(),
          isNotEmpty,
        );
        final empty = t.screen.buffer.cursor!;
        await t.type('界🙂');
        expect(t.screen.buffer.cursor, Offset(empty.x + 4, empty.y));
        await t.press('left');
        expect(t.screen.buffer.cursor, Offset(empty.x + 2, empty.y));
        await t.resize(const Size(1, 1));
        expect(t.screen.buffer.cursor, isNull);
        await t.resize(size);
        expect(t.screen.buffer.cursor, Offset(empty.x + 2, empty.y));
      });
    }
  });
}
