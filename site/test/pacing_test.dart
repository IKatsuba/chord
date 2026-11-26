import 'package:chord_site/pacing.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

TerminalRecordingFrame _frame(int ms, [String? label]) =>
    TerminalRecordingFrame(
      at: Duration(milliseconds: ms),
      rows: ['at $ms'],
      label: label,
    );

List<int> _times(TerminalRecording r) => [
  for (final f in r.frames) f.at.inMilliseconds,
];

void main() {
  test('a step frame holds 1.5 s, and the rest move by as much', () {
    final recording = TerminalRecording(
      cols: 1,
      rows: 1,
      frames: [
        _frame(0),
        _frame(200, 'typed hello'),
        _frame(400, 'enter'),
        _frame(700),
        _frame(1000),
      ],
    );
    final out = paced(recording);
    expect(_times(out), [0, 200, 1700, 3200, 3500]);
    expect(
      [for (final f in out.frames) f.label],
      [null, 'typed hello', 'enter', null, null],
    );
    expect(out.frames[2].rows, ['at 400']);
    expect((out.cols, out.rows), (1, 1));
  });

  test('a step already held long enough, and the last frame, stay put', () {
    final recording = TerminalRecording(
      cols: 1,
      rows: 1,
      frames: [_frame(0, 'start'), _frame(2000), _frame(2100, 'end')],
    );
    expect(_times(paced(recording)), [0, 2000, 2100]);
  });

  test('unlabelled frames keep their own gaps', () {
    final recording = TerminalRecording(
      cols: 1,
      rows: 1,
      frames: [_frame(0), _frame(100), _frame(250)],
    );
    expect(_times(paced(recording)), [0, 100, 250]);
  });
}
