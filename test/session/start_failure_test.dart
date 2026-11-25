import 'package:chord/acp/connection.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_failure.dart';
import 'package:test/test.dart';

void main() {
  _testerStartupFailureBoundaries();
  for (final step in StartStep.values) {
    test('${step.method} preserves original startup precedence', () {
      const message = 'original words';
      expect(stepWords(message, null), message);
      expect(stepWords(message, StartFailure(step: step)), message);
      expect(
        stepWords(
          message,
          StartFailure(step: step, code: -32000, said: 'raw auth'),
        ),
        message,
      );
      expect(
        stepWords(
          message,
          StartFailure(step: step, code: -32602, said: 'agent said'),
        ),
        'it refused ${step.method}: agent said',
      );
      expect(
        stepWords(message, StartFailure(step: step, code: -32602)),
        'it refused ${step.method}: original words',
      );
      expect(
        stepWords(message, StartFailure(step: step, code: -32601)),
        step == StartStep.initialize
            ? 'it refused initialize: original words'
            : 'it does not serve ACP sessions: not an ACP agent, or not at this version.',
      );
      expect(
        stepWords(
          message,
          StartFailure(step: step, exit: const Exit(7), code: -32602),
        ),
        'it exited with code 7 before answering ${step.method}.',
      );
      expect(
        stepWords(
          message,
          StartFailure(
            step: step,
            exit: const Exit(143, 'SIGTERM'),
            code: -32000,
          ),
        ),
        'it was stopped by SIGTERM before answering ${step.method}.',
      );
      expect(
        stepWords(
          message,
          StartFailure(
            step: step,
            closed: true,
            exit: const Exit(7),
            code: -32602,
          ),
        ),
        'it closed its connection before answering ${step.method}.',
      );
    });
  }

  test('capture keeps refusal code, words and originating cause', () {
    final error = RpcException(-32602, 'it exited with code 7');
    final failed = startFailed(error, StartStep.newSession);
    expect(failed.cause, same(error));
    expect(failed.failure.code, -32602);
    expect(failed.failure.exit, isNull);
    expect(failed.failure.closed, isFalse);
    expect(
      startupWords(failed),
      'it refused session/new: it exited with code 7',
    );
  });

  test(
    'gone facts and stderr survive without inferring a later cleanup exit',
    () {
      const tail = Tail(['retained stderr'], 3);
      for (final exit in [null, const Exit(2), const Exit(143, 'SIGTERM')]) {
        final error = AgentGone('raw process words', exit, tail);
        final failed = startFailed(error, StartStep.loadSession);
        expect(failed.failure.exit, same(exit));
        expect(failed.failure.closed, exit == null);
        expect(failed.failure.stderr, same(tail));
        expect(failed.failure.code, isNull);
        expect(failed.cause, same(error));
      }
    },
  );

  test('resume wrapper retains context for auth and uncoded failures only', () {
    for (final code in [-32000, -32602, -32601]) {
      final original = RpcException(code, 'raw refusal');
      final failed = startFailed(original, StartStep.resumeSession);
      final wrapped = ResumeError(
        'it cannot resume session saved: raw refusal',
        cause: failed,
      );
      expect(startFailureOf(wrapped), same(failed.failure));
      expect(startMessage(wrapped), wrapped.message);
      expect(startupWords(wrapped), switch (code) {
        -32000 => wrapped.message,
        -32601 =>
          'it does not serve ACP sessions: not an ACP agent, or not at this version.',
        _ => 'it refused session/resume: raw refusal',
      });
    }
    const plain = ResumeError('raw local ownership refusal');
    expect(startFailureOf(plain), isNull);
    expect(startupWords(plain), plain.message);
  });
}

void _testerStartupFailureBoundaries() {
  group('tester: U52c structural failure boundaries', () {
    test('zero exit remains structural and beats auth refusal words', () {
      for (final step in StartStep.values) {
        final gone = AgentGone(
          'Authentication required',
          const Exit(0),
          const Tail([], 0),
        );
        final failed = startFailed(gone, step);
        expect(failed.failure.exit, const Exit(0));
        expect(failed.failure.closed, isFalse);
        expect(failed.cause, same(gone));
        expect(
          stepWords(
            'auth context',
            StartFailure(step: step, exit: failed.failure.exit, code: -32000),
          ),
          'it exited with code 0 before answering ${step.method}.',
        );
      }
    });

    test(
      'empty said and numeric codes preserve original nullish semantics',
      () {
        for (final step in StartStep.values) {
          for (final code in <num>[0, -32000.5, 1 << 60]) {
            final facts = StartFailure(step: step, code: code, said: '');
            expect(facts.code, code);
            expect(stepWords('fallback', facts), 'it refused ${step.method}: ');
          }
        }
      },
    );

    test(
      'a thousand supported resume wrappers retain the same failure facts',
      () {
        final original = RpcException(-32602, '界🙂é refusal');
        final failed = startFailed(original, StartStep.loadSession);
        Object wrapped = failed;
        for (var i = 0; i < 1000; i++) {
          wrapped = ResumeError('outer $i', cause: wrapped);
        }
        expect(startFailureOf(wrapped), same(failed.failure));
        expect(startMessage(wrapped), 'outer 999');
        expect(startupWords(wrapped), 'it refused session/load: 界🙂é refusal');
        expect(failed.cause, same(original));
      },
    );

    test(
      'format and local capability words never fabricate protocol facts',
      () {
        for (final error in <Object>[
          const FormatException(
            'it exited with code 9 before answering session/new',
          ),
          const AgentCapabilityError('session/load'),
          const ResumeError('it was stopped by SIGTERM'),
        ]) {
          final failed = startFailed(error, StartStep.initialize);
          expect(failed.failure.closed, isFalse);
          expect(failed.failure.exit, isNull);
          expect(failed.failure.code, isNull);
          expect(startupWords(failed), startMessage(error));
          expect(failed.cause, same(error));
        }
      },
    );
  });
}
