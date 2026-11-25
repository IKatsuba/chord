@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/efforts.dart';
import 'package:chord/session/models.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void keys(WidgetTester t, List<String> keys) {
  for (final key in keys) {
    t.host.handleKey(KeyCombo.parse(key).toEvent());
  }
}

void main() {
  test(
    'intent reduction composes repeated arrows and highlight without stale snapshots',
    () {
      const efforts = (
        option: 'effort',
        current: 'medium',
        available: [
          (id: 'low', name: 'Low'),
          (id: 'medium', name: 'Medium'),
          (id: 'high', name: 'High'),
          (id: 'max', name: 'Max'),
        ],
      );
      var state = const SettingsPickerState('model');
      for (final action in [
        const EffortMoved(1),
        const EffortMoved(1),
        const ModelHighlighted('small'),
      ]) {
        state = settingsPickerChanged(state, action, efforts);
      }
      expect(state.effort?.value, 'max');
      expect(state.highlighted, 'small');
      state = settingsPickerChanged(state, const EffortMoved(-1), efforts);
      expect(state.effort?.value, 'high');
      expect(state.highlighted, 'small');
      state = settingsPickerChanged(state, const EffortMoved(-1), efforts);
      expect(state.effort, isNull);
      expect(state.highlighted, 'small');
    },
  );
  group('live same-chunk settings', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'arrows, model highlight and numeric acceptance consume latest intent at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          keys(t, ['right', 'down']);
          await t.pump();
          expect(t.screen, shows('High effort •'));
          expect(t.screen, shows('asked for'));
          keys(t, ['left', 'up']);
          await t.pump();
          expect(t.screen, shows('Medium effort'));
          expect(t.screen, isNot(shows('High effort •')));
          keys(t, ['down', 'right', '2']);
          await t.pump();
          await fixture.until(
            () =>
                modelsFrom(
                      c.app.value.agent.configOptions,
                      c.app.value.agent.models,
                    )?.current ==
                    'fake-small' &&
                effortsFrom(c.app.value.agent.configOptions)?.current == 'high',
          );
          await t.pump();
          expect(
            c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .last
                .text,
            'Switched to Fake Small · High effort',
          );
        },
      );
      testWidgets(
        'Gone retains current intent and uses the dead-agent refusal at $size',
        (t) async {
          var pid = 0;
          final c = await fixture.connected(
            t,
            size,
            onPid: (value) => pid = value,
          );
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          expect(Process.killPid(pid, ProcessSignal.sigterm), isTrue);
          await fixture.until(() => c.app.value.start.phase == StartPhase.gone);
          keys(t, ['right', 'down', 'enter']);
          await t.pump();
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .any((entry) => entry.failed),
          );
          await t.pump();
          expect(
            t.screen,
            shows('Could not switch to Fake Small: The agent exited.'),
          );
        },
      );
      testWidgets(
        'Enter accepts latest effort while Escape and Closing invalidate old callbacks at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          keys(t, ['right', 'enter']);
          await t.pump();
          await fixture.until(
            () =>
                effortsFrom(c.app.value.agent.configOptions)?.current == 'high',
          );
          await t.pump();
          final count = c.app.value.transcript.entries.length;
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          keys(t, ['left', 'esc', 'enter']);
          await t.pump();
          expect(c.app.value.transcript.entries, hasLength(count));
          expect(effortsFrom(c.app.value.agent.configOptions)?.current, 'high');
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          keys(t, ['left', 'down']);
          c.app.value = reduceApp(c.app.value, const Closing());
          keys(t, ['right', 'enter']);
          await t.pump();
          expect(c.app.value.transcript.entries, hasLength(count));
        },
      );
    }
  });
}
