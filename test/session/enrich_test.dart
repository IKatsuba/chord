// The original's enrich_test.ts, the chain and the wire M1 keeps. Left for
// later: a recalled past (resume), the adapter's name and subagents' names,
// agent state, usage and costs on the wire.
import 'package:chord/session/enrich.dart';
import 'package:test/test.dart';

Message _update(String sessionId, Message update) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'sessionId': sessionId, 'update': update},
};

void main() {
  test('each enricher runs in turn over what the one before it made', () {
    List<Message> twice(Message m, Wire _) => [
      {...m, 'n': 1},
      {...m, 'n': 2},
    ];
    List<Message> tagged(Message m, Wire _) => [
      {...m, 'tag': 'x${m['n']}'},
    ];
    List<Message> dropOne(Message m, Wire _) => m['n'] == 1 ? [] : [m];

    expect(enrich([twice, tagged, dropOne], {'a': true}, Wire.empty), [
      {'a': true, 'n': 2, 'tag': 'x2'},
    ]);
    expect(enrich(const [], {'a': true}, Wire.empty), [
      {'a': true},
    ]);
  });

  test("the wire keeps each of chord's requests until the agent answers it, "
      'with a result or an error', () {
    var wire = heardFromChord(Wire.empty, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'session/new',
      'params': {'cwd': '/'},
    });
    wire = heardFromChord(wire, {
      'jsonrpc': '2.0',
      'id': 'x',
      'method': 'session/prompt',
      'params': 'not an object',
    });
    // A notification and an answer of chord's ask nothing.
    wire = heardFromChord(wire, {
      'jsonrpc': '2.0',
      'method': 'session/cancel',
      'params': {},
    });
    wire = heardFromChord(wire, {'jsonrpc': '2.0', 'id': 9, 'result': {}});

    expect(wire.asked.keys, ['1', 'x']);
    expect(wire.asked['1']!.method, 'session/new');
    expect(wire.asked['1']!.params, {'cwd': '/'});
    expect(wire.asked['x']!.params, isEmpty);

    wire = heardFromAgent(wire, {'jsonrpc': '2.0', 'id': 1, 'result': {}});
    wire = heardFromAgent(wire, {
      'jsonrpc': '2.0',
      'id': 'x',
      'error': {'code': -32603, 'message': 'no'},
    });

    expect(wire.asked, isEmpty);

    // A stray answer, or a request of the agent's under the same id, moves
    // nothing.
    final same = heardFromAgent(wire, {
      'jsonrpc': '2.0',
      'id': 1,
      'result': {},
    });

    expect(identical(same, wire), isTrue);
  });

  test("the wire keeps each session's tool calls apart, their title, kind "
      'and whether the content is their own', () {
    var wire = Wire.empty;

    for (final (sessionId, update) in <(String, Message)>[
      (
        'a',
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c',
          'title': 'Read',
          'kind': 'read',
          'content': [
            {'type': 'content'},
          ],
        },
      ),
      (
        'b',
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c',
          'title': 'Run',
          'content': [
            {'type': 'content'},
          ],
          '_meta': {
            filledKey: ['content'],
          },
        },
      ),
      (
        'a',
        {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c',
          'title': 'Read 2',
        },
      ),
      (
        'b',
        {'sessionUpdate': 'tool_call_update', 'toolCallId': 'c', 'content': []},
      ),
      ('a', {'sessionUpdate': 'agent_message_chunk'}),
      ('a', {'sessionUpdate': 'tool_call_update', 'toolCallId': 7}),
    ]) {
      wire = heardFromAgent(wire, _update(sessionId, update));
    }

    final a = wire.tools['a']!['c']!;
    final b = wire.tools['b']!['c']!;

    expect([a.title, a.kind, a.ownContent], ['Read 2', 'read', true]);
    expect([b.title, b.kind, b.ownContent], ['Run', null, false]);
    expect(wire.tools['a']!.keys, ['c']);
  });

  test('a message is read as a notification by its shape alone', () {
    final (sessionId, update) = notificationOf(
      _update('s', {'sessionUpdate': 'something_new', 'x': 1}),
    )!;

    expect(sessionId, 's');
    expect(update, {'sessionUpdate': 'something_new', 'x': 1});

    for (final message in <Message>[
      {
        ..._update('s', {'sessionUpdate': 'plan'}),
        'id': 1,
      },
      {'jsonrpc': '2.0', 'method': 'session/other', 'params': {}},
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 3,
          'update': {'sessionUpdate': 'plan'},
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's',
          'update': {'sessionUpdate': 3},
        },
      },
      {'jsonrpc': '2.0', 'method': 'session/update', 'params': 'x'},
    ]) {
      expect(notificationOf(message), isNull, reason: '$message');
    }
  });

  test('marking what chord filled keeps what was there, and names each '
      'field once', () {
    expect(markFilled(null, ['title']), {
      filledKey: ['title'],
    });
    expect(
      markFilled(
        {
          'own': true,
          filledKey: ['title', 3],
        },
        ['title', 'kind'],
      ),
      {
        'own': true,
        filledKey: ['title', 'kind'],
      },
    );
    expect(filledIn({'_meta': 'not an object'}), isEmpty);
  });

  test('the relay passes what chord says on as it is, and folds what the '
      'chain made, not what the agent sent', () {
    final heard = <Message>[];
    final relay = enricherRelay([
      (m, wire) {
        heard.add(m);
        final update = notificationOf(m)?.$2;
        // Names the call, as an enricher fills in a title.
        return update == null || update['toolCallId'] != 'c'
            ? [m]
            : [
                _update('s', {...update, 'title': 'Named'}),
              ];
      },
      (m, wire) => [
        if (notificationOf(m) case (
          _,
          final update,
        ) when update['sessionUpdate'] == 'tool_call_update')
          _update('s', {...update, 'known': wire.tools['s']?['c']?.title})
        else
          m,
      ],
    ]);
    final request = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'session/prompt',
      'params': {'sessionId': 's'},
    };

    expect(identical(relay.fromChord(request).single, request), isTrue);
    relay.fromAgent(
      _update('s', {'sessionUpdate': 'tool_call', 'toolCallId': 'c'}),
    );

    final out = relay.fromAgent(
      _update('s', {'sessionUpdate': 'tool_call_update', 'toolCallId': 'd'}),
    );

    expect(notificationOf(out.single)!.$2['known'], 'Named');
    expect(heard, hasLength(2));
  });

  group('tester: wire snapshot boundaries', () {
    test(
      'a tool update keeps old snapshots and other session facts identical',
      () {
        final first = heardFromAgent(
          Wire.empty,
          _update('a', {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'c',
            'title': 'first',
          }),
        );
        final both = heardFromAgent(
          first,
          _update('b', {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'c',
            'title': 'other',
          }),
        );
        final changed = heardFromAgent(
          both,
          _update('a', {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'c',
            'title': 'next',
          }),
        );
        expect(Wire.empty.tools, isEmpty);
        expect(first.tools.keys, ['a']);
        expect(first.tools['a']!['c']!.title, 'first');
        expect(both.tools['a']!['c']!.title, 'first');
        expect(changed.tools['a']!['c']!.title, 'next');
        expect(identical(changed.tools['b'], both.tools['b']), isTrue);
        expect(identical(changed.asked, both.asked), isTrue);
        final pending = heardFromChord(changed, {
          'id': 'request',
          'method': 'session/new',
          'params': {},
        });
        final answered = heardFromAgent(pending, {
          'id': 'request',
          'result': {},
        });
        expect(pending.asked.keys, ['request']);
        expect(answered.asked, isEmpty);
        expect(identical(answered.tools, changed.tools), isTrue);
      },
    );
  });
}
