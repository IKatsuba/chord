import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../app/code_pick_window_test.dart' show pressBounded, clickAt;
import '../../app/selection_window_test.dart';

void main() {
  group('tester nested subagent selection lifecycle', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'fold expand fold invalidates launch pick and restores run eligibility $size',
        (t) async {
          final c = selectionConnection([
            const model.AgentMessageEntry(
              't',
              'launch',
              toSubagent: true,
              agentId: 'a',
              title: 'agent',
              launch: true,
              text:
                  'Run first.\n\n```sh\necho launch\n```\n\nOne\n\nTwo\n\nThree\n\nFour\n\nFive',
            ),
          ]);
          addTearDown(c.close);
          final writes = <String>[];
          var executed = 0;
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: c,
              copy: (text, _) {
                writes.add(text);
                return const copy.CopyResult.sent();
              },
              runShell: (_, _) {
                executed++;
                throw StateError('unexpected shell');
              },
            ),
            size: size,
          );
          expect(t.screen.text, contains('echo launch'));
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen.text, contains('No code block to pick'));
          await t.press('ctrl+o');
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen.text, contains('another block'));
          await t.press('ctrl+o');
          expect(t.screen.text, isNot(contains('another block')));
          await t.press('c');
          expect(writes, isEmpty);
          await t.press('ctrl+c');
          await t.press('ctrl+o');
          await pressBounded(t, 'ctrl+x b r');
          expect(c.app.value.bash, isTrue);
          expect(c.app.value.draft, 'echo launch');
          expect(executed, 0);
        },
      );

      testWidgets(
        'nested code after notice permission and compaction copies and runs $size',
        (t) async {
          final c = selectionConnection([
            model.SubagentEntry(
              't',
              model.Subagent(
                'outer',
                title: 'outer',
                state: model.SubagentState.completed,
                entries: [
                  const model.NoticeEntry(
                    't',
                    model.NoticeSeverity.warning,
                    'Notice furniture',
                    description: 'Not selectable',
                  ),
                  const model.PermissionEntry('t', title: 'Allowed work'),
                  const model.CompactionEntry(
                    't',
                    model.Compaction(
                      'k',
                      'completed',
                      summary: 'Kept context.',
                    ),
                  ),
                  model.AssistantEntry(
                    't',
                    TextRun.empty.plus(
                      'Reply 界🙂e\u0301\n\n```sh\necho nested\n```',
                    ),
                  ),
                ],
              ),
            ),
            const model.SubagentEntry(
              't',
              model.Subagent(
                'next',
                title: 'next',
                state: model.SubagentState.completed,
              ),
            ),
          ]);
          addTearDown(c.close);
          final writes = <String>[];
          var executed = 0;
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: c,
              copyOnSelect: false,
              copy: (text, _) {
                writes.add(text);
                return const copy.CopyResult.sent();
              },
              runShell: (_, _) {
                executed++;
                throw StateError('unexpected shell');
              },
            ),
            size: size,
          );
          await t.press('ctrl+o');
          await pressBounded(t, 'ctrl+x b c');
          expect(writes, ['echo nested']);
          await clickAt(t, cellOf(t, '[copy]'));
          expect(writes.last, 'echo nested');
          await select(t, 'Reply 界🙂e\u0301');
          await t.press('ctrl+shift+c');
          expect(writes.last, 'Reply 界🙂e\u0301');
          await pressBounded(t, 'ctrl+x b r');
          expect(c.app.value.draft, 'echo nested');
          expect(executed, 0);
          await t.press('ctrl+c');
          for (final resized in [Size.zero, const Size(1, 1), size]) {
            await t.resize(resized);
          }
          await t.press('ctrl+o');
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen.text, contains('No code block to pick'));
          await t.pumpWidget(const SizedBox(), size: size);
          await t.pump(const Duration(seconds: 3));
        },
      );
    }
  });
}
