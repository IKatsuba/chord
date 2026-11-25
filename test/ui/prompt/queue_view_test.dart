import 'package:chord/session/conversation.dart';
import 'package:chord/ui/prompt/queue_view.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('queue keeps oldest text dim and preserves headers at $size', (
      t,
    ) async {
      await t.pumpWidget(
        Queue(
          queue: [
            const QueuedPrompt('1', 'one\ntwo'),
            QueuedPrompt('2', 'head${'x' * 150}tail', afterAnswer: true),
            const QueuedPrompt('3', 'three'),
            const QueuedPrompt('4', 'four'),
          ],
          limit: 3,
        ),
        size: size,
      );
      expect(t.screen.lines.first, ' › one …');
      expect(t.screen.lines[1], contains('after your answer: head'));
      expect(t.screen.lines[1], endsWith('tail'));
      expect(t.screen.lines[2], ' › … +2 more');
      expect(t.screen.styleAt(1, 0), Style.dim);
      expect(t.screen.styleAt(3, 0), Style.dim);
    });
  }
  group('tester U7 queue screen boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'queue preserves Unicode ends and updates to empty at $size',
        (t) async {
          final queue = ValueNotifier<List<QueuedPrompt>>([
            QueuedPrompt('1', '界🙂e\u0301${'x' * 200}TAIL', afterAnswer: true),
            const QueuedPrompt('2', 'second'),
            const QueuedPrompt('3', 'third'),
          ]);
          addTearDown(queue.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: queue,
              builder: (_) => Queue(queue: queue.value, limit: 2),
            ),
            size: size,
          );
          expect(
            t.screen.lines[0],
            startsWith(' › after your answer: 界🙂e\u0301'),
          );
          expect(t.screen.lines[0], endsWith('TAIL'));
          expect(t.screen.lines[1], ' › … +2 more');
          expect(t.screen.styleAt(3, 0), Style.dim);
          queue.value = [];
          await t.pump();
          expect(t.screen.text, '');
          await t.resize(const Size(12, 4));
          queue.value = [const QueuedPrompt('4', 'tiny', afterAnswer: true)];
          await t.pump();
          expect(t.screen.lines.first, startsWith(' › after'));
          expect(t.screen.lines.first, isNot(contains('tiny')));
        },
      );
    }
  });
}
