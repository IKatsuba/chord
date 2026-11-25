import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:chord/session/subagents.dart' show Heard;
import 'package:test/test.dart';

Map<String, Object?> _prompt(String id, String text) => {
  'type': 'prompt',
  'turnId': id,
  'at': 1.25,
  'prompt': text,
  'images': 0,
};
Transcript _fold(PreparedHistory past) =>
    past.actions.fold(Transcript.empty, reduceTranscript);

/// [updates], each the session's own as it heard them.
List<Heard> own(List<acp.SessionUpdate> updates) => [
  for (final update in updates) (update: update, subagentId: null),
];

void main() {
  group('CTUI-26 U3b tester: malformed boundaries and historical results', () {
    test(
      'malformed supported entries preserve later valid turns and omission fact',
      () {
        final broken = <Object?>[
          null,
          [],
          5,
          {'type': 'opened', 'at': 'wrong'},
          {
            'type': 'prompt',
            'turnId': 'bad',
            'prompt': 'bad',
            'at': 1,
            'images': 'wrong',
          },
          {'type': 'cancel', 'turnId': 'bad', 'at': 'wrong'},
          {'type': 'disconnected', 'at': 'wrong'},
          {
            'type': 'result',
            'turnId': 'bad',
            'result': {
              'status': 'failed',
              'error': {'message': 1},
            },
          },
          {
            'type': 'update',
            'turnId': 'bad',
            'update': {
              'sessionUpdate': 'plan',
              'entries': [
                {'content': 3},
              ],
            },
          },
          {
            'type': 'update',
            'turnId': 'bad',
            'update': {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'tool',
              'content': 'wrong',
            },
          },
          {
            'type': 'update',
            'turnId': 'bad',
            'update': {
              'sessionUpdate': 'agent_thought_chunk',
              'content': {'type': 'text', 'text': 3},
            },
          },
        ];
        for (final bad in broken) {
          final past = recordActions([
            _prompt('first', 'first'),
            bad,
            _prompt('next', '界👩‍💻é'),
            {
              'type': 'update',
              'turnId': 'next',
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'survives'},
              },
            },
          ]);
          expect(past.omitted, isTrue, reason: '$bad');
          final transcript = _fold(PreparedHistory.fromJson(past.toJson()));
          expect(transcript.entries.whereType<UserEntry>().map((e) => e.text), [
            'first',
            '界👩‍💻é',
          ]);
          expect(
            transcript.entries
                .whereType<AssistantEntry>()
                .single
                .text
                .toString(),
            'survives',
          );
          expect(transcript.turn, isA<Idle>());
        }
      },
    );

    test(
      'raw error codes survive conversion and worker JSON without numeric loss',
      () {
        for (final code in ['0', '-32000', '9' * 100, 'reason/text']) {
          final past = recordActions([
            _prompt('turn', 'ask'),
            {
              'type': 'result',
              'turnId': 'turn',
              'result': {
                'status': 'failed',
                'error': {'message': 'refused', 'code': code},
              },
            },
          ]);
          final copied = PreparedHistory.fromJson(
            jsonDecode(jsonEncode(past.toJson())) as Map<String, Object?>,
          );
          final converted = historyEntries(copied.actions);
          final result = converted.last['result'] as Map;
          expect((result['error'] as Map)['code'], code);
          expect(copied.omitted, int.tryParse(code) == null);
          expect(
            _fold(copied).entries.whereType<ErrorEntry>().single.message,
            'refused',
          );
        }
      },
    );

    test(
      'agent-loaded unsupported blocks flag omission without swallowing the next user',
      () {
        final past = pastActions(
          own([
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'user_message_chunk',
              'content': {'type': 'future', 'value': true},
            }),
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'first reply'},
            }),
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'user_message_chunk',
              'content': {'type': 'text', 'text': 'next 界🙂'},
            }),
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'next reply'},
            }),
          ]),
          3.75,
        );
        expect(past.omitted, isTrue);
        final transcript = _fold(past);
        expect(transcript.entries.whereType<UserEntry>().last.text, 'next 界🙂');
        expect(
          transcript.entries.whereType<AssistantEntry>().map(
            (e) => e.text.toString(),
          ),
          ['first reply', 'next reply'],
        );
        expect(transcript.turn, isA<Idle>());
      },
    );

    test(
      'cancellation after requesting preparation leaves bytes unchanged and no worker write',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'chord-replay-tester-',
        );
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final file = File(p.join(dir.path, 'history.jsonl'));
        final text = encodeRecord(_prompt('turn', 'fixture'));
        await file.writeAsString(text);
        final token = CancellationToken();
        final pending = readRecordedHistory(
          file.path,
          cancellationToken: token,
        );
        final checked = expectLater(
          pending,
          throwsA(isA<CancelledException>()),
        );
        token.cancel();
        await checked;
        expect(await file.readAsString(), text);
        await dir.delete(recursive: true);
        await Future<void>.delayed(Duration.zero);
        expect(await dir.exists(), isFalse);
      },
    );
  });
}
