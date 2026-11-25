// A request chord's server served is tied to the tool call the agent made
// for it, by the arguments both carry; the original's
// src/session/transcript/chord.ts.
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

UpdateAction _call(
  String id,
  Map<String, Object?> input, {
  String title = 'mcp__chord__send_message',
  String status = 'pending',
  Map<String, Object?>? meta,
}) => update('t', {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title,
  'status': status,
  'rawInput': input,
  '_meta': ?meta,
});

const _input = {'to': 'parser', 'text': 'Run the parser tests.'};

ToolCall _tool(Transcript state, String id) => state.entries
    .whereType<ToolEntry>()
    .lastWhere((entry) => entry.call.id == id)
    .call;

void main() {
  _testerReceiptMatching();
  test('a request served ties to its call by the arguments both carry', () {
    final state = fold([
      _call('c1', const {'to': 'docs', 'text': 'other'}),
      _call('c2', _input),
      const ServedAction(
        't',
        ChordCall(tool: ChordTool.sendMessage, input: _input),
      ),
    ]);
    expect(_tool(state, 'c1').chord, isNull);
    expect(_tool(state, 'c2').chord?.input, _input);
    expect(state.served, isEmpty);
  });

  test('one served before its call came waits, and ties once it comes', () {
    final state = fold([
      const ServedAction(
        't',
        ChordCall(tool: ChordTool.sendMessage, input: _input),
      ),
    ]);
    expect(state.served, hasLength(1));
    final after = fold([_call('c', _input)], state);
    expect(_tool(after, 'c').chord?.tool, ChordTool.sendMessage);
    expect(after.served, isEmpty);
  });

  test('a message served again as queued takes the place of the first', () {
    final state = fold([
      _call('c', _input),
      const ServedAction(
        't',
        ChordCall(
          tool: ChordTool.sendMessage,
          input: _input,
          answer: {'delivered': 'sent'},
          asked: 'q1',
        ),
      ),
      const ServedAction(
        't',
        ChordCall(
          tool: ChordTool.sendMessage,
          input: _input,
          answer: {'delivered': 'sent'},
          asked: 'q1',
          queued: true,
        ),
      ),
    ]);
    expect(_tool(state, 'c').chord?.queued, isTrue);
    expect(state.served, isEmpty);
  });

  test('a later update keeps the tie, and Claude marks a call cut off', () {
    final state = fold([
      _call('c', _input),
      const ServedAction(
        't',
        ChordCall(tool: ChordTool.sendMessage, input: _input),
      ),
      update('t', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'c',
        'status': 'completed',
      }),
      _call(
        'd',
        const {'text': 'Found it.'},
        status: 'failed',
        meta: {
          'claudeCode': {'nonExecutionKind': 'interrupted'},
        },
      ),
    ]);
    expect(_tool(state, 'c').chord, isNotNull);
    expect(_tool(state, 'c').status, 'completed');
    expect(_tool(state, 'd').cut, isTrue);
    expect(_tool(state, 'c').cut, isFalse);
  });
}

void _testerReceiptMatching() {
  group('CTUI-35 tester: receipt correlation', () {
    for (final before in [true, false]) {
      test(
        'identical calls retain separate asked ids with receipt-first=$before',
        () {
          const first = ChordCall(
            tool: ChordTool.sendMessage,
            input: _input,
            answer: {'delivered': 'sent'},
            asked: 'first',
          );
          const second = ChordCall(
            tool: ChordTool.sendMessage,
            input: _input,
            answer: {'delivered': 'sent'},
            asked: 'second',
          );
          final calls = [_call('c1', _input), _call('c2', _input)];
          final receipts = [
            const ServedAction('t', first),
            const ServedAction('t', second),
          ];
          var state = fold(
            before ? [...receipts, ...calls] : [...calls, ...receipts],
          );
          final firstId = before ? 'c1' : 'c2';
          final secondId = before ? 'c2' : 'c1';
          expect(_tool(state, firstId).chord!.asked, 'first');
          expect(_tool(state, secondId).chord!.asked, 'second');
          final firstIdentity = state.entries
              .whereType<ToolEntry>()
              .firstWhere((e) => e.call.id == firstId)
              .identity;
          state = fold([
            const ServedAction(
              't',
              ChordCall(
                tool: ChordTool.sendMessage,
                input: _input,
                asked: 'first',
                queued: true,
                answer: {'delivered': 'queued'},
              ),
            ),
            update('t', {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': firstId,
              'status': 'completed',
            }),
          ], state);
          expect(_tool(state, firstId).chord!.queued, isTrue);
          expect(_tool(state, secondId).chord, same(second));
          expect(_tool(state, firstId).status, 'completed');
          expect(
            state.entries
                .whereType<ToolEntry>()
                .firstWhere((e) => e.call.id == firstId)
                .identity,
            firstIdentity,
          );
          expect(state.served, isEmpty);
        },
      );
    }
    test(
      'map key order is irrelevant but nested array order distinguishes calls',
      () {
        const first = {
          'args': {
            'left': true,
            'right': [1, 2],
          },
          'to': 'parser',
        };
        const reversed = {
          'to': 'parser',
          'args': {
            'right': [2, 1],
            'left': true,
          },
        };
        final state = fold([
          _call('c1', first),
          _call('c2', reversed),
          const ServedAction(
            't',
            ChordCall(
              tool: ChordTool.sendMessage,
              input: {
                'to': 'parser',
                'args': {
                  'right': [1, 2],
                  'left': true,
                },
              },
            ),
          ),
        ]);
        expect(_tool(state, 'c1').chord, isNotNull);
        expect(_tool(state, 'c2').chord, isNull);
      },
    );
  });
}
