import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord/ui/transcript/transcript.dart' as ui;
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test('asksFor checks every permission by tool call id', () {
    final turn = AwaitingPermission('t', 0, [
      const PermissionWait('a', toolCallId: 'first'),
      const PermissionWait('b', toolCallId: 'second'),
    ]);
    expect(asksFor(turn, 'first'), isTrue);
    expect(asksFor(turn, 'second'), isTrue);
    expect(asksFor(turn, 'unknown'), isFalse);
    expect(asksFor(const Idle(), 'first'), isFalse);
    expect(asksFor(const Working('t', 0), 'first'), isFalse);
  });

  test('reviewed permission suppresses fallback waiting with no output', () {
    for (final status in ['pending', 'in_progress']) {
      final call = ToolCall(
        'a',
        status: status,
        review: const PermissionReview('caution', 'Review this.'),
      );
      expect(summary(call, false, asked: true).lines, isEmpty);
      expect(summary(call, false).lines, [
        status == 'pending' ? 'Waiting…' : 'Running…',
      ]);
      expect(toneOf(call, asked: true), Tone.pending);
    }
  });

  test(
    'unreviewed pending permission prefixes waiting before existing output',
    () {
      final content = acp.ToolCallContent.fromJson({
        'type': 'content',
        'content': {'type': 'text', 'text': 'one\ntwo\nthree\nfour\n'},
      });
      final call = ToolCall(
        'a',
        status: 'in_progress',
        kind: 'read',
        content: [content],
      );
      final view = summary(call, false, asked: true);
      expect(view.lines, ['Waiting…', 'one', 'two', 'three']);
      expect(view.hidden, 1);
      final reviewed = ToolCall(
        'b',
        status: 'pending',
        content: [content],
        review: const PermissionReview('caution', 'Review.'),
      );
      expect(summary(reviewed, true, asked: true).lines, [
        'one',
        'two',
        'three',
        'four',
      ]);
      expect(summary(const ToolCall('a'), false, asked: true).lines, [
        'Waiting…',
      ]);
    },
  );

  testWidgets(
    'transcript forwards asked and invalidates the same call when permission arrives',
    (t) async {
      const entry = ToolEntry(
        't',
        ToolCall(
          'a',
          title: 'Reviewed call',
          status: 'pending',
          review: PermissionReview('caution', 'Review.'),
        ),
      );
      final state = ValueNotifier<Transcript>(
        const Transcript(entries: [entry], turn: Working('t', 0)),
      );
      final scroll = ScrollController();
      await t.pumpWidget(
        ListenableBuilder(
          listenable: state,
          builder: (context) =>
              ui.Transcript(transcript: state.value, controller: scroll),
        ),
      );
      expect(t.screen, shows('Waiting…'));
      state.value = const Transcript(
        entries: [entry],
        turn: AwaitingPermission('t', 0, [
          PermissionWait('p', toolCallId: 'a'),
        ]),
      );
      await t.pump();
      expect(t.screen, shows('Reviewed: caution'));
      expect(t.screen, isNot(shows('Waiting…')));
      t.dispose();
      scroll.dispose();
      state.dispose();
    },
  );

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('review row is sufficient for a waiting call at $size', (
      t,
    ) async {
      await t.pumpWidget(
        const Tool(
          ToolCall(
            'a',
            title: 'Run a reviewed action',
            status: 'pending',
            review: PermissionReview('caution', 'Fixture review.'),
          ),
          expanded: false,
          asked: true,
        ),
        size: size,
      );
      expect(t.screen, shows('Reviewed: caution'));
      expect(t.screen, isNot(shows('Waiting…')));
    });
  }
}
