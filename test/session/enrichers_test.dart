// The original's enrichers_test.ts, the cases of the four enrichers M1
// runs: toolCallFacts, codexMcpCall, codexGuardianReview, rawOutputContent.
// Left for later: costs and windows, mode read-back, subagents' shapes and
// names, and recalling a past; the question enrichers are
// enrichers_questions_test.dart's.
import 'package:chord/acp/connection.dart' show Relay;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/tools.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

const _session = 'session-1';

/// A relay running [enrichers] on a session `session/new` opened.
({Relay relay, List<Message> Function(Message) update}) _relayOn(
  List<Enricher> enrichers,
) {
  final relay = enricherRelay(enrichers);

  relay.fromChord({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'session/new',
    'params': {'cwd': '/'},
  });
  relay.fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'result': {'sessionId': _session},
  });

  return (
    relay: relay,
    update: (update) => relay.fromAgent({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {'sessionId': _session, 'update': update},
    }),
  );
}

List<Message> _updates(List<Message> messages) => [
  for (final message in messages)
    if (notificationOf(message) case (_, final update)) update,
];

List<Map<String, Object?>> _text(String said) => [
  {
    'type': 'content',
    'content': {'type': 'text', 'text': said},
  },
];

void main() {
  test("a tool call's title and kind are carried onto updates that leave "
      'them out', () {
    final (:relay, :update) = _relayOn([toolCallFacts]);

    update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'call-1',
      'title': 'Read README.md',
      'kind': 'read',
      'status': 'pending',
    });

    expect(
      _updates(
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        }),
      ),
      [
        {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
          'title': 'Read README.md',
          'kind': 'read',
          '_meta': {
            filledKey: ['title', 'kind'],
          },
        },
      ],
    );

    // A title the update gives is the one kept, and carried after.
    update({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'call-1',
      'title': 'Read docs/README.md',
    });
    expect(
      _updates(
        update({'sessionUpdate': 'tool_call_update', 'toolCallId': 'call-1'}),
      ).single,
      {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-1',
        'title': 'Read docs/README.md',
        'kind': 'read',
        '_meta': {
          filledKey: ['title', 'kind'],
        },
      },
    );
    expect(
      _updates(
        update({'sessionUpdate': 'tool_call_update', 'toolCallId': 'other'}),
      ),
      [
        {'sessionUpdate': 'tool_call_update', 'toolCallId': 'other'},
      ],
    );
  });

  test('a permission asked about a known call names it', () {
    final (:relay, :update) = _relayOn([toolCallFacts]);

    update({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'call-1',
      'title': 'Write notes.md',
      'kind': 'edit',
    });

    final asked = relay.fromAgent({
      'jsonrpc': '2.0',
      'id': 'p-1',
      'method': 'session/request_permission',
      'params': {
        'sessionId': _session,
        'toolCall': {'toolCallId': 'call-1'},
        'options': <Object?>[],
      },
    }).single;

    expect((asked['params'] as Map)['toolCall'], {
      'toolCallId': 'call-1',
      'title': 'Write notes.md',
      'kind': 'edit',
      '_meta': {
        filledKey: ['title', 'kind'],
      },
    });
  });

  test("a call another session knows, or a permission naming none, is left "
      'as it came', () {
    final (:relay, :update) = _relayOn([toolCallFacts]);

    update({'sessionUpdate': 'tool_call', 'toolCallId': 'c', 'title': 'Run'});

    for (final message in <Message>[
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 'other',
          'update': {'sessionUpdate': 'tool_call_update', 'toolCallId': 'c'},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/request_permission',
        'params': {'sessionId': _session, 'options': <Object?>[]},
      },
    ]) {
      expect(identical(relay.fromAgent(message).single, message), isTrue);
    }
  });

  test("Codex's MCP call has its server, tool and arguments filed beside its "
      'rawInput, which stays as sent', () {
    final (:relay, :update) = _relayOn([codexMcpCall]);
    final rawInput = {
      'server': 'chord',
      'tool': 'send_message',
      'arguments': {'to': 'ship', 'text': 'ready'},
    };
    final enriched = _updates(
      update({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'exec-1',
        'title': 'mcp.chord.send_message',
        'kind': 'execute',
        'status': 'in_progress',
        'rawInput': rawInput,
        '_meta': {'is_mcp_tool_call': true},
      }),
    ).single;

    expect(enriched, {
      'sessionUpdate': 'tool_call',
      'toolCallId': 'exec-1',
      'title': 'mcp.chord.send_message',
      'kind': 'execute',
      'status': 'in_progress',
      'rawInput': rawInput,
      '_meta': {
        'is_mcp_tool_call': true,
        filledKey: [mcpCallKey],
        mcpCallKey: rawInput,
      },
    });
    expect(identical(enriched['rawInput'], rawInput), isTrue);
    // Enriching twice changes nothing more.
    expect(_updates(update(enriched)), [enriched]);

    // Claude's shape, and a command that is no MCP call, are left alone.
    for (final call in <Message>[
      {'title': 'mcp__chord__list_agents', 'kind': 'other', 'rawInput': {}},
      {
        'title': 'Run a.sh',
        'kind': 'execute',
        'rawInput': {'server': 'x', 'tool': 'y', 'arguments': {}},
      },
    ]) {
      final sent = {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'other',
        ...call,
      };

      expect(_updates(update(sent)), [sent]);
    }
  });

  test('a missing, null or empty arguments keeps its shape, and a malformed '
      'or unmarked wrapper is left unfilled', () {
    final (:relay, :update) = _relayOn([codexMcpCall]);

    for (final extra in <Message>[
      {},
      {'arguments': null},
      {'arguments': {}},
    ]) {
      final enriched = _updates(
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'optional',
          'rawInput': {'server': 'my.notes', 'tool': 'notes.v2', ...extra},
          '_meta': {'is_mcp_tool_call': true},
        }),
      ).single;

      expect((enriched['_meta'] as Map)[mcpCallKey], {
        'server': 'my.notes',
        'tool': 'notes.v2',
        ...extra,
      });
    }

    for (final (rawInput, marked) in <(Object?, Object?)>[
      (null, true),
      ({'tool': 'list'}, true),
      ({'server': null, 'tool': 'list'}, true),
      ({'server': 3, 'tool': 'list'}, true),
      ({'server': 'notes', 'tool': 7}, true),
      ({'server': 'notes', 'tool': 'list'}, false),
      ({'server': 'notes', 'tool': 'list'}, 'true'),
    ]) {
      final sent = {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'guard',
        'rawInput': rawInput,
        '_meta': {'is_mcp_tool_call': marked},
      };

      expect(_updates(update(sent)), [sent]);
    }
  });

  group('structured Codex Guardian review status', () {
    test('missing, malformed and empty review ids leave the message as it '
        'came', () {
      final (:relay, :update) = _relayOn([codexGuardianReview]);

      for (final toolCallId in [null, 42, 'guardian_assessment:', 'ordinary']) {
        for (final opening in [true, false]) {
          final sent = <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': _session,
              'update': {
                'sessionUpdate': opening ? 'tool_call' : 'tool_call_update',
                'toolCallId': ?toolCallId,
                opening ? 'rawInput' : 'rawOutput': {
                  'review': {'status': 'approved'},
                },
              },
            },
          };

          expect(relay.fromAgent(sent), [sent]);
        }
      }
    });

    for (final status in [
      'inProgress',
      'approved',
      'denied',
      'timedOut',
      'aborted',
      'futureStatus',
    ]) {
      for (final opening in [true, false]) {
        test(
          '$status from ${opening ? 'rawInput on an opening' : 'rawOutput on an update'} '
          'is filed without changing the agent fields',
          () {
            final (:relay, :update) = _relayOn([codexGuardianReview]);
            final sent = <String, Object?>{
              'sessionUpdate': opening ? 'tool_call' : 'tool_call_update',
              'toolCallId': 'guardian_assessment:review-1',
              'title': 'Guardian Review',
              'kind': 'think',
              opening ? 'rawInput' : 'rawOutput': {
                'review': {'status': status},
              },
              '_meta': {'own': true},
            };

            expect(_updates(update(sent)), [
              {
                ...sent,
                '_meta': {
                  'own': true,
                  filledKey: [guardianReviewKey],
                  guardianReviewKey: status,
                },
              },
            ]);
            expect(sent['_meta'], {'own': true});
          },
        );
      }
    }

    test('a review without a structured status, or in the wrong field, is '
        'left as it came', () {
      final (:relay, :update) = _relayOn([codexGuardianReview]);

      for (final fields in <Message>[
        {'toolCallId': 'guardian_assessment:missing'},
        {
          'toolCallId': 'guardian_assessment:malformed',
          'rawInput': {
            'review': {'status': null},
          },
        },
        {
          'toolCallId': 'guardian_assessment:wrong-field',
          'rawOutput': {
            'review': {'status': 'approved'},
          },
        },
      ]) {
        final sent = {
          'sessionUpdate': 'tool_call',
          'title': 'Guardian Review',
          'content': _text('Status: Approved'),
          ...fields,
        };

        expect(_updates(update(sent)), [sent]);
      }
    });

    test(
      'the transcript keeps the last structured status when absent, '
      'replaces it even with an unknown string, and ignores rendered text',
      () {
        final (:relay, :update) = _relayOn(m1Enrichers);
        var transcript = Transcript.empty;
        const id = 'guardian_assessment:review';
        final seen = <String?>[];

        for (final each in <Message>[
          {
            'sessionUpdate': 'tool_call',
            'toolCallId': id,
            'title': 'Guardian Review',
            'kind': 'think',
            'rawInput': {
              'review': {'status': 'inProgress'},
            },
          },
          {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': id,
            'content': _text('Status: Approved'),
          },
          {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': id,
            'rawOutput': {
              'review': {'status': 'approved'},
            },
          },
          {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': id,
            'rawOutput': {
              'review': {'status': 'futureStatus'},
            },
          },
          {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': id,
            'status': 'completed',
          },
        ]) {
          for (final read in _updates(update(each))) {
            transcript = reduceTranscript(
              transcript,
              UpdateAction('t1', acp.SessionUpdate.fromJson(read)),
            );
          }
          seen.add(
            transcript.entries.whereType<ToolEntry>().single.call.guardian,
          );
        }

        expect(seen, [
          'inProgress',
          'inProgress',
          'approved',
          'futureStatus',
          'futureStatus',
        ]);
      },
    );
  });

  group(
    "a result sent only as rawOutput is filled in as the call's content",
    () {
      Message? done(Object? rawOutput, [Message more = const {}]) {
        final (:relay, :update) = _relayOn([rawOutputContent]);

        return _updates(
          update({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-1',
            'status': 'completed',
            'rawOutput': rawOutput,
            ...more,
          }),
        ).firstOrNull;
      }

      test('a string is its text', () {
        expect(done('built in 3s\n'), {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
          'rawOutput': 'built in 3s\n',
          'content': _text('built in 3s\n'),
          '_meta': {
            filledKey: ['content'],
          },
        });
      });

      test('only a bare successful exit_code contributes no output', () {
        for (final code in <num>[0, 0.0]) {
          final result = done({'exit_code': code})!;
          expect(result.containsKey('content'), isFalse);
          expect(result.containsKey('_meta'), isFalse);
          expect(result['status'], 'completed');
          expect(result['rawOutput'], {'exit_code': code});
        }
        for (final raw in <Object?>[
          {'exit_code': 1},
          {'exit_code': -1.5},
          {'exit_code': '0'},
          {'exit_code': null},
          {'exitCode': 0},
          {'exit_code': 0, 'lines': 1},
        ]) {
          expect(done(raw)!['content'], isNotNull, reason: '$raw');
        }
        expect(
          done({'exit_code': 0, 'output': 'file text'})!['content'],
          _text('file text'),
        );
        expect(
          done({'exit_code': 0}, {'content': _text('agent text')})!['content'],
          _text('agent text'),
        );
      });

      test("cursor's shell: stdout then stderr; a non-zero exitCode fails the "
          'call', () {
        final shell = {
          'exitCode': 0,
          'stdout': 'ok 1\nok 2\n',
          'stderr': 'warn\n',
        };

        expect(done(shell), {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
          'rawOutput': shell,
          'content': _text('ok 1\nok 2\nwarn'),
          '_meta': {
            filledKey: ['content'],
          },
        });
        expect(done({...shell, 'exitCode': 2}), {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'failed',
          'rawOutput': {...shell, 'exitCode': 2},
          'content': _text('ok 1\nok 2\nwarn'),
          '_meta': {
            filledKey: ['content', 'status'],
          },
        });
        // Nothing printed, yet failed: the status alone.
        expect(done({'exitCode': 1, 'stdout': '', 'stderr': ''}), {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'failed',
          'rawOutput': {'exitCode': 1, 'stdout': '', 'stderr': ''},
          '_meta': {
            filledKey: ['status'],
          },
        });
        // An exit code that is no number, or a running call, fails nothing.
        expect(done({'stdout': 'ok', 'exitCode': '1'})?['status'], 'completed');
        expect(
          done(
            {'stdout': 'ok', 'exitCode': 1},
            {'status': 'in_progress'},
          )?['status'],
          'in_progress',
        );
      });

      test("auggie's output and bob's result are their text; any other value "
          'its JSON', () {
        expect(done({'output': 'file text'})?['content'], _text('file text'));
        expect(done({'result': 'done'})?['content'], _text('done'));
        expect(
          done({
            'files': ['a.ts'],
            'count': 1,
          })?['content'],
          _text('{\n  "files": [\n    "a.ts"\n  ],\n  "count": 1\n}'),
        );
        expect(done([1, 2])?['content'], _text('[\n  1,\n  2\n]'));
        expect(done(false)?['content'], _text('false'));
        expect(done(0)?['content'], _text('0'));
      });

      test('named fields keep their order and blank lines', () {
        expect(
          done({
            'result': 'result\n',
            'output': 'output\n',
            'stderr': 'warning\n',
            'stdout': 'one\n\n',
            'exitCode': -1,
          }),
          containsPair('content', _text('one\n\nwarning\noutput\nresult')),
        );
      });

      test('a running call is filled too, so its output shows as it comes', () {
        expect(
          done('line 1', {'status': 'in_progress'})?['content'],
          _text('line 1'),
        );
      });

      test('content the agent sent stays, and a call with no rawOutput, or an '
          'empty one, passes as it came', () {
        final (:relay, :update) = _relayOn([rawOutputContent]);
        final own = {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
          'content': _text('its own'),
          'rawOutput': {'stdout': 'other'},
        };
        final bare = {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        };

        expect(_updates(update(own)), [own]);
        expect(_updates(update(bare)), [bare]);
        expect(done(''), {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
          'rawOutput': '',
        });
      });

      test('content the agent sent earlier stays when a later update brings '
          'only rawOutput, through the whole chain and the transcript', () {
        final (:relay, :update) = _relayOn(m1Enrichers);
        final read = [
          for (final each in <Message>[
            {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'call-2',
              'title': 'Run npm test',
              'kind': 'execute',
              'status': 'in_progress',
              'content': _text('its own'),
            },
            {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'call-2',
              'status': 'completed',
              'rawOutput': 'raw',
            },
          ])
            ..._updates(update(each)),
        ];
        final transcript = read.fold(
          Transcript.empty,
          (state, each) => reduceTranscript(
            state,
            UpdateAction('t1', acp.SessionUpdate.fromJson(each)),
          ),
        );
        final call = transcript.entries.whereType<ToolEntry>().single.call;

        // Its title and kind carried on, as toolCallFacts does; no content.
        expect(read[1]['title'], 'Run npm test');
        expect(read[1].containsKey('content'), isFalse);
        expect([for (final c in call.content!) c.toJson()], _text('its own'));

        // Content the agent clears is its own word too: then rawOutput fills.
        expect(
          _updates(
            update({
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'call-2',
              'content': <Object?>[],
            }),
          ),
          hasLength(1),
        );
        expect(
          _updates(
            update({
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'call-2',
              'status': 'completed',
              'rawOutput': 'raw',
            }),
          ).single['content'],
          _text('raw'),
        );
      });

      test('a clear sent with rawOutput in one update is the agent clearing '
          'too, so a newer rawOutput fills again', () {
        final (:relay, :update) = _relayOn(m1Enrichers);
        Object? content(Message each) =>
            _updates(update(each)).single['content'];

        content({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-3',
          'title': 'Run npm test',
          'status': 'in_progress',
          'content': _text('its own'),
        });

        expect(
          content({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-3',
            'content': <Object?>[],
            'rawOutput': 'first',
          }),
          _text('first'),
        );
        expect(
          content({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-3',
            'status': 'completed',
            'rawOutput': 'second',
          }),
          _text('second'),
        );
      });

      test(
        'two sessions reuse a call id without sharing content ownership',
        () {
          final relay = enricherRelay(m1Enrichers);
          Object? send(String sessionId, Message update) => notificationOf(
            relay.fromAgent({
              'jsonrpc': '2.0',
              'method': 'session/update',
              'params': {'sessionId': sessionId, 'update': update},
            }).single,
          )!.$2['content'];

          send('own', {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'shared',
            'content': _text('agent original'),
          });
          send('generated', {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'shared',
            'rawOutput': 'partial',
          });

          expect(
            send('own', {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'shared',
              'rawOutput': 'ignored',
            }),
            isNull,
          );
          expect(
            send('generated', {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'shared',
              'rawOutput': {'stdout': 'final\n'},
            }),
            _text('final'),
          );
        },
      );
    },
  );

  test('every enricher builds new maps and never writes the one it was '
      'handed', () {
    final relay = enricherRelay(m1Enrichers);
    final sent = <Message>[
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': _session,
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'guardian_assessment:r',
            'title': 'T',
            'kind': 'execute',
            'rawInput': {
              'server': 's',
              'tool': 't',
              'review': {'status': 'approved'},
            },
            'rawOutput': 'out',
            '_meta': {'is_mcp_tool_call': true},
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': _session,
          'update': {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'guardian_assessment:r',
            'rawOutput': {'stdout': 'x', 'exitCode': 1},
            'status': 'completed',
          },
        },
      },
    ];
    final before = [for (final each in sent) _deepCopy(each)];

    for (final each in sent) {
      relay.fromAgent(each);
    }

    expect(sent, before);
  });

  group('tester: enricher isolation and immutable inputs', () {
    test(
      'separate relays never share facts for identical session and call ids',
      () {
        final first = _relayOn(m1Enrichers);
        final second = _relayOn(m1Enrichers);
        first.update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c',
          'title': 'First',
          'kind': 'read',
          'content': _text('owned'),
        });
        final message = {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c',
          'rawOutput': '界 e\u0301 👩‍💻\x1b[31m',
        };
        final a = _updates(first.update(message)).single;
        final b = _updates(second.update(message)).single;
        expect(a['title'], 'First');
        expect(a.containsKey('content'), isFalse);
        expect(b.containsKey('title'), isFalse);
        expect(b['content'], _text(message['rawOutput'] as String));
        expect(message.containsKey('_meta'), isFalse);
      },
    );

    test(
      'the four enrichers accept nested immutable maps and mark only fills',
      () {
        final (:relay, :update) = _relayOn(m1Enrichers);
        const sent = <String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': 'guardian_assessment:r',
          'rawInput': {
            'server': 's',
            'tool': 't',
            'arguments': {'q': '界'},
            'review': {'status': 'approved'},
          },
          'rawOutput': 'output',
          '_meta': {
            'is_mcp_tool_call': true,
            'kept': {'nested': true},
            filledKey: ['prior'],
          },
        };
        final result = _updates(update(sent)).single;
        expect(filledIn(result), [
          'prior',
          mcpCallKey,
          guardianReviewKey,
          'content',
        ]);
        expect((result['_meta'] as Map)['kept'], {'nested': true});
        expect(identical(result['rawInput'], sent['rawInput']), isTrue);
        expect(result['content'], _text('output'));
        expect((sent['_meta'] as Map)[filledKey], ['prior']);
        expect(sent.containsKey('content'), isFalse);
        expect(_updates(update(result)), [result]);
      },
    );
  });

  test('session enrichers run in the original order', () {
    expect(m1Enrichers, [
      subagentShape,
      claudeSubagentName,
      toolCallFacts,
      codexMcpCall,
      codexGuardianReview,
      rawOutputContent,
      modeReadBack,
      costFromTokens,
      windowFromModel,
      claudeQuestions,
      codexQuestions,
      droidQuestions,
      opencodeQuestions,
      dimcodeQuestions,
    ]);
  });
}

Object? _deepCopy(Object? value) => switch (value) {
  Map() => {
    for (final MapEntry(:key, :value) in value.entries) key: _deepCopy(value),
  },
  List() => [for (final each in value) _deepCopy(each)],
  _ => value,
};
