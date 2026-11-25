// Original Transcript_test.tsx/Reply_test.tsx/gap_test.tsx: M1 entry cases.
// Tools are U5; non-M1 entries, mouse selection, code actions and custom
// mount windows are omitted. Normal Markdown is the framework's widget.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'user/assistant blocks have one gap and fixed gutters at $size',
      (t) async {
        await t.pumpWidget(
          Column(
            children: [
              const TranscriptEntry(model.UserEntry('a', 'hello')),
              TranscriptEntry(
                model.AssistantEntry(
                  'a',
                  TextRun.empty.plus('**reply**\n\n- item'),
                ),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(6), [
          '',
          '› hello',
          '',
          '⏺ reply',
          '',
          '  - item',
        ]);
        expect(t.screen.styleAt(2, 3).isBold, isTrue);
      },
    );
    testWidgets('thoughts fold to Thinking and expand in dim italic at $size', (
      t,
    ) async {
      final entry = model.ThoughtEntry('a', TextRun.empty.plus('  one\ntwo  '));
      await t.pumpWidget(TranscriptEntry(entry), size: size);
      expect(t.screen.lines.take(3), ['', '∴ Thinking…', '']);
      expect(t.screen.styleAt(2, 1).isDim, isTrue);
      expect(t.screen.styleAt(2, 1).isItalic, isTrue);
      await t.pumpWidget(TranscriptEntry(entry, expanded: true), size: size);
      expect(t.screen.lines.take(4), ['', '∴ Thinking…', '  one', '  two']);
    });
    testWidgets(
      'cancelled stopped and permissions attach without a gap at $size',
      (t) async {
        final option = acp.PermissionOption.fromJson({
          'optionId': 'allow',
          'name': 'Allow once',
          'kind': 'allow_once',
        });
        await t.pumpWidget(
          Column(
            children: [
              const TranscriptEntry(model.CancelledEntry('a')),
              const TranscriptEntry(model.StoppedEntry('a', 'max_tokens')),
              TranscriptEntry(
                model.PermissionEntry('a', title: 'Bash ls', option: option),
              ),
              const TranscriptEntry(model.PermissionEntry('a')),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(4), [
          '  ⎿  Interrupted by user',
          '  ⎿  Stopped: max_tokens',
          '  ⎿  Allowed Bash ls · Allow once',
          '  ⎿  Rejected the tool call',
        ]);
        expect(t.screen.styleAt(5, 0).fg, ThemeData.dark().error.fg);
      },
    );
    testWidgets(
      'errors warnings and finished plans keep original words at $size',
      (t) async {
        await t.pumpWidget(
          Column(
            children: [
              const TranscriptEntry(model.ErrorEntry('a', 'failed')),
              const TranscriptEntry(model.WarningEntry('a', 'warning')),
              TranscriptEntry(
                model.FinishedPlanEntry('a', [
                  acp.PlanEntry.fromJson({
                    'content': 'done',
                    'status': 'completed',
                    'priority': 'medium',
                  }),
                ]),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(7), [
          '',
          '⏺ failed',
          '',
          '⏺ warning',
          '',
          '⏺ Plan',
          '  ⎿  ☒ done',
        ]);
        expect(t.screen.styleAt(7, 6).isStrikethrough, isTrue);
      },
    );
    testWidgets('long completed plan steps retain both ends at $size', (
      t,
    ) async {
      final text = '${'A' * 160} end 日本語';
      await t.pumpWidget(
        TranscriptEntry(
          model.FinishedPlanEntry('a', [
            acp.PlanEntry.fromJson({
              'content': text,
              'status': 'completed',
              'priority': 'medium',
            }),
          ]),
        ),
        size: size,
      );
      final budget = (size.width - 10) ~/ 2;
      expect(
        t.screen.lines[2],
        '  ⎿  ☒ ${'A' * budget}...${'A' * (budget - 11)} end 日本語',
      );
      expect(t.screen.lines[3], isEmpty);
      expect(t.screen.styleAt(7 + budget, 2).isStrikethrough, isFalse);
      expect(t.screen.styleAt(7, 2).isStrikethrough, isTrue);
      expect(t.screen.styleAt(10 + budget, 2).isStrikethrough, isTrue);
    });
    testWidgets(
      'assistant strips agent ANSI and settles growing Markdown at $size',
      (t) async {
        final entry = model.AssistantEntry(
          'a',
          TextRun.empty.plus('\x1b[31mreply\x1b[0m\n\n```dart\nfinal x = 1;\n'),
        );
        await t.pumpWidget(TranscriptEntry(entry, growing: true), size: size);
        expect(t.screen, shows('reply'));
        expect(t.screen, shows('final x = 1;'));
        expect(t.screen.styleAt(2, 1).fg, isNot(const IndexedColor(1)));
        await t.pumpWidget(TranscriptEntry(entry), size: size);
        expect(t.screen, shows('final x = 1;'));
      },
    );
  }
}
