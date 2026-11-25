import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a one-row transcript retains wrapped tool extents at $size', (
      tester,
    ) async {
      final scroll = ScrollController(follow: Follow.bottom);
      final height = ValueNotifier(2);
      addTearDown(scroll.dispose);
      addTearDown(height.dispose);
      final transcript = model.Transcript(
        entries: [
          const model.UserEntry('earlier', 'Previous reply'),
          model.ToolEntry(
            'request',
            model.ToolCall(
              'write',
              title: 'mcp__files__write_file',
              rawInput: {'content': 'word ' * 140},
              status: 'pending',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: height,
          builder: (_) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: height.value,
              child: Transcript(transcript: transcript, controller: scroll),
            ),
          ),
        ),
        size: size,
      );
      final toolRows = scroll.itemRows(1);
      final content = scroll.contentRows;
      expect(toolRows, greaterThan(3));
      expect(content, toolRows + 2);
      final bottom = scroll.offset;
      scroll.lineUp();
      await tester.pump();
      expect(scroll.offset, bottom - 1);
      expect(tester.screen.lines[1], contains('2 lines below'));

      // OpenTUI's one-row viewport collapses this margined tool to one
      // row (opentui#1739). Keep the full block available for scrolling.
      for (final rows in [1, 3, 2]) {
        height.value = rows;
        await tester.pump();
        expect(scroll.itemRows(1), toolRows);
        expect(scroll.contentRows, content);
        expect(scroll.offset, bottom - 1);
      }
      scroll.toTop();
      await tester.pump();
      expect(tester.screen.lines[1], contains('lines below'));
      height.value = 3;
      await tester.pump();
      expect(tester.screen, shows('Previous reply'));
      scroll.toBottom();
      await tester.pump();
      expect(scroll.isFollowing, isTrue);
      expect(scroll.itemRows(1), toolRows);
    });
  }
}
