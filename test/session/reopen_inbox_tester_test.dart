import 'dart:convert';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/inbox.dart';
import 'package:fake_async/fake_async.dart';
import 'package:chord/session/subagents.dart' show Heard;
import 'package:test/test.dart';

import '../acp/connection_test.dart' show Harness;
import 'reopen_inbox_test.dart'
    show answer, notification, reply, request, textOf;

void main() {
  group('CTUI-26 U3a tester: byte partitions and independent ownership', () {
    for (final method in ['session/load', 'session/resume']) {
      test(
        '$method partitions Unicode history and live at every byte split',
        () {
          const before = 'HISTORY 界👩‍💻é \u001b[31m';
          const after = 'LIVE 界🙂é';
          final sample = utf8.encode(
            [
              notification(before),
              {'jsonrpc': '2.0', 'id': 2, 'result': <String, Object?>{}},
              notification(after),
            ].map((frame) => '${jsonEncode(frame)}\n').join(),
          );
          for (var split = 0; split <= sample.length; split++) {
            fakeAsync((async) {
              final inbox = SessionInbox();
              final h = Harness(onTraffic: inbox.hear);
              final agent = h.open(
                async,
                init: {
                  'protocolVersion': 1,
                  'agentCapabilities': {
                    'loadSession': true,
                    'sessionCapabilities': {'resume': <String, Object?>{}},
                  },
                },
              );
              inbox.beginReopen(method, 'literal/id');
              final params = acp.ReopenSessionRequest(
                sessionId: 'literal/id',
                cwd: 'fixture-project',
                mcpServers: const [],
              );
              List<Heard>? history;
              final opened = method == 'session/load'
                  ? agent.loadSession(params)
                  : agent.resumeSession(params);
              opened.then((response) {
                history = inbox.completeReopen(response, rawHasPast: false);
              });
              async.flushMicrotasks();
              final bytes = utf8.encode(
                [
                  notification(before),
                  {
                    'jsonrpc': '2.0',
                    'id': h.lastRequest(method)['id'],
                    'result': <String, Object?>{},
                  },
                  notification(after),
                ].map((frame) => '${jsonEncode(frame)}\n').join(),
              );
              expect(bytes.length, sample.length);
              h.process.writeStdout(bytes.sublist(0, split));
              async.flushMicrotasks();
              h.process.writeStdout(bytes.sublist(split));
              async.flushMicrotasks();
              final live = <String>[];
              inbox.subscribe((u) => live.add(textOf(u)));
              expect(
                history!.map((heard) => textOf(heard.update)),
                method == 'session/load' ? [before] : isEmpty,
                reason: 'split $split',
              );
              expect(
                live,
                method == 'session/load' ? [after] : [before, after],
                reason: 'split $split',
              );
              inbox.close();
              agent.close().ignore();
              async.elapse(const Duration(seconds: 3));
              expect(h.process.exited, isTrue);
            });
          }
        },
      );
    }

    test(
      'closing during a thousand retained updates cannot disturb another inbox',
      () {
        final old = SessionInbox()..beginReopen('session/resume', 'literal/id');
        final current = SessionInbox()
          ..beginReopen('session/resume', 'literal/id');
        old.hear(request('session/resume', 1));
        current.hear(request('session/resume', 1));
        for (var i = 0; i < 1000; i++) {
          old.hear(Traffic.agent(notification('old $i')));
          current.hear(Traffic.agent(notification('current $i')));
        }
        old.hear(reply(1));
        current.hear(reply(1));
        old.completeReopen(answer(), rawHasPast: true);
        current.completeReopen(answer(), rawHasPast: true);
        final stopped = <String>[], retained = <String>[];
        old.subscribe((u) {
          stopped.add(textOf(u));
          if (stopped.length == 500) {
            old.close();
            current.hear(
              Traffic.agent(notification('current during old close')),
            );
          }
        });
        current.subscribe((u) => retained.add(textOf(u)));
        old.hear(Traffic.agent(notification('old late')));
        current.hear(Traffic.agent(notification('current live')));
        expect(stopped, [for (var i = 0; i < 500; i++) 'old $i']);
        expect(retained, [
          for (var i = 0; i < 1000; i++) 'current $i',
          'current during old close',
          'current live',
        ]);
        current.close();
      },
    );
  });
}
