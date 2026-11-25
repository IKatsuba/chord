// The original's notify watch for forms and links (src/notify.ts): a form
// or link opens a wait while live, the first only, and its answer or
// withdrawal ends it; one asked between turns lasts past a turn.
import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

({Watch watch, List<Wait> waits}) play(List<ConversationEvent> events) {
  var watch = emptyWatch;
  final waits = <Wait>[];
  for (final event in events) {
    final (watch: next, :wait) = watchWaits(watch, event);
    watch = next;
    if (wait != null) waits.add(wait);
  }
  return (watch: watch, waits: waits);
}

ConversationEvent elicited(ElicitationWait wait) =>
    Transcribed(ElicitationRequestedAction('t1', wait));

void main() {
  test('a form, then a link, is one wait; the answers end it', () {
    const form = FormWait('f', 'Set up the deploy target');
    const link = LinkWait('l', 'Sign in', 'https://example.com');
    final asked = play([
      const Connected('s', AgentState.empty),
      const Transcribed(PromptAction('t1', 'form', 0)),
      elicited(form),
      elicited(link),
    ]);
    expect(asked.waits, [const InputAsk('Set up the deploy target')]);
    expect(asked.watch.asking, {'f', 'l'});
    expect(askingNow(asked.watch), const InputAsk('Set up the deploy target'));

    var watch = asked.watch;
    watch = watchWaits(
      watch,
      const Transcribed(
        ElicitationSettledAction('t1', 'f', ElicitationDeclined()),
      ),
    ).watch;
    expect(askingNow(watch), const InputAsk('Sign in', url: true));
    watch = watchWaits(
      watch,
      const Transcribed(
        ElicitationSettledAction('t1', 'l', ElicitationWithdrawn()),
      ),
    ).watch;
    expect(watch.asking, isEmpty);
    expect(watch.asked, isEmpty);
  });

  test('one replayed before the session is live opens no wait; one between '
      'turns lasts', () {
    expect(play([elicited(const FormWait('f', 'Form'))]).waits, isEmpty);
    final between = play([
      const Connected('s', AgentState.empty),
      elicited(const FormWait('f', 'Form').asked(at: 1, between: true)),
    ]);
    expect(between.waits, hasLength(1));
    expect(between.watch.lasting, {'f'});
  });
}
