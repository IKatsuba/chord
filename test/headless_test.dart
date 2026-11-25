// `chord -p`'s words: the original's tests/headless_test.ts pure cases.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/headless.dart';
import 'package:chord/session/oneshot.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

acp.SessionUpdate _say(String text) => acp.SessionUpdate.fromJson({
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
});

acp.SessionUpdate _think(String text) => acp.SessionUpdate.fromJson({
  'sessionUpdate': 'agent_thought_chunk',
  'content': {'type': 'text', 'text': text},
});

final _call = acp.SessionUpdate.fromJson({
  'sessionUpdate': 'tool_call',
  'toolCallId': 'c1',
  'title': 'Read notes.txt',
});

acp.SessionUpdate _plan(String id, String content) =>
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'plan_update',
      'plan': {'type': 'markdown', 'planId': id, 'content': content},
    });

OneshotOutcome _done([String stopReason = 'end_turn']) =>
    OneshotOutcome(sessionId: 'session-1', result: TurnAnswered(stopReason));

void main() {
  group('tester: CTUI-28 headless output boundaries', () {
    test(
      'tool boundaries survive empty chunks and never add a third newline',
      () {
        for (final (before, expected) in [
          ('', 'next'),
          ('line', 'line\n\nnext'),
          ('line\n', 'line\n\nnext'),
          ('line\n\n', 'line\n\nnext'),
          ('line\n\n\n', 'line\n\n\nnext'),
        ]) {
          final reply = Reply();
          reply.take(_say(before));
          reply.take(_call);
          reply.take(_say(''));
          reply.take(_think('not stdout'));
          reply.take(_call);
          reply.take(_say('next'));
          expect(reply.text, expected);
          expect(reply.end(), '\n');
        }
        final empty = Reply();
        empty.take(_call);
        expect(empty.end(), '');
      },
    );

    test('every Unicode and escape split joins without normalization', () {
      const text = '界👩‍💻é\x1b[31m red\x1b[0m\n';
      for (var split = 0; split <= text.length; split++) {
        final reply = Reply();
        final first = reply.take(_say(text.substring(0, split)));
        final second = reply.take(_say(text.substring(split)));
        expect('$first$second', text, reason: 'split $split');
        expect(reply.text, text);
        expect(reply.end(), '');
      }
    });

    test(
      'removed and resurrected plans keep one logical position and the printed suffix',
      () {
        final reply = Reply();
        expect(reply.take(_plan('one', '')), '');
        expect(reply.take(_plan('one', 'A')), 'A');
        expect(reply.take(_say(' after')), ' after');
        reply.take(
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'plan_removed',
            'planId': 'one',
          }),
        );
        expect(reply.text, ' after');
        expect(reply.take(_plan('one', 'AB')), 'B');
        expect(reply.text, 'AB after');
        expect(reply.take(_plan('two', 'second')), 'second');
        expect(reply.take(_plan('one', 'rewrite')), '');
        expect(reply.text, 'rewrite aftersecond');
      },
    );

    test(
      'a rewritten plan leaves a pending tool break for the next actual text',
      () {
        final reply = Reply();
        reply.take(_plan('p', 'old'));
        reply.take(_call);
        expect(reply.take(_plan('p', 'replacement')), '');
        expect(reply.take(_say('next')), '\n\nnext');
        expect(reply.text, 'replacement\n\nnext');
        final independent = Reply();
        expect(independent.take(_plan('p', 'fresh')), 'fresh');
        expect(independent.text, 'fresh');
      },
    );

    test(
      'JSON preserves all sparse zero and fractional token fields and zero non-USD cost',
      () {
        final json = resultJson(
          const OneshotOutcome(
            sessionId: 's',
            result: TurnAnswered('end_turn'),
            usage: {
              'inputTokens': 0,
              'outputTokens': 0.5,
              'cachedReadTokens': 0,
              'cachedWriteTokens': 2,
              'thoughtTokens': 3,
              'totalTokens': 5.5,
            },
            cost: (amount: 0, currency: 'EUR'),
            costEstimated: true,
          ),
          '界😀é',
        );
        expect(json['usage'], {
          'input_tokens': 0,
          'output_tokens': 0.5,
          'cache_read_input_tokens': 0,
          'cache_creation_input_tokens': 2,
          'thought_tokens': 3,
          'total_tokens': 5.5,
        });
        expect(json['cost'], {'amount': 0, 'currency': 'EUR'});
        expect(json['cost_estimated'], isTrue);
        expect(json.containsKey('total_cost_usd'), isFalse);
        final absent = resultJson(
          const OneshotOutcome(
            sessionId: 's',
            result: TurnAnswered('end_turn'),
            usage: {},
            costEstimated: true,
          ),
          '',
        );
        expect(absent['usage'], isEmpty);
        expect(absent.containsKey('cost_estimated'), isFalse);
        expect(absent.containsKey('error'), isFalse);
      },
    );

    test(
      'recorded cancellation status is authoritative without losing the stop reason',
      () {
        final json = resultJson(
          const OneshotOutcome(
            sessionId: 's',
            result: TurnAnswered('end_turn', recordedStatus: 'cancelled'),
          ),
          'partial',
        );
        expect(json['is_error'], isTrue);
        expect(json['stop_reason'], 'end_turn');
        expect(json['error'], 'The turn was cancelled.');
        expect(json['result'], 'partial');
        final failed = resultJson(
          const OneshotOutcome(sessionId: 's', result: TurnFailed('')),
          '',
        );
        expect(failed['is_error'], isTrue);
        expect(failed['error'], '');
        expect(failed.containsKey('stop_reason'), isFalse);
      },
    );

    test('diagnostic empty values retain the original distinctions', () {
      expect(
        noticeLine(
          title: ' \x1b]0;hidden\x07界\n👩‍💻 é ',
          description: '\t\r\n',
        ),
        'chord: 界 👩‍💻 é\n',
      );
      expect(
        allowedLine({'toolCallId': 'id', 'title': ''}),
        'chord: allowed .\n',
      );
      expect(skippedLines('fake', message: 'fallback', questions: []), '');
      expect(
        skippedLines('fake', message: ''),
        'chord: fake asked:  — skipped (no one to answer under -p)\n',
      );
      expect(joinPiped(' ', '\n'), ' \n\n');
    });
  });
  test('piped input follows the prompt on a line of its own', () {
    expect(joinPiped('Explain', 'some code\n'), 'Explain\nsome code\n');
    expect(joinPiped('Explain', null), 'Explain');
    expect(joinPiped('Explain', ''), 'Explain');
    expect(joinPiped('', 'only piped'), 'only piped');
  });

  test('the reply keeps the agent text and leaves its thinking out', () {
    final reply = Reply();
    expect(
      [
        for (final e in [_think('hmm'), _say('Hel'), _say('lo')]) reply.take(e),
      ],
      ['', 'Hel', 'lo'],
    );
    expect(reply.text, 'Hello');
    expect(reply.end(), '\n');
  });

  test('text after a tool call starts a paragraph of its own', () {
    final reply = Reply();
    for (final e in [_call, _say('Reading.'), _call, _say('Done.')]) {
      reply.take(e);
    }
    expect(reply.text, 'Reading.\n\nDone.');
    final ended = Reply();
    for (final e in [_say('Line.\n'), _call, _say('Next.\n')]) {
      ended.take(e);
    }
    expect(ended.text, 'Line.\n\nNext.\n');
    expect(ended.end(), '');
  });

  test('a markdown plan reaches stdout once, as it grows', () {
    final reply = Reply();
    expect(
      [
        for (final e in [
          _say('Here it is.\n'),
          _plan('a', '1. Read'),
          _plan('a', '1. Read'),
          _plan('a', '1. Read\n2. Write\n'),
          _plan('a', 'rewritten'),
        ])
          reply.take(e),
      ],
      ['Here it is.\n', '1. Read', '', '\n2. Write\n', ''],
    );
    expect(reply.text, 'Here it is.\nrewritten');
  });

  test('the JSON result has a markdown plan as last sent', () {
    final reply = Reply();
    final written = [
      for (final e in [
        _plan('a', '1. Read'),
        _plan('a', '1. Inspect'),
        _plan('a', '1. Inspect\n2. Write'),
        _say(' Done.'),
        _call,
        _plan('b', 'Gone'),
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'plan_removed',
          'planId': 'b',
        }),
        _say('Bye.'),
      ])
        reply.take(e),
    ];
    expect(written, ['1. Read', '', '', ' Done.', '', '\n\nGone', '', 'Bye.']);
    expect(reply.text, '1. Inspect\n2. Write Done.\n\nBye.');
    expect(
      resultJson(_done(), reply.text)['result'],
      '1. Inspect\n2. Write Done.\n\nBye.',
    );
  });

  test('only an ended turn counts as a finished answer', () {
    expect(failureOf(_done()), isNull);
    expect(failureOf(_done('max_tokens')), 'The agent stopped: max_tokens.');
    expect(failureOf(_done('cancelled')), 'The turn was cancelled.');
    expect(
      failureOf(
        const OneshotOutcome(sessionId: 's', result: TurnFailed('It broke.')),
      ),
      'It broke.',
    );
  });

  test('the JSON result names what Claude Code names', () {
    expect(
      resultJson(
        const OneshotOutcome(
          sessionId: 'session-1',
          result: TurnAnswered('end_turn'),
          usage: {'inputTokens': 10, 'outputTokens': 2, 'cachedReadTokens': 5},
          cost: (amount: 0.5, currency: 'USD'),
        ),
        'Hi.',
      ),
      {
        'type': 'result',
        'is_error': false,
        'result': 'Hi.',
        'session_id': 'session-1',
        'stop_reason': 'end_turn',
        'usage': {
          'input_tokens': 10,
          'output_tokens': 2,
          'cache_read_input_tokens': 5,
        },
        'total_cost_usd': 0.5,
      },
    );
    expect(
      resultJson(
        const OneshotOutcome(
          sessionId: 's',
          result: TurnFailed('It broke.'),
          cost: (amount: 3, currency: 'EUR'),
        ),
        '',
      ),
      {
        'type': 'result',
        'is_error': true,
        'result': '',
        'session_id': 's',
        'cost': {'amount': 3, 'currency': 'EUR'},
        'error': 'It broke.',
      },
    );
    expect(
      resultJson(
        const OneshotOutcome(
          sessionId: 's',
          result: TurnAnswered('end_turn'),
          cost: (amount: 0.01, currency: 'USD'),
          costEstimated: true,
        ),
        '',
      ),
      containsPair('cost_estimated', true),
    );
  });

  test("a notice's line is cleaned and folded to one, its description left "
      'out when it has none', () {
    expect(
      noticeLine(
        title: '\x1b[1mMCP server\x1b[0m failed',
        description: 'one\n\n  two',
      ),
      'chord: MCP server failed: one two\n',
    );
    expect(noticeLine(title: 'Alone'), 'chord: Alone\n');
  });

  test('permission and form lines name what was refused, allowed or '
      'skipped', () {
    expect(
      refusalLine({'toolCallId': 'c1', 'title': 'Write notes.txt'}),
      'chord: refused Write notes.txt: -p cannot ask for permission.\n',
    );
    expect(refusalLine({'toolCallId': 'c1'}), contains('refused c1:'));
    expect(
      allowedLine({'toolCallId': 'c1', 'title': 'Write notes.txt'}),
      'chord: allowed Write notes.txt.\n',
    );
    expect(
      skippedLines('fake', message: 'Pick', questions: ['One?', 'Two?']),
      'chord: fake asked: One? — skipped (no one to answer under -p)\n'
      'chord: fake asked: Two? — skipped (no one to answer under -p)\n',
    );
    expect(
      skippedLines('fake', message: 'Fill this in'),
      'chord: fake asked: Fill this in — skipped (no one to answer under -p)\n',
    );
  });
}
