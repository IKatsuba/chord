// The draft's images in the window's state, from the original's
// src/ui/prompt/state.ts and src/ui/app/state.ts (images_added,
// paste_failed, images_sent, queued, queue_withdrawn, cleared).
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart';
import 'package:chord/ui/prompt/images.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

PastedImage image(int id) =>
    (id: id, mediaType: 'image/png', data: 'data-$id', bytes: 4);

void main() {
  test('images added are held by number, the count the highest given', () {
    var state = reduceWindow(
      const AppState(),
      ImagesAddedAction([image(1), image(3)]),
    );
    expect(state.images.map((i) => i.id), [1, 3]);
    expect(state.imageCount, 3);
    // One added again replaces the one of its number.
    state = reduceWindow(state, ImagesAddedAction([image(1)]));
    expect(state.images.map((i) => i.id), [3, 1]);
    expect(state.imageCount, 3);
    expect(reduceWindow(state, const ImagesAddedAction([])), same(state));
  });

  test('a sent prompt takes the images, but for those a waiting draft '
      'names', () {
    final held = reduceWindow(
      const AppState(),
      ImagesAddedAction([image(1), image(2)]),
    );
    expect(reduceWindow(held, const ImagesSentAction()).images, isEmpty);
    expect(
      reduceWindow(
        held,
        const ImagesSentAction('still [Image #2]'),
      ).images.map((i) => i.id),
      [2],
    );
    // The count stays, so no later image takes a number given out.
    expect(reduceWindow(held, const ImagesSentAction()).imageCount, 2);
  });

  test('a paste that found nothing is said until the draft is touched', () {
    final failed = reduceWindow(
      const AppState(),
      const PasteFailedAction('No image in the clipboard'),
    );
    expect(failed.pasteFailed, 'No image in the clipboard');
    expect(
      reduceWindow(failed, const DraftEditedAction('x', 1)).pasteFailed,
      isNull,
    );
    expect(
      reduceWindow(failed, const DraftClearedAction()).pasteFailed,
      isNull,
    );
    expect(
      reduceWindow(failed, ImagesAddedAction([image(1)])).pasteFailed,
      isNull,
    );
  });

  test('"not started yet" goes once the agent starts or fails to, and is '
      'not said after', () {
    const starting = AppState(start: StartState(phase: StartPhase.starting));
    final said = reduceWindow(
      starting,
      const PasteFailedAction('fake has not started yet', untilStarted: true),
    );
    expect(said.pasteFailed, 'fake has not started yet');
    expect(
      reduceApp(said, const Connected('s', AgentState.empty)).pasteFailed,
      isNull,
    );
    expect(reduceApp(said, const ConnectFailed('nope')).pasteFailed, isNull);
    // Any other note stays past the start.
    final other = reduceWindow(
      starting,
      const PasteFailedAction('No image in the clipboard'),
    );
    expect(
      reduceApp(other, const Connected('s', AgentState.empty)).pasteFailed,
      'No image in the clipboard',
    );
    // Come after the start: not so any longer.
    const up = AppState(start: StartState(phase: StartPhase.connected));
    expect(
      reduceWindow(
        up,
        const PasteFailedAction('fake has not started yet', untilStarted: true),
      ),
      same(up),
    );
  });

  test('a queued prompt takes the images it names, and a withdrawal gives '
      'them back with their placeholders', () {
    final held = reduceWindow(
      const AppState(),
      ImagesAddedAction([image(1), image(2)]),
    );
    var state = reduceApp(held, const Queued('t1', 'look [Image #2]'));
    expect(state.queue.single.images.map((i) => i.id), [2]);
    state = reduceWindow(state, const ImagesSentAction());
    expect(state.images, isEmpty);
    // Told again, it keeps what it took.
    state = reduceApp(
      state,
      const Queued('t1', 'look [Image #2]', taken: true),
    );
    expect(state.queue.single.images.map((i) => i.id), [2]);
    state = reduceApp(state, QueueWithdrawn([state.queue.single]));
    expect(state.queue, isEmpty);
    expect(state.images.map((i) => i.id), [2]);
    // A steer out with the agent took its images as it went.
    final steer = reduceApp(
      held,
      const Queued('t2', 'and [Image #1]', steering: true),
    );
    expect(steer.queue.single.images, isEmpty);
  });

  test('/clear keeps the draft with its images', () {
    final held = reduceWindow(
      const AppState(draft: '[Image #1] ', cursor: 11),
      ImagesAddedAction([image(1)]),
    );
    final cleared = reduceApp(held, const Cleared());
    expect(cleared.images.map((i) => i.id), [1]);
    expect(cleared.imageCount, 1);
  });

  test('a prompt sent with images brings them back when recalled', () {
    var history = recordedWith(const History(), 'see [Image #1]', [image(1)]);
    history = recorded(history, 'plain');
    expect(recalledImages(history, 'see [Image #1]').map((i) => i.id), [1]);
    expect(recalledImages(history, 'plain'), isEmpty);
    // The walk keeps them.
    final walked = older(history, '')!;
    expect(recalledImages(walked.history, 'see [Image #1]').map((i) => i.id), [
      1,
    ]);
    // Sent again without them, it brings none.
    history = recordedWith(history, 'see [Image #1]', const []);
    expect(recalledImages(history, 'see [Image #1]'), isEmpty);
  });

  group('tester: image state ownership', () {
    test(
      'history snapshots the supplied image list across walks and recordings',
      () {
        final supplied = [image(1)];
        final first = recordedWith(const History(), '[Image #1]', supplied);
        supplied.clear();
        expect(recalledImages(first, '[Image #1]'), [image(1)]);
        final walk = older(first, 'unsent')!;
        expect(recalledImages(newer(walk.history)!.history, '[Image #1]'), [
          image(1),
        ]);
        final next = recorded(first, '[Image #1]');
        expect(recalledImages(next, '[Image #1]'), isEmpty);
        expect(recalledImages(first, '[Image #1]'), [image(1)]);
      },
    );

    test('withdrawing one queued prompt restores only its images', () {
      var state = reduceWindow(
        const AppState(),
        ImagesAddedAction([image(1), image(2)]),
      );
      state = reduceApp(state, const Queued('a', '[Image #1]'));
      state = reduceApp(state, const Queued('b', '[Image #2]'));
      state = reduceWindow(state, const ImagesSentAction());
      final before = state;
      state = reduceApp(state, QueueWithdrawn([state.queue.first]));
      expect(state.images, [image(1)]);
      expect(state.imageCount, 2);
      expect(state.queue.single.turnId, 'b');
      expect(state.queue.single.images, [image(2)]);
      expect(before.images, isEmpty);
      expect(before.queue, hasLength(2));
    });
  });
}
