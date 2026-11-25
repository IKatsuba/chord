// A session that starts from another's whole conversation, ACP's
// `session/fork`, as the original's session.ts opens one: asked only of an
// agent that offers it, a refusal failing the start at that step.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/session.dart';
import 'package:chord/session/start_failure.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'session_fake.dart';

void main() {
  final skip = fakeAgentSkip;

  Future<Session> open({
    List<String> flags = const ['--fork'],
    String? fork,
    Map<String, String>? env,
  }) {
    final dir = Directory.systemTemp.createTempSync('chord-fork-');
    addTearDown(() => dir.delete(recursive: true));
    return openSession(
      agent: 'fake',
      command: fakeAgentCommand(null, flags),
      env: env,
      cwd: dir.path,
      open: fakeSessionOpener(),
      fork: fork,
    );
  }

  test('an agent that offers it forks a session into one of its own, which '
      'says it forks', () async {
    final source = await open();
    addTearDown(source.close);
    expect(source.forks(), isTrue);
    final fork = await open(fork: source.id);
    addTearDown(fork.close);
    expect(fork.id, isNot(source.id));
    expect(fork.forks(), isTrue);
  }, skip: skip);

  test('one that does not offer it is never asked, its start failing at '
      'session/fork; a refusal fails it there too', () async {
    final plain = await open(flags: const []);
    addTearDown(plain.close);
    expect(plain.forks(), isFalse);
    await expectLater(
      open(flags: const [], fork: plain.id),
      throwsA(
        isA<StartFailed>().having(
          (e) => e.failure.step,
          'step',
          StartStep.forkSession,
        ),
      ),
    );
    await expectLater(
      open(fork: plain.id, env: {'CHORD_FAKE_REFUSE_FORK': '1'}),
      throwsA(
        isA<StartFailed>()
            .having((e) => e.failure.step, 'step', StartStep.forkSession)
            .having((e) => e.failure.code, 'code', -32002),
      ),
    );
  }, skip: skip);
}
