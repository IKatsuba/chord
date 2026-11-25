// The background view's refusal that an agent offers no stop, as the
// original's tests/ui/background/state_test.ts has it.
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/background/background.dart' show ItemRef;
import 'package:chord/ui/background/state.dart';
import 'package:chord/ui/background/view.dart' show noStopHint;
import 'package:test/test.dart';

void main() {
  testerLateStopOffer();
  group('a refusal that an agent offers no stop, once it offers one', () {
    const ItemRef a = (key: 1, id: 'a');
    List<BackgroundAction> before(String hint) => [
      const BackgroundOpened(),
      const BackgroundFocused(a),
      const BackgroundStopAsked(a, 't'),
      BackgroundHinted('t', hint),
    ];
    BackgroundView? run(String hint, [ItemRef focus = a]) => [
      ...before(hint),
      BackgroundStopOffered(focus),
    ].fold<BackgroundView?>(null, reduceBackground);

    test('is dropped, and the ❯ stays', () {
      final view = run(noStopHint);

      expect(view?.hint, isNull);
      expect(view?.focus, a);
    });

    test('stays when the offer is for another row', () {
      expect(run(noStopHint, (key: 1, id: 'b'))?.hint, noStopHint);
    });

    test('leaves any other hint where it was', () {
      const hint = 'could not stop: Session not found';

      expect(run(hint)?.hint, hint);
    });

    test('reaches the view through the app state too', () {
      // The window's state carries the view: the original's reduceApp is
      // the port's reduceWindow for these.
      final state = before(noStopHint).fold(
        AppState.starting,
        (state, action) => reduceWindow(state, BackgroundChangedAction(action)),
      );
      expect(state.backgroundView?.hint, noStopHint);

      expect(
        reduceWindow(
          state,
          const BackgroundChangedAction(BackgroundStopOffered(a)),
        ).backgroundView?.hint,
        isNull,
      );
    });
  });
}

void testerLateStopOffer() {
  group('CTUI-83 tester: late stop offer ownership', () {
    test('a reused id in another session keeps its refusal and geometry', () {
      const ref = (key: 2, id: 'shared');
      const view = BackgroundView(
        focus: ref,
        top: 4,
        laid: '80x24',
        over: ['ask'],
        hint: noStopHint,
        detail: ref,
      );
      expect(
        reduceBackground(
          view,
          const BackgroundStopOffered((key: 1, id: 'shared')),
        ),
        same(view),
      );
      final offered = reduceBackground(view, const BackgroundStopOffered(ref))!;
      expect(offered.hint, isNull);
      expect(
        (offered.focus, offered.top, offered.laid, offered.detail),
        (ref, 4, '80x24', ref),
      );
      expect(offered.over, ['ask']);
      expect(reduceBackground(null, const BackgroundStopOffered(ref)), isNull);
    });
  });
}
