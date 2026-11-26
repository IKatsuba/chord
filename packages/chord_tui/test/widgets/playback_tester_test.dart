import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/playback.dart' show sliceColumns;
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

TerminalRecording _recording({String first = 'first'}) => TerminalRecording(
  cols: 12,
  rows: 3,
  frames: [
    TerminalRecordingFrame(
      at: Duration.zero,
      rows: [first, 'middle', 'bottom'],
    ),
    const TerminalRecordingFrame(
      at: Duration(seconds: 1),
      rows: ['second', 'middle', 'bottom'],
    ),
    const TerminalRecordingFrame(
      at: Duration(seconds: 2),
      rows: ['last', 'middle', 'bottom'],
    ),
  ],
);

void main() {
  group('tester: Playback geometry and grapheme edges', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(120, 40),
      Size(80, 24),
      Size(43, 37),
    ]) {
      testWidgets('renders and accepts all controls at $size', (t) async {
        final controller = PlaybackController(
          _recording(first: '\x1b[1m界🙂e\u0301\x1b[0m'),
        );
        addTearDown(controller.dispose);
        await t.pumpWidget(Playback(controller, autofocus: true), size: size);
        if (size.width >= 12 && size.height >= 3) {
          expect(t.screen.lines.first, '界🙂e\u0301');
          expect(t.screen.styleAt(0, 0).isBold, isTrue);
        } else if (size == const Size(1, 1)) {
          expect(t.screen.text, '⌄');
        }
        for (final key in [
          'space',
          'space',
          'right',
          'l',
          'left',
          'h',
          'r',
          'space',
          'shift+right',
          'shift+left',
          'shift+down',
          'shift+up',
        ]) {
          await t.press(key);
        }
        expect(t.screen.text, isNot(contains('Error')));
      });
    }

    testWidgets('unbounded axes take the recording size', (t) async {
      final controller = PlaybackController(_recording());
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Row(
          children: [
            Column(children: [Playback(controller)]),
          ],
        ),
      );
      expect(t.screen.lines.take(3), ['first', 'middle', 'bottom']);
    });

    test('every column boundary preserves or blanks complete graphemes', () {
      const span = TextSpan('A界🙂e\u0301Z', style: Style(bold: true));
      const expected = ['A ', '界', '  ', '🙂', ' e\u0301', 'e\u0301Z'];
      for (var start = 0; start < expected.length; start++) {
        final cut = sliceColumns(span, start, 2);
        expect(
          cut.map((s) => s.text).join(),
          expected[start],
          reason: 'column $start',
        );
        expect(cut.every((s) => s.style?.isBold == true), isTrue);
      }
      expect(sliceColumns(span, 0, 0), isEmpty);
    });

    testWidgets('resize clamps pan and restores the top-left when it fits', (
      t,
    ) async {
      final controller = PlaybackController(_recording());
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Playback(controller, autofocus: true),
        size: const Size(5, 2),
      );
      await t.press('shift+right');
      await t.press('shift+down');
      expect(t.screen.lines.first, 'iddl›');
      await t.resize(const Size(120, 40));
      expect(t.screen.lines.take(3), ['first', 'middle', 'bottom']);
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.first, 'first');
      await t.resize(const Size(5, 2));
      expect(t.screen.lines, ['firs›', '⌄⌄⌄⌄⌄']);
    });
  });

  group('tester: Playback focus and listener ownership', () {
    testWidgets('focus leaves and returns before keys work again', (t) async {
      final controller = PlaybackController(_recording());
      final playbackFocus = FocusNode();
      final otherFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(playbackFocus.dispose);
      addTearDown(otherFocus.dispose);
      await t.pumpWidget(
        Column(
          children: [
            Focus(focusNode: otherFocus, child: Text('elsewhere')),
            Expanded(
              child: Playback(
                controller,
                autofocus: true,
                focusNode: playbackFocus,
              ),
            ),
          ],
        ),
      );
      await t.press('right');
      expect(controller.value.frame, 1);
      otherFocus.requestFocus();
      await t.pump();
      await t.press('right');
      expect(controller.value.frame, 1);
      playbackFocus.requestFocus();
      await t.pump();
      await t.press('right');
      expect(controller.value.frame, 2);
    });

    testWidgets('controller replacement detaches the old live controller', (
      t,
    ) async {
      final old = PlaybackController(_recording())..play();
      final next = PlaybackController(_recording(first: 'replacement'));
      addTearDown(old.dispose);
      addTearDown(next.dispose);
      final selected = ValueNotifier(old);
      addTearDown(selected.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: selected,
          builder: (_) => Playback(selected.value, autofocus: true),
        ),
      );
      expect(old.hasListeners, isTrue);
      selected.value = next;
      await t.pump();
      expect(old.hasListeners, isFalse);
      expect(next.hasListeners, isTrue);
      old.seekTo(const Duration(seconds: 2));
      await t.pump();
      expect(t.screen.lines.first, 'replacement');
      next.play();
      await t.pumpWidget(Text('removed'));
      expect(next.hasListeners, isFalse);
      expect(next.value.isPlaying, isTrue);
      expect(old.isDisposed, isFalse);
      await t.pump();
      expect(t.screen.text, 'removed');
    });

    testWidgets(
      'a thousand changes between frames leave the last image and bar',
      (t) async {
        final controller = PlaybackController(_recording());
        addTearDown(controller.dispose);
        await t.pumpWidget(
          Column(
            children: [
              Expanded(child: Playback(controller)),
              PlaybackBar(controller),
            ],
          ),
        );
        for (var i = 0; i < 1000; i++) {
          controller.seekTo(Duration(milliseconds: i * 2));
        }
        controller.seekTo(const Duration(seconds: 2));
        await t.pump();
        expect(t.screen.lines.first, 'last');
        expect(t.screen.lines.last, '❚❚ 0:02 / 0:02 · step 3 of 3');
      },
    );

    test('disposing a playing controller cancels every pending tick', () {
      fakeAsync((async) {
        final controller = PlaybackController(_recording())..play();
        var notifications = 0;
        controller.addListener(() => notifications++);
        async.elapse(const Duration(milliseconds: 500));
        controller.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(notifications, 0);
        expect(async.pendingTimers, isEmpty);
        expect(controller.play, throwsStateError);
      });
    });
  });
}
