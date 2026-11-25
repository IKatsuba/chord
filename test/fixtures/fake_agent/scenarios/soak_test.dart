import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../turn.dart';
import 'soak.dart';

void main() {
  group('tester: CTUI-147 bounded soak session counters', () {
    test(
      'interleaved sessions count their own replies and keep calls paired',
      () {
        options.args = ['--step-ms', '1'];
        fakeAsync((clock) {
          final input = StreamController<List<int>>();
          final messages = <Map>[];
          final connection = Connection.serve(
            input.stream,
            (bytes) {
              final message = jsonDecode(utf8.decode(bytes)) as Map;
              messages.add(message['params'] as Map);
            },
            () async {},
            requests: {},
            notifications: {},
          );
          var finished = 0;
          Future<void> play(String id) async {
            expect(
              await soak['soakturn']!(
                Turn(connection.client, id, Aborter().signal),
              ),
              'end_turn',
            );
            finished++;
          }

          unawaited(play('tester-soak-a'));
          unawaited(play('tester-soak-b'));
          clock.elapse(const Duration(seconds: 1));
          expect(finished, 2);
          unawaited(play('tester-soak-a'));
          clock.elapse(const Duration(seconds: 1));
          expect(finished, 3);
          for (final (id, turns) in [
            ('tester-soak-a', 2),
            ('tester-soak-b', 1),
          ]) {
            final updates = [
              for (final message in messages)
                if (message['sessionId'] == id) message['update'] as Map,
            ];
            final headings = [
              for (final update in updates)
                if (update['content'] case {
                  'type': 'text',
                  'text': final String text,
                } when text.startsWith('## Turn '))
                  text,
            ];
            expect(headings, [
              for (var n = 1; n <= turns; n++) '## Turn $n\n\n',
            ]);
            final calls = [
              for (final update in updates)
                if (update['sessionUpdate'] == 'tool_call')
                  update['toolCallId'],
            ];
            final ends = [
              for (final update in updates)
                if (update['sessionUpdate'] == 'tool_call_update')
                  update['toolCallId'],
            ];
            expect(calls, hasLength(turns));
            expect(ends, calls);
          }
          connection.close();
          unawaited(input.close());
          clock.flushMicrotasks();
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
