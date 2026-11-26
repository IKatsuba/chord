import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/playback.dart' show sliceColumns;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

TerminalRecordingFrame _frame(int ms, List<String> rows, [String? label]) =>
    TerminalRecordingFrame(
      at: Duration(milliseconds: ms),
      rows: rows,
      label: label,
    );

/// Three frames of a 12x3 terminal, the last two labelled steps.
final _recording = TerminalRecording(
  cols: 12,
  rows: 3,
  frames: [
    _frame(0, ['\x1b[1mchord\x1b[0m one', 'row two', 'row three']),
    _frame(1000, ['typed', 'hello', ''], 'typed the prompt'),
    _frame(62000, ['answered', 'the end', 'abcdefghijkl'], 'answered'),
  ],
);

Widget _page(PlaybackController controller, {bool autofocus = true}) => Column(
  children: [
    Expanded(child: Playback(controller, autofocus: autofocus)),
    PlaybackBar(controller),
  ],
);

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('draws the frame from the top left, at $size', (t) async {
      final controller = PlaybackController(_recording);
      addTearDown(controller.dispose);
      await t.pumpWidget(_page(controller), size: size);
      expect(t.screen.lines.take(3), ['chord one', 'row two', 'row three']);
      expect(t.screen.styleAt(0, 0).isBold, isTrue);
      expect(t.screen.styleAt(6, 0).isBold, isFalse);
      // Before the first labelled frame there is no step to name.
      expect(t.screen.lines.last, '❚❚ 0:00 / 1:02');
    });
  }

  testWidgets('steps move by the keys and the bar follows', (t) async {
    final controller = PlaybackController(_recording);
    addTearDown(controller.dispose);
    await t.pumpWidget(_page(controller));
    await t.press('right');
    expect(t.screen.lines.first, 'typed');
    expect(
      t.screen.lines.last,
      '❚❚ 0:01 / 1:02 · step 1 of 2 · typed the prompt',
    );
    await t.press('l');
    expect(t.screen.lines.first, 'answered');
    expect(t.screen.lines.last, '❚❚ 1:02 / 1:02 · step 2 of 2 · answered');
    await t.press('l');
    expect(t.screen.lines.first, 'answered');
    expect(t.screen.lines.last, '■ ended · r restart');
    await t.press('h');
    expect(t.screen.lines.first, 'typed');
    await t.press('left');
    expect(t.screen.lines.first, 'chord one');
    await t.press('r');
    expect(t.screen.lines.first, 'chord one');
    expect(t.screen.lines.last, startsWith('▶ 0:00 / 1:02'));
  });

  testWidgets('space plays, time moves the frames, space pauses', (t) async {
    final quick = TerminalRecording(
      cols: 6,
      rows: 1,
      frames: [
        _frame(0, ['first']),
        _frame(40, ['second']),
        _frame(80, ['third']),
      ],
    );
    final controller = PlaybackController(quick);
    addTearDown(controller.dispose);
    await t.pumpWidget(_page(controller));
    await t.press('space');
    expect(controller.value.isPlaying, isTrue);
    expect(t.screen.lines.last, startsWith('▶ 0:00 / 0:00 · step 1 of 3'));
    await t.pump(const Duration(milliseconds: 60));
    expect(t.screen.lines.first, 'second');
    await t.press('space');
    expect(controller.value.isPlaying, isFalse);
    await t.pump(const Duration(milliseconds: 80));
    expect(t.screen.lines.first, 'second');
    await t.press('space');
    await t.pump(const Duration(milliseconds: 100));
    expect(t.screen.lines.first, 'third');
    expect(t.screen.lines.last, '■ ended · r restart');
  });

  testWidgets('a looping controller plays again from the start', (t) async {
    final quick = TerminalRecording(
      cols: 6,
      rows: 1,
      frames: [
        _frame(0, ['first']),
        _frame(30, ['second']),
      ],
    );
    final controller = PlaybackController(quick, looping: true)..play();
    addTearDown(controller.dispose);
    await t.pumpWidget(_page(controller));
    await t.pump(const Duration(milliseconds: 100));
    expect(controller.value.isEnded, isFalse);
    expect(controller.value.isPlaying, isTrue);
  });

  testWidgets('keys do nothing while it is not focused', (t) async {
    final controller = PlaybackController(_recording);
    addTearDown(controller.dispose);
    await t.pumpWidget(
      Column(
        children: [
          Focus(autofocus: true, child: Text('elsewhere')),
          Expanded(child: _page(controller, autofocus: false)),
        ],
      ),
    );
    await t.press('right');
    await t.press('space');
    expect(controller.value.frame, 0);
    expect(controller.value.isPlaying, isFalse);
  });

  testWidgets('an empty recording draws nothing and says so', (t) async {
    final controller = PlaybackController(
      const TerminalRecording(cols: 10, rows: 2, frames: []),
    );
    addTearDown(controller.dispose);
    await t.pumpWidget(_page(controller));
    await t.press('space');
    expect(t.screen.lines.first, '');
    expect(t.screen.lines.last, 'no frames');
  });

  testWidgets('a clipped recording marks its cut edges and pans', (t) async {
    final controller = PlaybackController(_recording)
      ..seekTo(const Duration(seconds: 62));
    addTearDown(controller.dispose);
    await t.pumpWidget(_page(controller), size: const Size(8, 3));
    expect(t.screen.lines, ['answere›', '⌄⌄⌄⌄⌄⌄⌄⌄', '❚❚ 1:02']);
    final dim = t.screen.styleAt(7, 0);
    expect(dim.isDim, isTrue);
    expect(t.screen.styleAt(0, 1).isDim, isTrue);
    await t.press('shift+down');
    expect(t.screen.lines.first, 'the end›');
    await t.press('shift+right');
    await t.press('shift+right');
    await t.press('shift+right');
    await t.press('shift+right');
    await t.press('shift+right');
    // Panned to the right edge: nothing is cut there any more.
    expect(t.screen.lines.first, 'end');
    // Panned to the bottom: the last row shows, no ⌄; further does nothing.
    expect(t.screen.lines.take(2), ['end', 'efghijkl']);
    await t.press('shift+down');
    expect(t.screen.lines.take(2), ['end', 'efghijkl']);
    await t.press('shift+left');
    await t.press('shift+up');
    // A short row keeps the › in the last column.
    expect(t.screen.lines.take(2), ['wered  ›', '⌄⌄⌄⌄⌄⌄⌄⌄']);
  });

  testWidgets('key help lists what the keys do', (t) async {
    final controller = PlaybackController(_recording);
    addTearDown(controller.dispose);
    await t.pumpWidget(
      Column(
        children: [
          Expanded(child: Playback(controller, autofocus: true)),
          const KeyHelp(),
        ],
      ),
      size: const Size(120, 40),
    );
    for (final action in [
      'Play or pause',
      'Next step',
      'Previous step',
      'Restart',
      'Pan right',
    ]) {
      expect(t.screen, shows(action));
    }
  });

  test('sliceColumns keeps styles and blanks cut wide characters', () {
    final cut = sliceColumns(
      TextSpan(
        '',
        children: [
          const TextSpan('ab', style: Style(bold: true)),
          const TextSpan('中文c'),
        ],
      ),
      1,
      3,
    );
    expect(cut.map((span) => span.text), ['b', '中']);
    expect(cut.first.style, const Style(bold: true));
    expect(
      sliceColumns(const TextSpan('a中b'), 2, 2).map((s) => s.text).join(),
      ' b',
    );
  });
}
