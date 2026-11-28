import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const PlaybackExample());

/// A short recorded terminal session played from the top left, with its
/// bar and keys under it; a window narrower than its 60 columns clips it,
/// and Shift+arrows pan. Ctrl+Q quits.
class PlaybackExample extends StatefulWidget {
  /// The example.
  const PlaybackExample({super.key});

  @override
  State<PlaybackExample> createState() => _PlaybackExampleState();
}

/// Six frames of a 60x12 shell: a command typed, run and answered.
TerminalRecording exampleRecording() {
  const prompt = '\x1b[32m~/project\x1b[0m \x1b[1m\$\x1b[0m';
  List<String> screen(List<String> rows) => [
    ...rows,
    for (var i = rows.length; i < 12; i++) '',
  ];
  TerminalRecordingFrame frame(int ms, List<String> rows, [String? label]) =>
      TerminalRecordingFrame(
        at: Duration(milliseconds: ms),
        rows: screen(rows),
        label: label,
      );
  return TerminalRecording(
    cols: 60,
    rows: 12,
    frames: [
      frame(0, [prompt]),
      frame(800, ['$prompt dart test'], 'typed the command'),
      frame(1600, [
        '$prompt dart test',
        '\x1b[2m00:01 +12: loading test/widgets_test.dart\x1b[0m',
      ], 'started the tests'),
      frame(2600, [
        '$prompt dart test',
        '\x1b[2m00:02 +48: test/widgets_test.dart: layout\x1b[0m',
      ]),
      frame(3600, [
        '$prompt dart test',
        '\x1b[32m00:03 +96: All tests passed!\x1b[0m',
        prompt,
      ], 'all tests passed'),
      frame(6000, [
        '$prompt dart test',
        '\x1b[32m00:03 +96: All tests passed!\x1b[0m',
        '$prompt \x1b[7m \x1b[0m',
      ]),
    ],
  );
}

class _PlaybackExampleState extends State<PlaybackExample> {
  final _controller = PlaybackController(exampleRecording())..play();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Playback(_controller, autofocus: true)),
        PlaybackBar(_controller),
        const KeyHelp(),
      ],
    ),
  );
}
