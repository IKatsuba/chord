import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/steering_replay.dart';

void main() {
  _testerReplayResizeBoundaries();
  testWidgets(
    '32-column app inset preserves the original space before notice ellipsis',
    (t) async {
      const entry = model.SelfStartedEntry('own', alone: false);
      final source = entrySelectionSource(
        entry,
        id: 'notice',
        revision: 1,
        width: 30,
      );
      for (final bound in [false, true]) {
        await t.pumpWidget(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: TranscriptEntry(
              entry,
              selectionSource: bound ? source : null,
            ),
          ),
          size: const Size(32, 10),
        );
        expect(t.screen.lines.first, '   ⎿  Interrupted · the agent …');
      }
    },
  );
  for (final size in const [
    Size(120, 40),
    Size(80, 24),
    Size(32, 10),
    Size(5, 4),
  ]) {
    for (final alone in [true, false]) {
      testWidgets(
        'self-started notice is dim end-CUT with matching source alone=$alone $size',
        (t) async {
          final entry = model.SelfStartedEntry('own', alone: alone);
          final source = entrySelectionSource(
            entry,
            id: 'notice',
            revision: 1,
            width: size.width,
          );
          expect(source.codeBlocks, isEmpty);
          List<String>? plain;
          for (final bound in [false, true]) {
            await t.pumpWidget(
              TranscriptEntry(entry, selectionSource: bound ? source : null),
              size: size,
            );
            final row = alone ? 1 : 0;
            expect(
              t.screen.lines[row].startsWith(alone ? '⏺ ' : '  ⎿'),
              isTrue,
            );
            if (size.width > 5) {
              expect(
                t.screen.lines[row].substring(alone ? 2 : 5),
                startsWith('Int'),
              );
              expect(t.screen.styleAt(alone ? 2 : 5, row).isDim, isTrue);
            }
            expect(
              t.screen.lines.skip(row + 1).every((line) => line.trim().isEmpty),
              isTrue,
            );
            if (plain != null) expect(t.screen.lines, plain);
            plain = List.of(t.screen.lines);
          }
        },
      );
    }
  }
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets(
      'a raw leading assistant paragraph space is dropped as the original $size',
      (t) async {
        final entry = reduceTranscript(
          model.Transcript.empty,
          model.UpdateAction(
            'own',
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': ' Late work 1.'},
            }),
          ),
        ).entries.single;
        final source = entrySelectionSource(
          entry,
          id: 'raw-leading',
          revision: 1,
          width: size.width,
        );
        for (final bound in [false, true]) {
          await t.pumpWidget(
            TranscriptEntry(entry, selectionSource: bound ? source : null),
            size: size,
          );
          expect(t.screen.lines[1], '⏺ Late work 1.');
        }
      },
    );

    for (final alone in [true, false]) {
      testWidgets(
        'notice source and mounted furniture stay excluded from copy alone=$alone $size',
        (t) async {
          final controller = SelectionController();
          final entry = model.SelfStartedEntry('own', alone: alone);
          final source = entrySelectionSource(
            entry,
            id: 'notice',
            revision: 1,
            width: size.width,
          );
          await t.pumpWidget(
            SelectionArea(
              controller: controller,
              selectionStyle: const Style(inverse: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('before'),
                  TranscriptEntry(entry, selectionSource: source),
                  Text('after'),
                ],
              ),
            ),
            size: size,
          );
          await t.mouse(
            const MouseEvent(
              MouseEventKind.press,
              position: Offset(0, 0),
              button: MouseButton.primary,
            ),
          );
          await t.mouse(
            MouseEvent(
              MouseEventKind.move,
              position: Offset(4, alone ? 3 : 2),
              button: MouseButton.primary,
            ),
          );
          await t.mouse(
            MouseEvent(
              MouseEventKind.release,
              position: Offset(4, alone ? 3 : 2),
              button: MouseButton.primary,
            ),
          );
          final text = controller.snapshot()!.text;
          expect(text, contains('before'));
          expect(text, contains('after'));
          expect(text, isNot(contains('Interrupted')));
          controller.dispose();
        },
      );
    }

    testWidgets(
      'late Unicode work stays above notice with distinct next prompt $size',
      (t) async {
        var state = reduceTranscript(
          model.Transcript.empty,
          const model.SelfStartedAction('own'),
        );
        state = reduceTranscript(
          state,
          model.UpdateAction(
            'own',
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text': 'Late 界😀 é 👩‍💻\u001b[31m text\u001b[0m',
              },
            }),
          ),
        );
        state = reduceTranscript(
          state,
          const model.PromptAction('next', 'Next personal prompt', 1),
        );
        final controller = ScrollController();
        final sources = TranscriptSources(Object())..retain(state.entries);
        await t.pumpWidget(
          Transcript(
            transcript: state,
            controller: controller,
            bindKeys: false,
            selectionSources: sources,
            selectionNamespace: sources.namespace,
          ),
          size: size,
        );
        final rows = t.screen.lines;
        final work = rows.indexWhere((line) => line.contains('Late 界😀'));
        final close = rows.indexWhere((line) => line.contains('Interrupted'));
        final next = rows.indexWhere(
          (line) => line.contains('Next personal prompt'),
        );
        expect(work, greaterThanOrEqualTo(0));
        expect(close, work + 1);
        expect(next, greaterThan(close));
        expect(rows[close].indexOf('Interrupted'), 5);
        controller.dispose();
      },
    );
    testWidgets(
      'agent-free replay fixture toggles alone, late, source and next $size',
      (t) async {
        await t.pumpWidget(
          const SteeringReplayFixture(alone: true),
          size: size,
        );
        expect(t.screen.text, contains('Interrupted'));
        expect(t.screen.text, isNot(contains('line below')));
        await t.press('ctrl+n');
        expect(t.screen.text, contains('Late work 1.'));
        expect(t.screen.text, isNot(contains('line below')));
        final beforeSource = List.of(t.screen.lines);
        await t.press('ctrl+s');
        expect(t.screen.lines, beforeSource);
        await t.press('ctrl+p');
        expect(t.screen.text, contains('Queued message goes as the next turn'));
        await t.press('ctrl+r');
        expect(t.screen.text, isNot(contains('Late work 1.')));
        await t.press('ctrl+t');
        expect(t.screen.text, contains('Visible self-started work'));
      },
    );
  }
}

void _testerReplayResizeBoundaries() {
  for (final alone in [true, false]) {
    testWidgets(
      'tester: bound notice matches direct rendering across zero and narrow resize alone=$alone',
      (t) async {
        final entry = model.SelfStartedEntry('own', alone: alone);
        for (final size in const [
          Size(120, 40),
          Size(1, 4),
          Size(0, 0),
          Size(80, 24),
          Size(32, 10),
          Size(120, 40),
        ]) {
          List<String>? direct;
          for (final bound in [false, true]) {
            final source = entrySelectionSource(
              entry,
              id: 'stable-notice',
              revision: 1,
              width: size.width,
            );
            await t.pumpWidget(
              TranscriptEntry(entry, selectionSource: bound ? source : null),
              size: size,
            );
            if (direct != null) expect(t.screen.lines, direct);
            direct = List.of(t.screen.lines);
            expect(source.codeBlocks, isEmpty);
            if (size.width >= 80) {
              expect(t.screen.text, contains('Interrupted'));
            }
            if (size.width == 0) expect(t.screen.text.trim(), isEmpty);
          }
        }
      },
    );
  }
}
