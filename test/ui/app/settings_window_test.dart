@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/models.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/session/modes.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('live session setting actions', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'initialized picker remains after actual fake exit and reports refusal at $size',
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
          await t.press('down');
          expect(Process.killPid(pid, ProcessSignal.sigterm), isTrue);
          await fixture.until(() => c.app.value.start.phase == StartPhase.gone);
          await t.pump();
          expect(t.screen, shows('Select model'));
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .any((entry) => entry.failed),
          );
          await t.pump();
          expect(t.screen, shows('Could not switch to Fake Small'));
          expect(t.screen, shows('⏺'));
          await t.type('/config');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Settings'));
          await t.press('esc');
          await t.type('/effort');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Effort'));
          await t.press('esc');
        },
      );
      testWidgets(
        'failed initialization and closing reject same-chunk picker input at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          final connected = c.app.value.start;
          final agent = c.app.value.agent;
          for (final closing in [false, true]) {
            c.app.value = AppState(start: connected, agent: agent);
            await t.pump();
            await t.type('/model');
            await t.press('enter');
            await t.pump();
            await t.press('down');
            c.app.value = closing
                ? reduceApp(c.app.value, const Closing())
                : AppState(
                    start: const StartState(phase: StartPhase.failed),
                    agent: agent,
                  );
            t.host.handleKey(KeyCombo.parse('enter').toEvent());
            await t.pump();
            expect(t.screen, isNot(shows('Select model')));
            expect(
              c.app.value.transcript.entries.whereType<model.NotedEntry>(),
              isEmpty,
            );
          }
        },
      );

      testWidgets(
        'model preview, effort commit and config back preserve prompt at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          final promptFocus = t.focusManager.primaryFocus;
          final promptTop = t.screen.lines.indexWhere(
            (line) => line.startsWith('╭'),
          );
          final scroll = c.app.value.scroll;
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Select model'));
          expect(t.screen, shows('Medium effort  ←/→ to adjust'));
          expect(c.app.value.scroll, scroll);
          expect(
            t.screen.lines.lastIndexWhere((line) => line.startsWith('╭')),
            promptTop,
          );
          await t.press('right');
          expect(t.screen, shows('High effort •'));
          await t.press('down');
          expect(t.screen, shows('asked for'));
          await t.press('enter');
          await fixture.until(
            () =>
                modelsFrom(
                  c.app.value.agent.configOptions,
                  c.app.value.agent.models,
                )?.current ==
                'fake-small',
          );
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .last
                .text
                .contains('Switched to'),
          );
          await t.pump();
          expect(t.focusManager.primaryFocus, same(promptFocus));
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
          expect(
            c.app.value.transcript.entries.whereType<model.NotedEntry>(),
            hasLength(1),
          );
          await t.type('/config');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Settings'));
          await t.press('enter');
          expect(t.screen, shows('Set Effort'));
          await t.press('esc');
          expect(t.screen, shows('Settings'));
          await t.press('esc');
          expect(t.focusManager.primaryFocus, same(promptFocus));
          await t.type('draft');
          await t.press('shift+tab');
          await fixture.until(
            () =>
                modesFrom(
                  c.app.value.agent.configOptions,
                  c.app.value.agent.modes,
                )?.current ==
                'acceptEdits',
          );
          await t.pump();
          expect(c.app.value.draft, 'draft');
          expect(t.screen, shows('accept edits on'));
          if (size.width == 120) {
            expect(t.screen, shows('(shift+tab to cycle)'));
          }
          await t.press('ctrl+c');
          await t.type('/effort');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('accept edits on'));
          expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
          await t.press('esc');
        },
      );
      testWidgets(
        'Esc discards effort preview and effort id runs locally at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/model');
          await t.press('enter');
          await t.pump();
          await t.press('right');
          await t.press('esc');
          expect(c.app.value.transcript.entries, isEmpty);
          await t.type('/effort');
          await t.press('enter');
          await t.pump();
          expect(t.screen, shows('Effort'));
          await t.press('3');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .any((e) => e.text == 'Effort set to High'),
          );
          await t.pump();
          expect(t.screen, shows('Effort set to High'));
          await t.type('/effort unknown');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.NotedEntry>()
                .any((e) => e.text.contains('offers low, medium, high effort')),
          );
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
        },
      );
    }
  });
}
