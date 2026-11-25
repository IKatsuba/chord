import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test(
    'wheel delegates exactly to existing line scrolling and follows bounds',
    () {
      for (final scroll in const [
        ScrollState(),
        ScrollState(content: 100, view: 20, following: true),
        ScrollState(content: 100, view: 20, top: 17, news: true),
      ]) {
        final state = AppState(scroll: scroll, draft: 'draft');
        for (final action in const [WheeledAction.up(), WheeledAction.down()]) {
          final wheel = reduceWindow(state, action);
          final key = reduceWindow(
            state,
            TranscriptScrolledAction(action.step),
          );
          expect(wheel.scroll, key.scroll);
          expect(wheel.draft, state.draft);
          expect(wheel.transcript, same(state.transcript));
        }
      }
      const state = AppState(
        scroll: ScrollState(content: 100, view: 20, following: true),
      );
      final back = reduceWindow(state, const WheeledAction.up());
      expect(back.scroll.offset, 79);
      expect(back.scroll.following, isFalse);
      final bottom = reduceWindow(back, const WheeledAction.down());
      expect(bottom.scroll.following, isTrue);
      expect(bottom.scroll.offset, 80);
    },
  );
  test(
    'closing is idempotent, survives unrelated changes and Connected resets it',
    () {
      const state = AppState(
        scroll: ScrollState(content: 100, view: 20, following: true),
      );
      final closing = reduceApp(state, const Closing());
      expect(closing.closing, isTrue);
      expect(reduceApp(closing, const Closing()), same(closing));
      for (final action in const [WheeledAction.up(), WheeledAction.down()]) {
        expect(reduceWindow(closing, action), same(closing));
      }
      expect(
        reduceWindow(closing, const ToggleExpandedAction()).closing,
        isTrue,
      );
      expect(reduceApp(closing, const Queued('t', 'later')).closing, isTrue);
      final connected = reduceApp(
        closing,
        const Connected('fresh', AgentState.empty),
      );
      expect(connected.closing, isFalse);
      expect(
        reduceWindow(connected, const WheeledAction.up()).scroll.following,
        isFalse,
      );
    },
  );
}
