@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';
import 'package:chord_tui/testing.dart';
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('live slash commands', skip: fakeAgentSkip, () {
    testWidgets(
      'advertisement replacement is re-matched before same-chunk acceptance',
      (t) async {
        final c = await fixture.connected(t, const Size(80, 24));
        await t.type('/zz');
        c.app.value = reduceApp(
          c.app.value,
          AgentStateChanged(
            AgentState(
              commands: [
                acp.AvailableCommand.fromJson({
                  'name': 'zz-old',
                  'description': 'old',
                }),
              ],
            ),
          ),
        );
        await t.pump();
        expect(t.screen, shows('zz-old'));
        c.app.value = reduceApp(
          c.app.value,
          AgentStateChanged(
            AgentState(
              commands: [
                acp.AvailableCommand.fromJson({
                  'name': 'zz-new',
                  'description': 'new',
                }),
              ],
            ),
          ),
        );
        t.host.handleKey(KeyCombo.parse('enter').toEvent());
        await t.pump();
        await fixture.until(
          () => c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .isNotEmpty,
        );
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>().last.text,
          '/zz-new',
        );
      },
    );
    testWidgets(
      'zero completion room submits typed text and restored room never defers acceptance',
      (t) async {
        final c = await fixture.connected(t, const Size(80, 24));
        await t.type('/sta');
        await t.pump();
        await t.resize(const Size(80, 5));
        expect(t.screen, isNot(shows('Show the agent, model')));
        await t.press('tab');
        expect(c.app.value.draft, '/sta');
        expect(t.screen, shows('not enough space'));
        await t.resize(const Size(80, 24));
        await t.pump();
        expect(t.screen, isNot(shows('not enough space')));
        expect(c.app.value.draft, '/sta');
        await t.resize(const Size(80, 5));
        await t.press('tab');
        expect(t.screen, shows('not enough space'));
        await t.press('enter');
        await fixture.until(
          () => c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .isNotEmpty,
        );
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>().last.text,
          '/sta',
        );
        await t.resize(const Size(120, 40));
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          isEmpty,
        );
      },
    );
    testWidgets(
      'agent completion accepts arguments and resize preserves semantic highlight',
      (t) async {
        final c = await fixture.connected(t, const Size(120, 40));
        await t.type('/ec');
        await t.pump();
        await t.press('tab');
        expect(c.app.value.draft, '/echo ');
        await t.type('hello');
        await t.press('enter');
        await fixture.until(
          () => c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .isNotEmpty,
        );
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>().last.text,
          '/echo hello',
        );
        await t.type('/');
        await t.pump();
        t.host.handleKey(KeyCombo.parse('up').toEvent());
        await t.pump();
        await t.resize(const Size(80, 24));
        await t.press('tab');
        expect(c.app.value.draft, '/vim ');
        await t.press('ctrl+u');
        await t.type('/no-matching-command');
        await t.press('up');
        expect(c.app.value.draft, '/echo hello');
      },
    );
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'first Escape dismisses completion, editing reopens it, next Escape interrupts at $size',
        (t) async {
          final c = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '100'],
          );
          await t.type('slow');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.type('/sta');
          await t.pump();
          await t.press('esc');
          expect(
            c.app.value.transcript.entries.whereType<model.CancelledEntry>(),
            isEmpty,
          );
          expect(c.app.value.draft, '/sta');
          await t.type('t');
          expect(t.screen, shows('Show the agent, model'));
          await t.press('esc');
          expect(
            c.app.value.transcript.entries.whereType<model.CancelledEntry>(),
            isEmpty,
          );
          await t.press('esc');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.CancelledEntry>()
                .isNotEmpty,
          );
          expect(c.app.value.draft, '/stat');
        },
      );
      testWidgets(
        'clear preserves withdrawn queued text while replacing a running session at $size',
        (t) async {
          final c = await fixture.connected(
            t,
            size,
            flags: ['--step-ms', '100'],
          );
          await t.type('slow');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .isNotEmpty,
          );
          await t.type('queued first');
          await t.press('enter');
          expect(c.app.value.queue, hasLength(1));
          final old = c.app.value.start.sessionId;
          await t.type('/clear');
          await t.pump();
          await t.press('enter');
          await fixture.until(
            () =>
                c.app.value.start.sessionId != null &&
                c.app.value.start.sessionId != old,
          );
          await t.pump();
          expect(c.app.value.draft, 'queued first');
          expect(c.app.value.queue, isEmpty);
          expect(c.app.value.transcript.entries, isEmpty);
          expect(t.screen, shows('│ › queued first'));
        },
      );
      testWidgets(
        'completion keeps typing/focus and Tab inserts without sending at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          final focus = t.focusManager.primaryFocus;
          await t.type('/');
          await t.pump();
          expect(t.screen, shows('Start a new session'));
          await t.press('down');
          await t.press('tab');
          expect(c.app.value.draft, '/config ');
          expect(c.app.value.transcript.entries, isEmpty);
          expect(t.focusManager.primaryFocus, same(focus));
          await t.press('ctrl+u');
          await t.type('/mod');
          await t.pump();
          await t.press('enter');
          expect(t.screen, shows('Select model'));
          await t.press('esc');
          expect(t.focusManager.primaryFocus, same(focus));
        },
      );
      testWidgets(
        'dismissal preserves draft and ordinary typed commands trim at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/sta');
          await t.pump();
          await t.press('esc');
          expect(c.app.value.draft, '/sta');
          expect(t.screen, isNot(shows('Show the agent, model')));
          await t.press('ctrl+u');
          await t.type('  ordinary text  ');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .isNotEmpty,
          );
          expect(
            c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .first
                .text,
            'ordinary text',
          );
        },
      );
      testWidgets(
        'status is local and clear replaces session without forwarding reserved names at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/status');
          await t.pump();
          await t.press('enter');
          expect(
            c.app.value.transcript.entries.whereType<model.ReportEntry>(),
            hasLength(1),
          );
          expect(t.screen, shows('Session:'));
          expect(t.screen, shows('Directory:'));
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
          // /team is chord's own: it leaves the box and sends nothing.
          await t.type('/team edit');
          await t.press('enter');
          expect(c.app.value.draft, '');
          expect(
            c.app.value.transcript.entries.whereType<model.UserEntry>(),
            isEmpty,
          );
          final old = c.app.value.start.sessionId;
          await t.type('/clear');
          await t.pump();
          await t.press('enter');
          await fixture.until(
            () =>
                c.app.value.start.sessionId != null &&
                c.app.value.start.sessionId != old,
          );
          await t.pump();
          expect(c.app.value.transcript.entries, isEmpty);
          expect(c.app.value.draft, isEmpty);
          await t.type('/help');
          await t.pump();
          await t.press('enter');
          expect(c.app.value.shortcuts.help, isTrue);
          await t.press('esc');
        },
      );
    }
  });
}
