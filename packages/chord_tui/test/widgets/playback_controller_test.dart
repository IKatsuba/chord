import 'package:chord_tui/chord_tui.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

TerminalRecordingFrame _frame(int ms) => TerminalRecordingFrame(
  at: Duration(milliseconds: ms),
  rows: ['at $ms'],
);

final _recording = TerminalRecording(
  cols: 6,
  rows: 1,
  frames: [_frame(0), _frame(1000), _frame(3000)],
);

const _ms = Duration(milliseconds: 1);

void main() {
  test('pause between frames keeps the time played', () {
    fakeAsync((async) {
      final controller = PlaybackController(_recording)..play();
      async.elapse(_ms * 900);
      controller.pause();
      expect(controller.value.position, _ms * 900);
      expect(controller.value.frame, 0);
      async.elapse(const Duration(seconds: 5));
      expect(controller.value.position, _ms * 900);
      controller.play();
      async.elapse(_ms * 100);
      expect(controller.value.frame, 1);
      expect(controller.value.position, _ms * 1000);
      controller.dispose();
    });
  });

  test('play again before the next tick does not hold time back', () {
    fakeAsync((async) {
      final controller = PlaybackController(_recording)..play();
      for (var i = 0; i < 4; i++) {
        async.elapse(_ms * 500);
        controller.play();
      }
      expect(controller.value.position, const Duration(seconds: 2));
      expect(controller.value.frame, 1);
      controller.dispose();
    });
  });

  test('time passes into steps and seeks before they apply', () {
    fakeAsync((async) {
      final controller = PlaybackController(_recording)..play();
      async.elapse(_ms * 1500);
      controller.seekTo(_ms * 2500);
      expect(controller.value.position, _ms * 2500);
      expect(controller.value.isPlaying, isTrue);
      async.elapse(_ms * 500);
      expect(controller.value.frame, 2);
      expect(controller.value.isEnded, isTrue);
      controller.dispose();
    });
  });

  test('listeners hear each frame and each second while playing', () {
    fakeAsync((async) {
      final controller = PlaybackController(_recording);
      final heard = <Duration>[];
      controller.addListener(() => heard.add(controller.value.position));
      controller.play();
      async.elapse(const Duration(seconds: 4));
      expect(heard, [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      ]);
      expect(controller.value.isEnded, isTrue);
      controller.dispose();
    });
  });

  test('a looping controller keeps playing past the end', () {
    fakeAsync((async) {
      final controller = PlaybackController(_recording, looping: true)..play();
      async.elapse(_ms * 3500);
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.position, _ms * 500);
      controller.dispose();
    });
  });
}
