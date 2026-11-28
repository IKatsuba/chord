import 'package:chord_tui/src/foundation/playback.dart';
import 'package:test/test.dart';

TerminalRecordingFrame _frame(int ms, String row, [String? label]) =>
    TerminalRecordingFrame(
      at: Duration(milliseconds: ms),
      rows: [row],
      label: label,
    );

final _recording = TerminalRecording(
  cols: 10,
  rows: 1,
  frames: [
    _frame(0, 'a', 'start'),
    _frame(1000, 'b'),
    _frame(2000, 'c', 'typed'),
    _frame(3000, 'd'),
  ],
);

PlaybackState _run(
  List<PlaybackAction> actions, {
  TerminalRecording? recording,
  bool looping = false,
}) => actions.fold(
  const PlaybackState(),
  (state, action) =>
      reducePlayback(recording ?? _recording, state, action, looping: looping),
);

const _ms = Duration(milliseconds: 1);

void main() {
  group('TerminalRecording', () {
    test('reads version 1 JSON', () {
      final recording = TerminalRecording.fromJson({
        'version': 1,
        'cols': 120,
        'rows': 36,
        'frames': [
          {
            'at': 0,
            'rows': ['\x1b[1mchord\x1b[0m'],
            'label': null,
          },
          {
            'at': 1300,
            'rows': ['x'],
            'label': 'typed the prompt',
          },
        ],
      });
      expect((recording.cols, recording.rows), (120, 36));
      expect(recording.frames.last.at, const Duration(milliseconds: 1300));
      expect(recording.frames.last.label, 'typed the prompt');
      expect(recording.frames.first.rows, ['\x1b[1mchord\x1b[0m']);
      expect(recording.steps, [1]);
    });

    test('refuses other versions and malformed frames', () {
      expect(
        () => TerminalRecording.fromJson({
          'version': 2,
          'cols': 1,
          'rows': 1,
          'frames': [],
        }),
        throwsFormatException,
      );
      expect(
        () => TerminalRecording.fromJson({
          'version': 1,
          'cols': 1,
          'rows': 1,
          'frames': [
            {
              'at': 0,
              'rows': [1],
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('with no labels every frame is a step', () {
      final recording = TerminalRecording(
        cols: 1,
        rows: 1,
        frames: [_frame(0, 'a'), _frame(5, 'b')],
      );
      expect(recording.steps, [0, 1]);
    });
  });

  group('reducePlayback', () {
    test('ticks advance a playing recording frame by frame', () {
      final state = _run([
        const PlaybackPlay(),
        const PlaybackTick(Duration(milliseconds: 1500)),
      ]);
      expect(state.position, const Duration(milliseconds: 1500));
      expect(state.frame, 1);
      expect(state.isPlaying, isTrue);
    });

    test('a paused recording does not move', () {
      final state = _run([
        const PlaybackTick(Duration(seconds: 2)),
        const PlaybackPlay(),
        const PlaybackPause(),
        const PlaybackTick(Duration(seconds: 2)),
      ]);
      expect(state, const PlaybackState());
    });

    test('play reaches the end, keeps the last frame and ends', () {
      final state = _run([
        const PlaybackPlay(),
        const PlaybackTick(Duration(seconds: 9)),
      ]);
      expect(
        state,
        const PlaybackState(
          position: Duration(seconds: 3),
          frame: 3,
          isEnded: true,
        ),
      );
    });

    test('looping wraps around instead of ending', () {
      final state = _run([
        const PlaybackPlay(),
        const PlaybackTick(Duration(milliseconds: 3500)),
      ], looping: true);
      expect(state.position, const Duration(milliseconds: 500));
      expect(state.frame, 0);
      expect(state.isPlaying, isTrue);
      expect(state.isEnded, isFalse);
    });

    test('play from the end starts again', () {
      final state = _run([
        const PlaybackPlay(),
        const PlaybackTick(Duration(seconds: 9)),
        const PlaybackPlay(),
      ]);
      expect(state, const PlaybackState(isPlaying: true));
    });

    test('steps move between labelled frames and pause', () {
      var state = _run([const PlaybackPlay(), const PlaybackNextStep()]);
      expect(state.frame, 2);
      expect(state.position, const Duration(seconds: 2));
      expect(state.isPlaying, isFalse);
      state = reducePlayback(_recording, state, const PlaybackNextStep());
      expect(state.frame, 3);
      expect(state.isEnded, isTrue);
      state = reducePlayback(_recording, state, const PlaybackPreviousStep());
      expect(state.frame, 2);
      expect(state.isEnded, isFalse);
      state = reducePlayback(_recording, state, const PlaybackPreviousStep());
      expect(state.frame, 0);
      state = reducePlayback(_recording, state, const PlaybackPreviousStep());
      expect(state.frame, 0);
    });

    test('previous step from inside a step goes to the one before', () {
      final state = _run([
        const PlaybackSeek(Duration(milliseconds: 2500)),
        const PlaybackPreviousStep(),
      ]);
      expect(state.frame, 0);
    });

    test('seek clamps to the recording and keeps whether it plays', () {
      expect(
        _run([const PlaybackSeek(Duration(seconds: -1))]).position,
        Duration.zero,
      );
      final state = _run([
        const PlaybackPlay(),
        const PlaybackSeek(Duration(seconds: 9)),
      ]);
      expect(state.position, const Duration(seconds: 3));
      expect(state.frame, 3);
      expect(state.isPlaying, isTrue);
      expect(
        reducePlayback(_recording, state, const PlaybackTick(_ms)).isEnded,
        isTrue,
      );
    });

    test('restart plays from the beginning', () {
      final state = _run([
        const PlaybackSeek(Duration(seconds: 2)),
        const PlaybackRestart(),
      ]);
      expect(state, const PlaybackState(isPlaying: true));
    });

    test('before the first labelled frame there is no step', () {
      final recording = TerminalRecording(
        cols: 1,
        rows: 1,
        frames: [_frame(0, 'a'), _frame(5, 'b', 'one'), _frame(9, 'c')],
      );
      expect(stepOf(recording, 0), -1);
      expect(stepOf(recording, 1), 0);
      expect(stepOf(recording, 2), 0);
      final state = reducePlayback(
        recording,
        const PlaybackState(),
        const PlaybackNextStep(),
      );
      expect(state.frame, 1);
      expect(
        reducePlayback(recording, state, const PlaybackPreviousStep()).frame,
        0,
      );
    });

    test('a recording with no frames does not move', () {
      const empty = TerminalRecording(cols: 1, rows: 1, frames: []);
      expect(
        _run([
          const PlaybackPlay(),
          const PlaybackTick(Duration(seconds: 1)),
          const PlaybackNextStep(),
        ], recording: empty),
        const PlaybackState(),
      );
      expect(empty.steps, isEmpty);
    });
  });
}
