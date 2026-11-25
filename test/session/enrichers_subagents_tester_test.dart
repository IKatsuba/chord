import 'dart:convert';

import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:test/test.dart';

Message _message(Message update) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'sessionId': 'parent', 'update': update, 'other': 'kept'},
};
Message _update(EnricherRelay relay, Message update) =>
    (relay.fromAgent(_message(update)).single['params'] as Map)['update']
        as Message;

void _initialize(EnricherRelay relay, Object? name, {bool error = false}) {
  relay.fromChord({
    'jsonrpc': '2.0',
    'method': 'initialize',
    'id': 'init',
    'params': <String, Object?>{},
  });
  relay.fromAgent({
    'jsonrpc': '2.0',
    'id': 'init',
    'result': {
      'agentInfo': {'name': name},
    },
    if (error) 'error': {'code': -1, 'message': 'failed'},
  });
}

const _native = <String, Object?>{
  'sessionUpdate': 'subagent_update',
  'sessionId': 'child',
  'title': 'Agent',
};

void main() {
  group('tester subagent enricher boundaries', () {
    test(
      'draft normalizes before Claude naming and preserves every unrelated field',
      () {
        final relay = enricherRelay(m1Enrichers);
        _initialize(relay, claudeAdapter);
        final input = _message({
          'sessionUpdate': 'subagent_spawned',
          'subagentSessionId': 'child',
          'name': '界🙂e\u0301',
          'task': 'task',
          'state': {'bad': 'shape'},
          'capabilities': 7,
          'prompt': ['raw'],
          '_meta': {'adapter': 'kept', namedByTitleKey: false},
        });
        final before = jsonEncode(input);
        final result = relay.fromAgent(input).single;
        expect((result['params'] as Map)['other'], 'kept');
        expect((result['params'] as Map)['update'], {
          'sessionUpdate': 'subagent_update',
          'sessionId': 'child',
          'title': '界🙂e\u0301',
          'description': 'task',
          '_meta': {
            'adapter': 'kept',
            namedByTitleKey: true,
            subagentDraftKey: {
              'sessionUpdate': 'subagent_spawned',
              'state': {'bad': 'shape'},
              'capabilities': 7,
              'prompt': ['raw'],
            },
          },
        });
        expect(jsonEncode(input), before);
      },
    );

    test(
      'native updates remain identical without a Claude adapter and draft transforms once',
      () {
        final relay = enricherRelay([subagentShape]);
        final message = _message(_native);
        expect(relay.fromAgent(message).single, same(message));
        final normalized = relay
            .fromAgent(
              _message({
                'sessionUpdate': 'subagent_state_update',
                'subagentSessionId': 'child',
                'state': 'working',
                'unknown': null,
              }),
            )
            .single;
        expect(relay.fromAgent(normalized).single, same(normalized));
        expect(((normalized['params'] as Map)['update'] as Map)['_meta'], {
          subagentDraftKey: {
            'sessionUpdate': 'subagent_state_update',
            'unknown': null,
          },
        });
      },
    );

    test('malformed envelopes and child ids pass unchanged', () {
      final relay = enricherRelay(m1Enrichers);
      for (final message in <Message>[
        {
          'method': 'session/update',
          'id': 'request',
          'params': {
            'sessionId': 'parent',
            'update': {
              'sessionUpdate': 'subagent_spawned',
              'subagentSessionId': 'child',
            },
          },
        },
        _message({
          'sessionUpdate': 'subagent_spawned',
          'subagentSessionId': 4,
          'name': 'x',
        }),
        _message({'sessionUpdate': 'other', 'subagentSessionId': 'child'}),
        {
          'method': 'session/update',
          'params': {
            'sessionId': 4,
            'update': {
              'sessionUpdate': 'subagent_spawned',
              'subagentSessionId': 'child',
            },
          },
        },
      ]) {
        expect(relay.fromAgent(message).single, same(message));
      }
    });

    test('error and unmatched initialize results cannot select Claude', () {
      final relay = enricherRelay(m1Enrichers);
      relay.fromAgent({
        'jsonrpc': '2.0',
        'id': 'unknown',
        'result': {
          'agentInfo': {'name': claudeAdapter},
        },
      });
      expect(_update(relay, _native)['_meta'], isNull);
      _initialize(relay, claudeAdapter, error: true);
      expect(_update(relay, _native)['_meta'], isNull);
      for (final name in [null, 7, 'claude', claudeAdapter.toUpperCase()]) {
        _initialize(relay, name);
        expect(_update(relay, _native)['_meta'], isNull);
      }
    });

    test(
      'adapter survives chord requests agent state tool facts and recall writes',
      () {
        final relay = enricherRelay(m1Enrichers);
        _initialize(relay, claudeAdapter);
        relay.fromChord({
          'jsonrpc': '2.0',
          'id': 'new',
          'method': 'session/new',
          'params': <String, Object?>{},
        });
        relay.fromAgent({
          'jsonrpc': '2.0',
          'id': 'new',
          'result': {'sessionId': 'parent'},
        });
        for (var i = 0; i < 1000; i++) {
          _update(relay, {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tool-$i',
            'title': 'Read',
            'kind': 'read',
          });
        }
        _update(relay, {
          'sessionUpdate': 'usage_update',
          'used': 1,
          'size': 100,
        });
        _update(relay, {
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'default',
        });
        relay.recall('parent', []);
        final meta = _update(relay, _native)['_meta'] as Map;
        expect(meta[namedByTitleKey], true);
        _initialize(relay, claudeAdapter, error: true);
        expect(
          (_update(relay, _native)['_meta'] as Map)[namedByTitleKey],
          true,
        );
      },
    );

    test('separate relays never share initialized adapter facts', () {
      final claude = enricherRelay(m1Enrichers),
          other = enricherRelay(m1Enrichers);
      _initialize(claude, claudeAdapter);
      _initialize(other, 'codex-acp');
      expect((_update(claude, _native)['_meta'] as Map)[namedByTitleKey], true);
      expect(_update(other, _native)['_meta'], isNull);
    });
  });
}
