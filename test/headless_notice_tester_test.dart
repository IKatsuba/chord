import 'dart:async';
import 'dart:convert';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/session.dart' show SessionOpener;
import 'package:chord/headless.dart';
import 'package:chord/notices.dart';
import 'package:chord/session/oneshot.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'session/oneshot_notice_test.dart' show NoticeAgent;

void main() {
  group('tester CTUI-161: agent notice delivery boundaries', () {
    for (final format in ['text', 'json']) {
      test('$format cleans actual updates and retains repeated notices', () {
        final agent = _AgentNotices([
          {'title': '\x1b[31m界👩‍💻é\x1b[0m', 'description': 'one\n two'},
          {'title': 'Alone', 'description': null},
          {'title': 'Alone', 'description': ''},
        ]);
        final out = StringBuffer(), err = StringBuffer();
        fakeAsync((async) {
          agent.drive(
            async,
            agent.run(format, out, (text) async => err.write(text)),
          );
        });
        expect(
          '$err',
          'chord: 界👩‍💻é: one two\nchord: Alone\nchord: Alone\n',
        );
        expect(
          format == 'json' ? (jsonDecode('$out') as Map)['result'] : '$out',
          format == 'json' ? 'reply' : 'reply\n',
        );
      });

      test('$format drains a thousand notices before returning', () {
        final agent = _AgentNotices([
          for (var i = 0; i < 1000; i++) {'title': 'notice $i'},
        ], stopReason: 'cancelled');
        final out = StringBuffer(), err = StringBuffer();
        fakeAsync((async) {
          agent.drive(
            async,
            agent.run(format, out, (text) async => err.write(text)),
          );
        });
        expect(
          '$err',
          "${[for (var i = 0; i < 1000; i++) 'chord: notice $i\n'].join()}"
              'chord: The turn was cancelled.\n',
        );
        expect('$out', isNot(contains('notice')));
        if (format == 'json') {
          expect((jsonDecode('$out') as Map)['is_error'], isTrue);
        }
      });
    }

    test('a held stderr callback blocks later notice and reply delivery', () {
      final agent = _AgentNotices([
        {'title': 'first'},
        {'title': 'second'},
      ]);
      final out = StringBuffer(), delivered = <String>[];
      fakeAsync((async) {
        final release = Completer<void>();
        final run = agent.run('text', out, (text) async {
          delivered.add(text);
          if (delivered.length == 1) await release.future;
        });
        for (var i = 0; i < 10; i++) {
          async.flushMicrotasks();
          agent.step();
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(delivered, ['chord: first\n']);
        expect('$out', isEmpty);
        release.complete();
        agent.drive(async, run);
      });
      expect(delivered, ['chord: first\n', 'chord: second\n']);
      expect('$out', 'reply\n');
    });

    test('simultaneous invocations retain their own notice and reply', () {
      final agents = [
        _AgentNotices([
          {'title': 'one'},
        ]),
        _AgentNotices([
          {'title': 'two'},
        ]),
      ];
      final outs = [StringBuffer(), StringBuffer()];
      final errs = [StringBuffer(), StringBuffer()];
      fakeAsync((async) {
        var done = false;
        Future.wait([
          for (var i = 0; i < agents.length; i++)
            agents[i].run('json', outs[i], (text) async => errs[i].write(text)),
        ]).then((_) => done = true);
        for (var i = 0; i < 300 && !done; i++) {
          async.flushMicrotasks();
          for (final agent in agents) {
            agent.step();
          }
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(done, isTrue);
      });
      expect(errs.map((e) => '$e'), ['chord: one\n', 'chord: two\n']);
      for (var i = 0; i < agents.length; i++) {
        expect((jsonDecode('${outs[i]}') as Map)['result'], 'reply');
        expect(agents[i].process.exited, isTrue);
      }
    });
  });
  group('tester CTUI-101: no-screen notice ordering', () {
    test('JSON stays parseable and each invocation says the notice anew', () {
      for (var run = 0; run < 2; run++) {
        final agent = NoticeAgent(start: 'full-access');
        final out = StringBuffer(), err = StringBuffer();
        fakeAsync((async) {
          agent.drive(
            async,
            runHeadless(
              agent: 'dimcode',
              command: 'memory',
              cwd: '/w',
              prompt: 'hello',
              format: 'json',
              open: agent.open,
              stdout: (text) async => out.write(text),
              stderr: (text) async => err.write(text),
            ),
          );
        });
        final value = jsonDecode('$out') as Map;
        expect(value['result'], 'beforeafter');
        expect(
          '$err',
          '${dimcodeWords.paragraphs.map((p) => 'chord: $p').join('\n')}\n',
        );
        expect('$out', isNot(contains(dimcodeWords.title)));
      }
    });

    test('a delayed notice callback holds later reply delivery in order', () {
      final agent = NoticeAgent(start: 'read-only', moves: ['full-access']);
      final delivered = <String>[];
      fakeAsync((async) {
        final release = Completer<void>();
        final run = runOneshot(
          agent: 'dimcode',
          command: 'memory',
          cwd: '/w',
          prompt: 'hello',
          open: agent.open,
          onRefused: (_) {},
          onNotice: (_) async {
            delivered.add('notice start');
            await release.future;
            delivered.add('notice end');
          },
          onUpdate: (update) {
            if (update.toJson()['content'] case {'text': final String text}) {
              delivered.add(text);
            }
          },
        );
        for (var step = 0; step < 8; step++) {
          async.flushMicrotasks();
          agent.step();
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(delivered, ['before', 'notice start']);
        release.complete();
        agent.drive(async, run.then((_) {}));
      });
      expect(delivered, [
        'before',
        'notice start',
        'notice end',
        'moved full-access',
        'after',
      ]);
    });

    test(
      'a burst of permission changes emits one notice and retains every reply',
      () {
        final agent = NoticeAgent(
          start: 'read-only',
          moves: [
            for (var i = 0; i < 1000; i++)
              i.isEven ? 'full-access' : 'read-only',
          ],
        );
        var notices = 0, chunks = 0;
        fakeAsync((async) {
          agent.drive(
            async,
            runOneshot(
              agent: 'dimcode',
              command: 'memory',
              cwd: '/w',
              prompt: 'hello',
              open: agent.open,
              onRefused: (_) {},
              onNotice: (_) => notices++,
              onUpdate: (update) {
                if (update.toJson()['content'] case {'text': final String _}) {
                  chunks++;
                }
              },
            ).then((_) {}),
          );
        });
        expect(notices, 1);
        expect(chunks, 1002);
      },
    );
  });
}

final class _AgentNotices {
  _AgentNotices(this.notices, {this.stopReason = 'end_turn'}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
  }
  final List<Map<String, Object?>> notices;
  final String stopReason;
  late final MemoryAgentProcess process;
  final _answered = <Object?>{};

  SessionOpener get open =>
      ({
        required command,
        env,
        required cwd,
        required onTraffic,
        required onPermission,
        relay,
        cancellationToken,
      }) => connectAgent(
        process,
        onTraffic: onTraffic,
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
      );

  Future<int> run(
    String format,
    StringBuffer out,
    Future<void> Function(String) stderr,
  ) => runHeadless(
    agent: 'memory',
    command: 'memory',
    cwd: '/w',
    prompt: 'hello',
    format: format,
    open: open,
    stdout: (text) async => out.write(text),
    stderr: stderr,
  );

  void step() {
    for (final message in [...process.stdin.messages]) {
      final id = message['id'];
      if (id == null || message['method'] == null || !_answered.add(id)) {
        continue;
      }
      void send(Map<String, Object?> value) =>
          process.send({'jsonrpc': '2.0', ...value});
      switch (message['method']) {
        case 'initialize':
          send({
            'id': id,
            'result': {'protocolVersion': 1},
          });
        case 'session/new':
          send({
            'id': id,
            'result': {'sessionId': 's1'},
          });
        case 'session/prompt':
          for (final notice in notices) {
            send({
              'method': 'session/update',
              'params': {
                'sessionId': 's1',
                'update': {
                  'sessionUpdate': 'notice',
                  'severity': 'info',
                  ...notice,
                },
              },
            });
          }
          send({
            'method': 'session/update',
            'params': {
              'sessionId': 's1',
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'reply'},
              },
            },
          });
          send({
            'id': id,
            'result': {'stopReason': stopReason},
          });
        default:
          send({'id': id, 'result': <String, Object?>{}});
      }
    }
  }

  void drive(FakeAsync async, Future<int> run) {
    var done = false;
    run.then((_) => done = true);
    for (var i = 0; i < 300 && !done; i++) {
      async.flushMicrotasks();
      step();
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
    expect(process.exited, isTrue);
  }
}
