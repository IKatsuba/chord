// The `agents` scenario's two messages to `parser`, as the original's
// conversation.ts `tell` and `#enqueue` answer them on an agent that takes
// no steering, as the fake by default: `queued` while the recipient runs a
// turn, `sent` once it is idle. Whether the second `→ to @parser` says
// `· queued` turns only on whether parser's turn for the first message
// has ended when the second arrives: the original's capture
// (docs/design/evidence/CTUI-35/children/orig-120x40-agents.txt) found it
// ended, the port's found it running; both answer as the state was.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/tasks.dart' show wrapMessage;
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

const _main = MessageFrom('main', reachable: true);

const _first =
    'I changed how a string at the end of a line is read. Run the parser '
    'tests now and tell me only what fails.';
const _second =
    'The printer is fixed too; run the whole parser suite once more.';

/// Parser, on an agent that steers none, running its first turn with the
/// first message told behind it, then that message's turn begun.
({Conversation conversation, ScriptedSession session}) _parser(
  FakeAsync async,
) {
  late ScriptedSession session;
  final conversation = Conversation(({
    required onTraffic,
    required cancellationToken,
  }) {
    session = ScriptedSession()..steering = false;
    return Future.value(session);
  })..start();
  async.flushMicrotasks();
  conversation.send('agentchild');
  async.flushMicrotasks();
  // The first message reaches parser while its first turn runs.
  expect(conversation.tell(_main, _first), Delivery.queued);
  session.turns.first.answer();
  async.elapse(const Duration(seconds: 5));
  // Parser has heard it: the turn the scenario's gate waits for.
  expect(session.turns.last.text, wrapMessage(_main, _first));
  return (conversation: conversation, session: session);
}

void main() {
  test('the second message while parser still runs the first one\'s turn '
      'is queued, as the original answers a busy recipient', () {
    fakeAsync((async) {
      final parser = _parser(async);
      expect(parser.conversation.tell(_main, _second), Delivery.queued);
    });
  });

  test('the second message once that turn has ended is sent, as the '
      'original\'s capture shows it', () {
    fakeAsync((async) {
      final parser = _parser(async);
      parser.session.turns.last.answer();
      async.elapse(const Duration(seconds: 5));
      expect(parser.conversation.tell(_main, _second), Delivery.sent);
      async.flushMicrotasks();
      expect(parser.session.turns.last.text, wrapMessage(_main, _second));
    });
  });
}
