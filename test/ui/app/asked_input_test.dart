// Which request is on screen and holds the keys, as the original's
// busy.ts askedInput and dialogs/state.ts betweenAsked say it: a
// permission or plan before a form or link, and one asked between turns
// held until the person takes the keys into it.
import 'package:chord/ui/app/state.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

const _form = FormWait('f', 'Form');

AppState stateOf(Transcript transcript) => AppState(transcript: transcript);

void main() {
  test('a form is on screen once no permission or open plan waits', () {
    expect(askedInput(const Transcript(asking: [_form])), same(_form));
    expect(
      askedInput(
        const Transcript(
          asking: [_form],
          turn: AwaitingPermission('t', 0, [PermissionWait('p')]),
        ),
      ),
      isNull,
    );
    expect(
      askedInput(
        const Transcript(
          asking: [_form],
          planAsks: [
            PlanAsk('t', PlanWait('plan', PlanAgent.cursor, toolCallId: 'c')),
          ],
        ),
      ),
      isNull,
    );
  });

  test('one asked in the turn has the keys at once', () {
    final state = stateOf(
      const Transcript(asking: [_form], turn: Working('t', 0)),
    );
    expect(betweenAsked(state.transcript), isNull);
    expect(heldBack(state), isFalse);
    expect(requestHasKeys(state), isTrue);
  });

  test('one asked between turns is held until ctrl+x a takes the keys', () {
    final between = _form.asked(at: 1, between: true);
    final state = stateOf(Transcript(asking: [between]));
    expect(betweenAsked(state.transcript), 'f');
    expect(heldBack(state), isTrue);
    expect(requestHasKeys(state), isFalse);
    final attended = attendRequest(state);
    expect(heldBack(attended), isFalse);
    expect(requestHasKeys(attended), isTrue);
    expect(attendRequest(attended), same(attended));
  });

  test('a permission between turns is still held as before', () {
    final state = stateOf(
      const Transcript(
        turn: AwaitingPermission('t', 0, [PermissionWait('p')], between: true),
      ),
    );
    expect(heldBack(state), isTrue);
    expect(heldBack(attendRequest(state)), isFalse);
  });
}
