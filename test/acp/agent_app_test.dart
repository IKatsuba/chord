import 'dart:convert';

import 'package:chord/acp/agent_app.dart';
import 'package:chord/acp/rpc.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/initial_options.dart';
import 'package:chord/session/servers.dart';
import 'package:chord/session/upstream.dart';
import 'package:test/test.dart';

import 'zod_answers.dart';

void main() {
  group('CTUI-36 tester: monitor stop params', () {
    test(
      'both identifiers are required strings and unknown fields are dropped',
      () {
        final check = checkOf('_chord/monitors/stop');
        for (final params in [
          null,
          <String, Object?>{},
          {'sessionId': 's'},
          {'id': 'm1'},
          {'sessionId': 1, 'id': 'm1'},
          {'sessionId': 's', 'id': null},
          {
            'sessionId': 's',
            'id': ['m1'],
          },
        ]) {
          expect(
            () => check(params),
            throwsA(isA<RpcException>().having((e) => e.code, 'code', -32602)),
          );
        }
        expect(check({'sessionId': 's/界', 'id': 'm1', 'extra': true}), {
          'sessionId': 's/界',
          'id': 'm1',
        });
      },
    );
  });

  group('params parsed to zod\'s value, or refused in zod\'s words, as the '
      'original answers them', () {
    for (final [method as String, params, tree, parsed]
        in jsonDecode(zodAnswers) as List) {
      test('$method ${jsonEncode(params)}', () {
        final check = checkOf(method);
        if (tree == null) {
          // As text, so the order of keys is zod's too.
          expect(jsonEncode(check(params)), jsonEncode(parsed));
          return;
        }
        try {
          check(params);
          fail('taken');
        } on RpcException catch (error) {
          expect(error.code, -32602);
          expect(error.message, 'Invalid params');
          // As text, so the order of keys is the original's too.
          expect(jsonEncode(error.data), jsonEncode(tree));
        }
      });
    }
  });

  test('parsed objects are typed maps, merged and recorded ones too', () {
    final parsed = checkOf('session/new')({
      'cwd': '/w',
      'mcpServers': [
        {'type': 'http', 'name': 'a', 'url': 'u', 'headers': <Object?>[]},
      ],
      '_meta': {'x': 1},
    });
    expect((parsed['mcpServers'] as List).single, isA<Map<String, Object?>>());
    expect(parsed['_meta'], isA<Map<String, Object?>>());
  });

  test('absent params are read as an empty object', () {
    expect(checkOf('auth/status')(null), <String, Object?>{});
    expect(
      () => checkOf('session/close')(null),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32602)),
    );
  });

  test('every method chord acp serves has its check, and no other', () {
    expect(paramsOf.keys, [
      'initialize',
      'session/new',
      'session/load',
      'session/resume',
      'session/list',
      'session/close',
      'session/prompt',
      'session/cancel',
      'session/set_config_option',
      'session/set_mode',
      'session/set_title',
      'auth/status',
      '_chord/session/steer',
      '_chord/agents/send',
      '_chord/agents/close',
      '_chord/monitors/stop',
    ]);
  });

  group('tester U3 normalized params boundaries', () {
    test('invalid optional capabilities cannot enable a gated update', () {
      final parsed = checkOf('initialize')({
        'protocolVersion': 1,
        'clientCapabilities': {
          'plan': true,
          'subagents': 'yes',
          'session': {'compaction': [], 'notices': false},
          'terminal': 1,
        },
      });
      final capabilities = parsed['clientCapabilities'] as Map<String, Object?>;
      for (final kind in [
        'plan_update',
        'subagent_update',
        'compaction_update',
        'notice',
      ]) {
        expect(reaches(capabilities, kind), isFalse, reason: kind);
      }
      expect(capabilities['terminal'], isFalse);
      expect(reaches(capabilities, 'agent_message_chunk'), isTrue);
    });

    test(
      'prompt strips unknown fields while steer preserves whole resource blocks',
      () {
        final block = <String, Object?>{
          'type': 'resource',
          'resource': {
            'uri': 'file:///note',
            'text': '界👩‍💻e\u0301\u001b[31m',
            'extra': 'resource',
          },
          'extra': 'block',
          '_meta': {'kept': true},
        };
        final input = {
          'sessionId': 's',
          'prompt': [block],
          'extra': 'outer',
        };
        final before = jsonEncode(input);
        final ordinary = checkOf('session/prompt')(input);
        final steer = checkOf('_chord/session/steer')(input);
        expect(ordinary.containsKey('extra'), isFalse);
        expect(steer.containsKey('extra'), isFalse);
        final ordinaryBlock = (ordinary['prompt'] as List).single as Map;
        final steerBlock = (steer['prompt'] as List).single as Map;
        expect(ordinaryBlock.containsKey('extra'), isFalse);
        expect(
          (ordinaryBlock['resource'] as Map).containsKey('extra'),
          isFalse,
        );
        expect(steerBlock['extra'], 'block');
        expect((steerBlock['resource'] as Map)['extra'], 'resource');
        expect(jsonEncode(input), before);
        final sent = promptOf(
          [Map<String, Object?>.from(steerBlock)],
          'fake',
          takesImages: false,
          takesEmbeddedContext: true,
        );
        expect(sent.refused, isNull);
        expect(sent.prompt!.parts.resources.single, steerBlock);
      },
    );

    test(
      'an MCP server falling back to stdio cannot retain HTTP routing fields',
      () {
        final parsed = checkOf('session/new')({
          'cwd': '/work',
          'mcpServers': [
            {
              'type': 'http',
              'name': 'fallback',
              'command': 'helper',
              'args': null,
              'env': null,
            },
          ],
        });
        expect(parsed['mcpServers'], [
          {'name': 'fallback', 'command': 'helper', 'args': [], 'env': []},
        ]);
      },
    );

    test('the selected string config branch removes a boolean type tag', () {
      final parsed = checkOf('session/set_config_option')({
        'sessionId': 's',
        'configId': 'x',
        'type': 'boolean',
        'value': 'literal',
      });
      expect(parsed, {'value': 'literal', 'sessionId': 's', 'configId': 'x'});
    });
  });

  group('tester U3 parsed consumer boundaries', () {
    test(
      'parsed MCP intersections reach filtering and initial config consumers',
      () {
        final parsed = checkOf('session/new')({
          'cwd': '/w',
          'mcpServers': [
            {
              'type': 'http',
              'name': 'http',
              'url': 'https://example.test',
              'headers': [
                {'name': 'x', 'value': 'y'},
              ],
            },
            {
              'type': 'sse',
              'name': 'sse',
              'url': 'https://example.test',
              'headers': [],
            },
            {'type': 'acp', 'name': 'acp', 'serverId': 'peer'},
          ],
          'configOptions': [
            {
              'configId': 'fast',
              'type': 'boolean',
              'value': true,
              '_meta': {'kept': true},
            },
          ],
          '_meta': {
            'unknown': [1, null],
          },
        });
        final servers = (parsed['mcpServers'] as List)
            .cast<Map<String, Object?>>();
        final filtered = serversFor('a', {'http': true, 'acp': true}, servers);
        expect(filtered.servers.map((s) => s['name']), ['http', 'acp']);
        expect(filtered.heldBack.single.server, 'sse');
        final headers = (servers.first['headers'] as List)
            .cast<Map<String, Object?>>();
        expect(headers.single['value'], 'y');
        final config = initialEntries(
          acp.InitializeResponse.fromJson({
            'protocolVersion': 1,
            'agentCapabilities': {
              'sessionCapabilities': {'options': {}},
            },
          }),
          (model: null, effort: null, mode: null),
          entries: (parsed['configOptions'] as List)
              .cast<Map<String, Object?>>(),
        );
        expect(config.single['value'], isTrue);
        expect(
          (config.single['_meta'] as Map<String, Object?>)['kept'],
          isTrue,
        );
        expect((parsed['_meta'] as Map<String, Object?>)['unknown'], [1, null]);
      },
    );

    test('parsed content intersections reach prompt mapping whole', () {
      final parsed = checkOf('session/prompt')({
        'sessionId': 's',
        'prompt': [
          {
            'type': 'resource',
            'resource': {
              'uri': 'memory://text',
              'text': '界👩‍💻e\u0301',
              '_meta': {'kept': true},
            },
          },
          {
            'type': 'resource',
            'resource': {'uri': 'memory://blob', 'blob': 'AAEC'},
          },
          {'type': 'resource_link', 'name': 'link', 'uri': 'memory://link'},
        ],
      });
      final prompt = promptOf(
        (parsed['prompt'] as List).cast<Map<String, Object?>>(),
        'a',
        takesImages: false,
        takesEmbeddedContext: true,
      );
      expect(prompt.refused, isNull);
      expect(prompt.prompt!.parts.resources, hasLength(2));
      expect(
        (prompt.prompt!.parts.resources.first['resource']
            as Map<String, Object?>)['text'],
        '界👩‍💻e\u0301',
      );
      expect(prompt.prompt!.parts.links.single['name'], 'link');
    });
  });
}
