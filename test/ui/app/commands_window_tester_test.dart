@Tags(['fake_agent'])
library;

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

void main() {
  group('tester slash dispatch lifecycle', skip: fakeAgentSkip, () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'batched navigation and Tab use the latest highlight at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          final focus = t.focusManager.primaryFocus;
          await t.type('/');
          await t.pump();
          for (var i = 0; i < 4; i++) {
            t.host.handleKey(const KeyEvent('down'));
          }
          t.host.handleKey(const KeyEvent('tab'));
          await t.pump();
          expect(c.app.value.draft, '/echo ');
          expect(c.app.value.transcript.entries, isEmpty);
          expect(t.focusManager.primaryFocus, same(focus));
          await t.type('界🙂e\u0301');
          await t.press('enter');
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .isNotEmpty,
          );
          expect(
            c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            '/echo 界🙂e\u0301',
          );
        },
      );

      testWidgets(
        'withdrawn advertisements cannot accept an old match at $size',
        (t) async {
          final c = await fixture.connected(t, size);
          await t.type('/zz');
          c.app.value = reduceApp(
            c.app.value,
            AgentStateChanged(
              AgentState(
                commands: [
                  acp.AvailableCommand.fromJson({
                    'name': 'zz-old',
                    'description': 'Previously offered',
                  }),
                ],
              ),
            ),
          );
          await t.pump();
          expect(t.screen, shows('zz-old'));
          for (var i = 0; i < 1000; i++) {
            c.app.value = reduceApp(
              c.app.value,
              AgentStateChanged(
                AgentState(
                  commands: i == 999
                      ? []
                      : [
                          acp.AvailableCommand.fromJson({
                            'name': 'zz-$i',
                            'description': 'Intermediate advertisement',
                          }),
                        ],
                ),
              ),
            );
          }
          t.host.handleKey(const KeyEvent('tab'));
          expect(c.app.value.draft, '/zz');
          t.host.handleKey(const KeyEvent('enter'));
          await fixture.until(
            () => c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .isNotEmpty,
          );
          await t.pump();
          expect(
            c.app.value.transcript.entries
                .whereType<model.UserEntry>()
                .single
                .text,
            '/zz',
          );
          expect(
            c.app.value.transcript.entries.whereType<model.ReportEntry>(),
            isEmpty,
          );
        },
      );
    }
  });
}
