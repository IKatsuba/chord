// The walk with an agent's kept drafts (CHD-493 U10, CTUI-35 I3): ↑ shows
// the newest kept draft, then older ones, then the prompts sent; ↓ walks
// back through them to the draft the walk began on. The prompts are the
// window's, the place in the walk each agent's own.
import 'package:chord/ui/prompt/history.dart';
import 'package:test/test.dart';

void main() {
  final sent = recorded(recorded(const History(), 'one'), 'two');
  const kept = ['kept old', 'kept new'];

  test('older shows the newest kept draft, then older, then prompts', () {
    final first = older(sent, '', kept)!;
    expect((first.text, first.kept, first.history.index), ('kept new', 1, 3));
    final second = older(first.history, first.text, kept)!;
    expect((second.text, second.kept), ('kept old', 0));
    final third = older(second.history, second.text, kept)!;
    expect((third.text, third.kept), ('two', null));
    final fourth = older(third.history, third.text, kept)!;
    expect((fourth.text, fourth.kept), ('one', null));
    expect(older(fourth.history, fourth.text, kept), isNull);
  });

  test('newer walks back through the kept drafts to the walk\'s draft', () {
    var step = older(sent, 'typed', kept)!;
    step = older(step.history, step.text, kept)!;
    step = older(step.history, step.text, kept)!;
    expect(step.text, 'two');
    step = newer(step.history, kept)!;
    expect((step.text, step.kept), ('kept old', 0));
    step = newer(step.history, kept)!;
    expect((step.text, step.kept), ('kept new', 1));
    step = newer(step.history, kept)!;
    expect((step.text, step.kept, step.history.index), ('typed', null, null));
    expect(newer(step.history, kept), isNull);
  });

  test('a place past the kept drafts there are stands at the draft', () {
    // Two were kept when the walk stood on the newest; one was taken since.
    final walk = older(sent, 'typed', kept)!.history;
    final step = newer(walk, const ['kept old'])!;
    expect((step.text, step.history.index), ('typed', null));
    expect(older(walk, '', const ['kept old'])!.text, 'kept old');
  });

  test('a kept draft shown never walks from any line', () {
    final step = older(sent, '', kept)!;
    expect(walking(step.history, step.text), isFalse);
    final prompt = older(older(step.history, '', kept)!.history, '', kept)!;
    expect(walking(prompt.history, 'two'), isTrue);
  });

  test(
    'an agent\'s place is kept apart from the prompts every agent shares',
    () {
      final onKept = older(sent, 'mine', kept)!.history;
      final walk = walkOf(onKept)!;
      expect((walk.prompt, walk.kept, walk.draft), (null, 1, 'mine'));
      // Another agent sends a prompt: this agent still stands on its draft.
      final more = recorded(sent, 'three');
      final back = walkedIn(more, walk);
      expect((back.index, back.draft), (4, 'mine'));
      expect(older(back, '', kept)!.text, 'kept old');
      final onPrompt = older(older(onKept, '', kept)!.history, '', kept)!;
      expect(walkOf(onPrompt.history)!.prompt, 1);
      expect(walkedIn(more, walkOf(onPrompt.history)).index, 1);
      expect(walkOf(sent), isNull);
      expect(walkedIn(more, null).index, isNull);
    },
  );
}
