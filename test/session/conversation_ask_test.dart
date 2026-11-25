// chord's own question in the permission box, as the original's
// Conversation.ask: asked during a turn, answered by the option picked, Esc
// picking the reject option, and withdrawn by its signal, the turn's end, an
// interrupt, a clear or the close; with no turn, never asked.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

final _options = [
  acp.PermissionOption.fromJson({
    'optionId': 'yes',
    'name': 'Yes, in ~/s.json',
    'kind': 'allow_once',
  }),
  acp.PermissionOption.fromJson({
    'optionId': 'no',
    'name': 'No, tell fake what to change',
    'kind': 'reject_once',
  }),
];

const _save = SaveBox(
  question: 'Set theme?',
  escape: 'tell fake what to change',
  asked: 'call-1',
);

/// A scripted conversation in a turn, under [async].
Scripted _inTurn(FakeAsync async) {
  final s = Scripted();
  s.conversation.start();
  async.flushMicrotasks();
  s.conversation.send('go');
  async.flushMicrotasks();
  return s;
}

/// [s]'s question asked with [signal], what it settles to kept in [into].
void _ask(Scripted s, List<Object?> into, [CancellationToken? signal]) => s
    .conversation
    .ask(
      title: 'Settings(theme)',
      detail: 'In ~/s.json: not set becomes "dark".',
      options: _options,
      save: _save,
      signal: signal ?? CancellationToken(),
    )
    .then(into.add);

List<PermissionWait> _asked(Scripted s) => [
  for (final event in s.events)
    if (event case Transcribed(action: PermissionRequestedAction(:final wait)))
      wait,
];

List<PermissionAnswer> _settled(Scripted s) => [
  for (final event in s.events)
    if (event case Transcribed(action: PermissionSettledAction(:final answer)))
      answer,
];

void main() {
  test('asked in a turn, it is drawn as a request with its box, and the '
      'option picked answers it', () {
    fakeAsync((async) {
      final s = _inTurn(async);
      final settled = <Object?>[];
      _ask(s, settled);
      async.flushMicrotasks();
      final wait = _asked(s).single;
      expect(
        (wait.title, wait.detail, wait.save, wait.options),
        (
          'Settings(theme)',
          'In ~/s.json: not set becomes "dark".',
          _save,
          _options,
        ),
      );
      // A client asked through ACP sees the detail as the call's content.
      final request = s.conversation.permissionRequest(wait.id)!;
      expect(request.toolCall.toolCallId, wait.id);
      expect(request.raw.toJson()['toolCall'], {
        'toolCallId': wait.id,
        'title': 'Settings(theme)',
        'content': [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': 'In ~/s.json: not set becomes "dark".',
            },
          },
        ],
      });
      expect(settled, isEmpty);
      s.conversation.choose(wait.id, 'yes');
      async.flushMicrotasks();
      expect(settled, ['yes']);
      expect(_settled(s).single, isA<Chosen>());
    });
  });

  test('Esc picks the reject option', () {
    fakeAsync((async) {
      final s = _inTurn(async);
      final settled = <Object?>[];
      _ask(s, settled);
      async.flushMicrotasks();
      s.conversation.reject(_asked(s).single.id);
      async.flushMicrotasks();
      expect(settled, ['no']);
    });
  });

  test('with no turn, or once closing, nothing is asked', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      final settled = <Object?>[];
      _ask(s, settled);
      async.flushMicrotasks();
      expect(settled, [null]);
      expect(_asked(s), isEmpty);
    });
  });

  test('a cancelled signal never asks; one cancelled while asked withdraws '
      'it', () {
    fakeAsync((async) {
      final s = _inTurn(async);
      final settled = <Object?>[];
      _ask(s, settled, CancellationToken()..cancel());
      async.flushMicrotasks();
      expect(settled, [null]);
      expect(_asked(s), isEmpty);
      final signal = CancellationToken();
      _ask(s, settled, signal);
      async.flushMicrotasks();
      signal.cancel();
      async.flushMicrotasks();
      expect(settled, [null, null]);
      expect(_settled(s).single, isA<Withdrawn>());
      expect(s.conversation.permissionRequest(_asked(s).single.id), isNull);
    });
  });

  test("a signal kept past its question holds nothing of it, answered or "
      "withdrawn, and its later cancel touches nothing", () {
    fakeAsync((async) {
      final s = _inTurn(async);
      final settled = <Object?>[];
      final kept = CancellationToken();
      _ask(s, settled, kept);
      async.flushMicrotasks();
      expect(kept.hasCancellables, isTrue);
      s.conversation.choose(_asked(s).single.id, 'yes');
      async.flushMicrotasks();
      expect(kept.hasCancellables, isFalse);
      // Withdrawn by the turn's end rather than the signal.
      final other = CancellationToken();
      _ask(s, settled, other);
      async.flushMicrotasks();
      s.session.turns.single.answer();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(other.hasCancellables, isFalse);
      final events = s.events.length;
      kept.cancel();
      other.cancel();
      async.flushMicrotasks();
      expect(settled, ['yes', null]);
      expect(s.events.length, events);
      expect(_settled(s).whereType<Withdrawn>(), hasLength(1));
    });
  });

  for (final (how, end) in <(String, void Function(Scripted s))>[
    ("the turn's end", (s) => s.session.turns.single.answer()),
    ('an interrupt', (s) => s.conversation.interrupt()),
    ('a clear', (s) => s.conversation.clear().ignore()),
    ('the close', (s) => s.conversation.close().ignore()),
  ]) {
    test('$how withdraws it, answered by nobody', () {
      fakeAsync((async) {
        final s = _inTurn(async);
        final settled = <Object?>[];
        _ask(s, settled);
        async.flushMicrotasks();
        end(s);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(settled, [null]);
      });
    });
  }
}
