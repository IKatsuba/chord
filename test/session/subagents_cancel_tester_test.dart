@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/permissions.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

// This fixture test names Dart directly while ordinary callers stay
// on the original until every prompt scenario is ported.
Future<void> _withDartSubagent(
  Future<void> Function(Session session, TrafficRecorder traffic) body,
) async {
  final directory = Directory.systemTemp.createTempSync('chord-dart-subagent-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final traffic = TrafficRecorder();
  final pids = <int>[];
  final session = await openSession(
    agent: 'fake',
    command: dartFakeCommand('codexsubagentstop', ['--step-ms', '1']),
    cwd: directory.path,
    open: fakeOpenerWith(
      onPid: pids.add,
      capabilities: acp.ClientCapabilities.fromJson({
        'subagents': <String, Object?>{},
      }),
    ),
    onTraffic: traffic.add,
  );
  try {
    expect(pids, hasLength(1));
    await body(session, traffic);
  } finally {
    await session.close();
    await session.exited;
    expect(
      pids.where((id) => Process.runSync('kill', ['-0', '$id']).exitCode == 0),
      isEmpty,
    );
  }
}

void main() {
  group('tester: CTUI-147 Dart fake own-id stop through the session', () {
    test(
      'stopping the child sends only its id and the parent answers again',
      () async {
        await _withDartSubagent((session, traffic) async {
          final announced = traffic.next(
            (event) => switch (event) {
              AgentTraffic(
                message: {
                  'method': 'session/update',
                  'params': {
                    'update': {
                      'sessionUpdate': 'subagent_update',
                      'capabilities': {'cancel': Map()},
                    },
                  },
                },
              ) =>
                true,
              _ => false,
            },
          );
          final turn = session.prompt('codexsubagentstop');
          final message = (await announced as AgentTraffic).message;
          final childId =
              ((message['params'] as Map)['update'] as Map)['sessionId']
                  as String;
          expect(childId, isNot(session.id));
          await session.stopSubagent(childId);
          expect(
            await turn.result,
            isA<TurnAnswered>().having(
              (answer) => answer.cancelled,
              'cancelled',
              isFalse,
            ),
          );
          final cancels = [
            for (final event in traffic.heard)
              if (event case ChordTraffic(
                :final message,
              ) when message['method'] == 'session/cancel')
                (message['params'] as Map)['sessionId'],
          ];
          expect(cancels, [childId]);
          final later = await run(session, 'verbatim still usable');
          expect(later.result, isA<TurnAnswered>());
          expect(said(later.updates).join(), contains('still usable'));
        });
      },
    );
  });

  group('tester subagent cancellation ownership', skip: fakeAgentSkip, () {
    for (final bySession in [false, true]) {
      test(
        '${bySession ? 'session' : 'turn'} cancel withdraws child ask with one root notification',
        () async {
          await withSession(
            capabilities: acp.ClientCapabilities.fromJson({
              'subagents': <String, Object?>{},
            }),
            (session, traffic) async {
              final asked = Completer<PendingPermission>();
              session.permissions.subscribe(asked.complete);
              final turn = session.prompt('claudesubagents');
              final pending = await asked.future.timeout(
                const Duration(seconds: 20),
              );
              expect(pending.sessionId, isNot(session.id));
              if (bySession) {
                await session.cancel();
              } else {
                await turn.cancel();
              }
              expect(pending.withdrawn.isCancelled, isTrue);
              expect(
                await turn.result,
                isA<TurnAnswered>().having(
                  (r) => r.cancelled,
                  'cancelled',
                  true,
                ),
              );
              final cancels = [
                for (final event in traffic.heard)
                  if (event case ChordTraffic(
                    :final message,
                  ) when message['method'] == 'session/cancel')
                    message,
              ];
              expect(cancels, hasLength(1));
              expect(
                (cancels.single['params'] as Map)['sessionId'],
                session.id,
              );
              pending.resolve('allow');
            },
          );
        },
      );
    }
  });
}
