// The background view's state, as the original's
// tests/ui/background/state_test.ts has it for monitors and tasks.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/background/background.dart' show ItemRef;
import 'package:chord/ui/background/state.dart';
import 'package:test/test.dart';

BackgroundView? _run(List<BackgroundAction> actions, [BackgroundView? from]) =>
    actions.fold(from, reduceBackground);

/// What [view] holds, to compare.
Map<String, Object?>? _held(BackgroundView? view) => view == null
    ? null
    : {
        'focus': ?view.focus,
        'top': ?view.top,
        'laid': ?view.laid,
        if (view.over.isNotEmpty) 'over': view.over,
        'hint': ?view.hint,
        'stopping': ?view.stopping,
        'detail': ?view.detail,
      };

void main() {
  const ItemRef a = (key: 1, id: 'a'), b = (key: 1, id: 'b');
  const hint = 'could not stop: Session not found';

  test("a stop's hint is said only for the stop x last asked for, while the "
      '❯ has stayed on its row since', () {
    BackgroundAction asked(String token) => BackgroundStopAsked(a, token);
    BackgroundAction refused(String token) => BackgroundHinted(token, hint);
    final opened = <BackgroundAction>[
      const BackgroundOpened(),
      const BackgroundFocused(a),
      asked('t1'),
    ];
    expect(_run([...opened, refused('t1')])?.hint, hint);
    // Kept while the ❯ stays; gone once it moves.
    expect(
      _run([...opened, refused('t1'), const BackgroundFocused(a)])?.hint,
      hint,
    );
    expect(
      _held(_run([...opened, refused('t1'), const BackgroundFocused(b)])),
      {'focus': b},
    );
    // An answer after the ❯ left, even if it came back, or after the view
    // closed and opened again, is not said.
    expect(
      _run([
        ...opened,
        const BackgroundFocused(b),
        const BackgroundFocused(a),
        refused('t1'),
      ])?.hint,
      isNull,
    );
    expect(
      _run([
        ...opened,
        const BackgroundClosed(),
        const BackgroundOpened(),
        const BackgroundFocused(a),
        refused('t1'),
      ])?.hint,
      isNull,
    );
    // Nor is an earlier stop's once a later one on the same row was asked.
    expect(
      _run([
        ...opened,
        const BackgroundFocused(b),
        const BackgroundFocused(a),
        asked('t2'),
        refused('t1'),
      ])?.hint,
      isNull,
    );
    expect(_run([refused('t1')]), isNull);
  });

  test('an old refusal cannot disarm a newer attempt and the new hint clears '
      'on owner change', () {
    const ItemRef focus = (key: 1, id: 'same');
    final state = _run([
      const BackgroundOpened(),
      const BackgroundFocused(focus),
      const BackgroundStopAsked(focus, 'old'),
      const BackgroundStopAsked(focus, 'new'),
    ]);
    final late = reduceBackground(
      state,
      const BackgroundHinted('old', 'old refusal'),
    );
    expect(late, same(state));
    expect(late?.stopping?.token, 'new');
    final refused = reduceBackground(
      late,
      const BackgroundHinted('new', 'new refusal'),
    );
    expect(refused?.hint, 'new refusal');
    expect(refused?.stopping, isNull);
    expect(
      reduceBackground(
        refused,
        const BackgroundFocused((key: 2, id: 'same')),
      )?.hint,
      isNull,
    );
  });

  group('the view over requests already waiting', () {
    const asking = Transcript(
      turn: AwaitingPermission('t', 0, [PermissionWait('p1')]),
    );

    test('opened over a permission waiting, it is shown and holds the keys; '
        'one that arrives once it is open hides it until answered', () {
      final view = _run([
        const BackgroundOpened(['p1']),
      ]);
      expect(backgroundShown(view, asking), isTrue);
      expect(askedIds(asking), ['p1']);
      const more = Transcript(
        turn: AwaitingPermission('t', 0, [
          PermissionWait('p1'),
          PermissionWait('p2'),
        ]),
        asking: [LinkWait('e1', 'Sign in', 'u')],
      );
      expect(askedIds(more), ['p1', 'p2', 'e1']);
      expect(backgroundShown(view, more), isFalse);
      // Answered, the view is back as it was.
      expect(backgroundShown(view, asking), isTrue);
      expect(backgroundShown(null, Transcript.empty), isFalse);
      expect(
        backgroundShown(_run([const BackgroundOpened()]), asking),
        isFalse,
      );
    });

    test('the list under the prompt has the keys only while the view is '
        'not open', () {
      expect(agentsHaveKeys(agentsFocus: true), isTrue);
      expect(agentsHaveKeys(agentsFocus: false), isFalse);
      expect(
        agentsHaveKeys(agentsFocus: true, view: const BackgroundView()),
        isFalse,
      );
    });
  });

  test('another size clears where the frame was scrolled to, keeping the ❯ '
      'on its item', () {
    const ItemRef focus = (key: 1, id: 't1');
    final resized = _run([
      const BackgroundOpened(),
      const BackgroundFocused(focus, top: 7, laid: '76x6'),
      const BackgroundResized(),
    ]);
    expect(_held(resized), {'focus': focus});
    // A move after it is laid out anew.
    expect(_held(reduceBackground(resized, const BackgroundFocused(focus))), {
      'focus': focus,
    });
    // Nothing to clear leaves it as it was.
    final unmoved = _run([const BackgroundOpened()]);
    expect(reduceBackground(unmoved, const BackgroundResized()), same(unmoved));
  });

  test("a tall row's place stays with the ❯ until a move says", () {
    final view = _run([
      const BackgroundOpened(),
      const BackgroundFocused(a, top: 3, laid: '76x6'),
      const BackgroundFocused(a),
    ]);
    expect([view?.top, view?.laid], [3, '76x6']);
    expect(reduceBackground(view, const BackgroundFocused(b))?.top, isNull);
  });

  test("a monitor's detail: opened, the ❯ and the detail are on its item; "
      '↑ ↓ take the detail with the ❯; closed, the ❯ stays', () {
    const ItemRef m1 = (key: 1, id: 'm1'), m2 = (key: 1, id: 'm2');
    final detail = _run([
      const BackgroundOpened(),
      const BackgroundFocused(m1, top: 2, laid: '76x6'),
      const BackgroundDetailOpened(m1),
    ]);
    expect(_held(detail), {'focus': m1, 'detail': m1});
    final moved = reduceBackground(detail, const BackgroundFocused(m2));
    expect([moved?.focus, moved?.detail], [m2, m2]);
    final back = reduceBackground(moved, const BackgroundDetailClosed());
    expect([back?.focus, back?.detail], [m2, null]);
    // On the rows, ↑ ↓ open nothing, and closing a detail none is open
    // changes nothing.
    expect(reduceBackground(back, const BackgroundFocused(m1))?.detail, isNull);
    expect(reduceBackground(back, const BackgroundDetailClosed()), same(back));
    expect(reduceBackground(null, const BackgroundDetailOpened(m1)), isNull);
  });

  group('CTUI-36 tester: closed view and plan requests', () {
    test('late actions cannot reopen a closed view', () {
      for (final action in const <BackgroundAction>[
        BackgroundClosed(),
        BackgroundResized(),
        BackgroundFocused(a),
        BackgroundStopAsked(a, 'old'),
        BackgroundHinted('old', 'late'),
        BackgroundDetailOpened(a),
        BackgroundDetailClosed(),
      ]) {
        expect(reduceBackground(null, action), isNull);
      }
    });

    test('new unanswered plans hide the view and settled plans release it', () {
      const wait = PlanWait('plan', PlanAgent.cursor, toolCallId: 'call');
      const pending = Transcript(planAsks: [PlanAsk('t', wait)]);
      const settled = Transcript(
        planAsks: [PlanAsk('t', wait, answer: PlanAccepted())],
      );
      const view = BackgroundView(focus: a, detail: a);
      expect(askedIds(pending), ['plan']);
      expect(backgroundShown(view, pending), isFalse);
      expect(askedIds(settled), isEmpty);
      expect(backgroundShown(view, settled), isTrue);
      expect(
        backgroundShown(const BackgroundView(over: ['plan']), pending),
        isTrue,
      );
      expect(view.detail, a);
    });
  });
}
