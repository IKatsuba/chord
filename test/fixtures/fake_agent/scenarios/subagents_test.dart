import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../client.dart' as capabilities;
import '../options.dart' as options;
import '../rpc.dart';
import '../turn.dart';
import 'subagents.dart';

final class _Updates {
  _Updates() {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        final params = (message['params'] as Map).cast<String, Object?>();
        messages.add(params);
        events.add(params);
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final input = StreamController<List<int>>();
  final events = StreamController<Map<String, Object?>>.broadcast();
  final messages = <Map<String, Object?>>[];
  late final Connection connection;

  Future<Map<String, Object?>> cancelable(String parent) =>
      events.stream.firstWhere((params) {
        final update = params['update'] as Map;
        return params['sessionId'] == parent &&
            update['sessionUpdate'] == 'subagent_update' &&
            update['capabilities'] is Map &&
            (update['capabilities'] as Map)['cancel'] is Map;
      });

  List<Map> ended(String child) => [
    for (final params in messages)
      if (params['update'] case final Map update)
        if (update['sessionId'] == child &&
            update['state'] is Map &&
            (update['state'] as Map)['state'] == 'idle')
          update,
  ];

  Future<void> close() async {
    await input.close();
    await connection.closed;
    await events.close();
  }
}

void main() {
  group('tester: CTUI-147 subagent stop ownership and lifetime', () {
    setUp(() {
      options.args = ['--step-ms', '0'];
      capabilities.clientTakesSubagents = true;
    });
    tearDown(() => expect(claudeChildren, isEmpty));

    for (final scenario in ['subagent', 'claudesubagents', 'codexsubagents']) {
      test(
        '$scenario without capability emits only its fallback text',
        () async {
          capabilities.clientTakesSubagents = false;
          final updates = _Updates();
          addTearDown(updates.close);
          expect(
            await subagents[scenario]!(
              Turn(updates.connection.client, 'root', Aborter().signal),
            ),
            'end_turn',
          );
          expect(updates.messages, hasLength(1));
          expect((updates.messages.single['update'] as Map)['content'], {
            'type': 'text',
            'text': 'Subagents go only to a client that takes them.',
          });
        },
      );
    }

    test(
      'a repeated own-id stop ends the child once and leaves the parent usable',
      () async {
        final updates = _Updates();
        addTearDown(updates.close);
        final ready = updates.cancelable('root');
        final abort = Aborter();
        final playing = subagents['codexsubagentstop']!(
          Turn(updates.connection.client, 'root', abort.signal),
        );
        final id = ((await ready)['update'] as Map)['sessionId'] as String;
        final stop = claudeChildren[id]!;
        await stop();
        await stop();
        expect(await playing, 'end_turn');
        expect(abort.signal.aborted, isFalse);
        expect(updates.ended(id), hasLength(1));
        expect(updates.ended(id).single['state'], {
          'state': 'idle',
          'stopReason': 'cancelled',
        });
        expect((updates.messages.last['update'] as Map)['content'], {
          'type': 'text',
          'text': 'It stopped, and the turn goes on.',
        });
        expect(claudeChildren.containsKey(id), isFalse);
      },
    );

    test(
      'parent cancellation ends its child and removes its pending stop',
      () async {
        final updates = _Updates();
        addTearDown(updates.close);
        final ready = updates.cancelable('root');
        final abort = Aborter();
        final reason = StateError('parent cancelled');
        final playing = subagents['codexsubagentstop']!(
          Turn(updates.connection.client, 'root', abort.signal),
        );
        final failed = expectLater(playing, throwsA(same(reason)));
        final id = ((await ready)['update'] as Map)['sessionId'] as String;
        abort.abort(reason);
        await failed;
        expect(updates.ended(id), hasLength(1));
        expect(updates.ended(id).single['state'], {
          'state': 'idle',
          'stopReason': 'cancelled',
        });
        expect(claudeChildren.containsKey(id), isFalse);
      },
    );

    test(
      'stopping one session child leaves another waiting until its parent cancels',
      () async {
        final updates = _Updates();
        addTearDown(updates.close);
        final readyFirst = updates.cancelable('first');
        final readySecond = updates.cancelable('second');
        final secondAbort = Aborter();
        final first = subagents['codexsubagentstop']!(
          Turn(updates.connection.client, 'first', Aborter().signal),
        );
        final second = subagents['codexsubagentstop']!(
          Turn(updates.connection.client, 'second', secondAbort.signal),
        );
        final secondFailed = expectLater(second, throwsA(isA<AbortError>()));
        final firstId =
            ((await readyFirst)['update'] as Map)['sessionId'] as String;
        final secondId =
            ((await readySecond)['update'] as Map)['sessionId'] as String;
        expect(firstId, isNot(secondId));
        await claudeChildren[firstId]!();
        expect(await first, 'end_turn');
        expect(updates.ended(secondId), isEmpty);
        expect(claudeChildren.containsKey(secondId), isTrue);
        secondAbort.abort();
        await secondFailed;
        expect(updates.ended(firstId), hasLength(1));
        expect(updates.ended(secondId), hasLength(1));
      },
    );
  });
}
