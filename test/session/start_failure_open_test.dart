import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_failure.dart';
import 'package:test/test.dart';

import 'reopen_session_test.dart' show directory;

class Script {
  Script(this.step, {this.code = -32602, this.exit, this.hang = false}) {
    process = MemoryAgentProcess(onSignal: (_) => stop());
  }
  final StartStep step;
  final int code;
  final Exit? exit;
  final bool hang;
  late final MemoryAgentProcess process;
  final reached = Completer<void>();

  void stop() {
    process.exit();
    process.closeStdout();
    process.closeStderr();
  }

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
        onTraffic: (traffic) {
          onTraffic(traffic);
          if (traffic case ChordTraffic(message: final request)) {
            final id = request['id'];
            if (id == null || process.exited) return;
            if (request['method'] == step.method) {
              if (!reached.isCompleted) reached.complete();
              if (hang) return;
              if (exit != null) {
                process.exit(exit!);
                process.closeStdout();
                process.closeStderr();
              } else {
                process.send({
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': {'code': code, 'message': 'scripted refusal'},
                });
              }
            } else {
              process.send({
                'jsonrpc': '2.0',
                'id': id,
                'result': request['method'] == 'initialize'
                    ? {
                        'protocolVersion': 1,
                        'agentCapabilities': {
                          'loadSession': step != StartStep.resumeSession,
                          'sessionCapabilities': {
                            if (step == StartStep.resumeSession)
                              'resume': <String, Object?>{},
                            if (step == StartStep.forkSession)
                              'fork': <String, Object?>{},
                          },
                        },
                      }
                    : {'sessionId': 'saved'},
              });
            }
          }
        },
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
        stop: const StopBounds(
          exit: Duration.zero,
          term: Duration(milliseconds: 10),
          kill: Duration(milliseconds: 100),
        ),
      );
}

void main() {
  for (final step in StartStep.values) {
    for (final code in [-32602, -32601, -32000]) {
      test('${step.method} captures RPC facts before cleanup $code', () async {
        final dir = await directory();
        final script = Script(step, code: code);
        Object? error;
        try {
          await openSession(
            agent: 'script',
            command: 'script',
            cwd: dir.path,
            resume:
                step == StartStep.loadSession || step == StartStep.resumeSession
                ? Resume(sessionId: 'saved', cwd: dir.path)
                : null,
            fork: step == StartStep.forkSession ? 'saved' : null,
            open: script.open,
          );
        } catch (caught) {
          error = caught;
        }
        expect(error, isNotNull);
        final facts = startFailureOf(error!);
        expect(facts?.step, step);
        expect(facts?.code, code);
        expect(facts?.said, 'scripted refusal');
        expect(
          facts?.exit,
          isNull,
          reason: 'cleanup exit must not replace RPC refusal',
        );
        expect(script.process.exited, isTrue);
        expect(script.process.stdin.addsAfterClose, 0);
        if (step == StartStep.loadSession || step == StartStep.resumeSession) {
          expect(error, isA<ResumeError>());
        }
        expect(
          startupWords(error),
          code == -32000
              ? startMessage(error)
              : code == -32601 && step != StartStep.initialize
              ? 'it does not serve ACP sessions: not an ACP agent, or not at this version.'
              : 'it refused ${step.method}: scripted refusal',
        );
      });
    }

    test('${step.method} retains observed exit through cleanup', () async {
      final dir = await directory();
      final script = Script(step, exit: const Exit(7));
      Object? error;
      try {
        await openSession(
          agent: 'script',
          command: 'script',
          cwd: dir.path,
          resume:
              step == StartStep.loadSession || step == StartStep.resumeSession
              ? Resume(sessionId: 'saved', cwd: dir.path)
              : null,
          // The fork step is reached forking a session that is up.
          fork: step == StartStep.forkSession ? 'saved' : null,
          open: script.open,
        );
      } catch (caught) {
        error = caught;
      }
      expect(error, isNotNull);
      expect(startFailureOf(error!)?.exit, const Exit(7));
      expect(
        startupWords(error),
        'it exited with code 7 before answering ${step.method}.',
      );
      expect(script.process.exited, isTrue);
    });

    test(
      '${step.method} cancellation bypasses visible startup classification',
      () async {
        final dir = await directory();
        final script = Script(step, hang: true);
        final token = CancellationToken();
        final opening = openSession(
          agent: 'script',
          command: 'script',
          cwd: dir.path,
          resume:
              step == StartStep.loadSession || step == StartStep.resumeSession
              ? Resume(sessionId: 'saved', cwd: dir.path)
              : null,
          // The fork step is reached forking a session that is up.
          fork: step == StartStep.forkSession ? 'saved' : null,
          open: script.open,
          cancellationToken: token,
        );
        final checked = expectLater(
          opening,
          throwsA(isA<CancelledException>()),
        );
        await script.reached.future;
        token.cancel();
        await checked;
        expect(script.process.exited, isTrue);
        expect(script.process.stdin.addsAfterClose, 0);
      },
    );
  }
}
