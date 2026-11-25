import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/plan_box.dart';
import 'package:chord/ui/dialogs/plan_scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-183: paged Note ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('Unicode Note keeps its paged row across focus and resize '
          'and detaches its controller at $size', (t) async {
        final scroll = PlanNoteScroll();
        final focus = FocusNode(), outside = FocusNode();
        addTearDown(scroll.dispose);
        addTearDown(focus.dispose);
        addTearDown(outside.dispose);
        var shape = openPlanShape;
        await t.pumpWidget(
          Column(
            children: [
              PlanBox(
                wait: const PlanWait(
                  'tester',
                  PlanAgent.cursor,
                  toolCallId: 'c',
                ),
                agent: 'fake',
                onAnswer: (_) {},
                windowRows: size.height,
                maxRows: size.height - 1,
                focusNode: focus,
                scroll: scroll,
                onShape: (next) => shape = next,
              ),
              Focus(focusNode: outside, child: Text('outside')),
            ],
          ),
          size: size,
        );
        focus.requestFocus();
        await t.press('down down');
        await t.paste(
          List.generate(
            160,
            (i) => 'row$i stays unchanged 界👩‍💻e\u0301',
          ).join(' '),
        );
        final note = shape.state.note;
        expect(scroll.overflows, isTrue);
        scroll.step(ScrollStep.top);
        await t.pump();
        expect(t.screen.text, contains('Note  row0'));
        outside.requestFocus();
        await t.pump();
        focus.requestFocus();
        await t.resize(const Size(60, 20));
        await t.resize(size);
        expect(t.screen.text, contains('Note  row0'));
        expect(shape.state.note, note);
        await t.type('!');
        expect(t.screen.text, contains('row159'));
        expect(shape.state.note, '$note!');
        await t.pumpWidget(const SizedBox(), size: size);
        // A controller supplied by the caller remains usable after removal.
        scroll.step(ScrollStep.top);
        scroll.follow();
        await t.pump();
        expect(t.screen.text.trim(), isEmpty);
      });
    }
  });
}
