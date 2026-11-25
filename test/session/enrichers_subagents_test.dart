// The original's tests/session/enrichers_test.ts for subagentShape and
// tests/session/enrich_test.ts for claudeSubagentName: the adapters' draft
// shape read as ACP's subagent_update, and Claude's subagents named by their
// title, by who the adapter is.
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:test/test.dart';

/// What [relay] makes of [update] sent for session `s`, the updates alone.
List<Object?> draft(EnricherRelay relay, Map<String, Object?> update) => [
  for (final message in relay.fromAgent({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': 's', 'update': update},
  }))
    (message['params'] as Map)['update'],
];

void main() {
  test("the adapters' subagent_spawned reads as ACP's subagent_update, with "
      'the rest of the draft kept', () {
    expect(
      draft(enricherRelay([subagentShape]), {
        'sessionUpdate': 'subagent_spawned',
        'subagentSessionId': 'child-1',
        'name': 'Find the session layer',
        'task': 'Find where chord routes updates.',
        'prompt': [
          {'type': 'text', 'text': 'Find where chord routes updates.'},
        ],
        'capabilities': <String, Object?>{},
        '_meta': {
          'claudeCode': {'parentToolUseId': 'tool-1'},
        },
      }),
      [
        {
          'sessionUpdate': 'subagent_update',
          'sessionId': 'child-1',
          'title': 'Find the session layer',
          'description': 'Find where chord routes updates.',
          'capabilities': <String, Object?>{},
          '_meta': {
            'claudeCode': {'parentToolUseId': 'tool-1'},
            subagentDraftKey: {
              'sessionUpdate': 'subagent_spawned',
              'prompt': [
                {'type': 'text', 'text': 'Find where chord routes updates.'},
              ],
            },
          },
        },
      ],
    );
  });

  test("the adapters' subagent_state_update reads as a subagent_update "
      'carrying its state', () {
    for (final state in ['completed', 'failed', 'cancelled', 'disconnected']) {
      expect(
        draft(enricherRelay([subagentShape]), {
          'sessionUpdate': 'subagent_state_update',
          'subagentSessionId': 'child-1',
          'state': state,
        }),
        [
          {
            'sessionUpdate': 'subagent_update',
            'sessionId': 'child-1',
            'state': {'state': state},
            '_meta': {
              subagentDraftKey: {'sessionUpdate': 'subagent_state_update'},
            },
          },
        ],
      );
    }
  });

  test('a field of the draft ACP has no place for, or of the wrong type, is '
      'kept, not lost', () {
    expect(
      draft(enricherRelay([subagentShape]), {
        'sessionUpdate': 'subagent_spawned',
        'subagentSessionId': 'child-1',
        'name': 7,
        'task': 'Look.',
        'model': 'haiku',
      }),
      [
        {
          'sessionUpdate': 'subagent_update',
          'sessionId': 'child-1',
          'description': 'Look.',
          '_meta': {
            subagentDraftKey: {
              'sessionUpdate': 'subagent_spawned',
              'name': 7,
              'model': 'haiku',
            },
          },
        },
      ],
    );
  });

  test("an agent's own subagent_update, and a draft with no subagent named, "
      'pass as they came', () {
    const own = {
      'sessionUpdate': 'subagent_update',
      'sessionId': 'child-1',
      'title': 'Look',
      'state': {'state': 'idle'},
    };
    expect(draft(enricherRelay([subagentShape]), own), [own]);
    expect(
      draft(enricherRelay([subagentShape]), {
        'sessionUpdate': 'subagent_spawned',
        'name': 'Look',
      }),
      [
        {'sessionUpdate': 'subagent_spawned', 'name': 'Look'},
      ],
    );
  });

  group(
    "Claude's subagents are named by their title, by who the adapter is",
    () {
      const update = {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's',
          'update': {
            'sessionUpdate': 'subagent_update',
            'sessionId': 'a',
            'title': 'A',
          },
        },
      };
      Object? named(EnricherRelay relay) {
        final [out] = relay.fromAgent(update);
        final meta = ((out['params'] as Map)['update'] as Map)['_meta'];
        return meta is Map ? meta[namedByTitleKey] : null;
      }

      EnricherRelay after(Object? result) {
        final relay = enricherRelay(m1Enrichers);
        relay.fromChord({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{},
        });
        final answer = {'jsonrpc': '2.0', 'id': 1, 'result': result};
        expect(relay.fromAgent(answer), [answer]);
        return relay;
      }

      test("the adapter's own name marks it, whatever command ran it", () {
        expect(
          named(
            after({
              'protocolVersion': 1,
              'agentInfo': {'name': claudeAdapter, 'version': '0'},
            }),
          ),
          isTrue,
        );
      });

      test('a malformed answer to initialize passes as it is, and marks '
          'nothing', () {
        for (final result in [
          null,
          'nope',
          7,
          <String, Object?>{},
          {'agentInfo': null},
          {'agentInfo': 'x'},
          {
            'agentInfo': {'name': 7},
          },
        ]) {
          expect(named(after(result)), isNull);
        }
      });

      test('another name, or none, leaves it', () {
        expect(
          named(
            after({
              'protocolVersion': 1,
              'agentInfo': {'name': 'codex-acp', 'version': '0'},
            }),
          ),
          isNull,
        );
        expect(named(after({'protocolVersion': 1})), isNull);
      });
    },
  );
}
