@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/oneshot.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

Future<OneshotOutcome> _played(String prompt, {bool tokensOnly = false}) async {
  final root = Directory.systemTemp.createTempSync('oneshot-tester-');
  final pids = <int>[];
  final pending = runOneshot(
    agent: 'fake',
    command: fakeAgentCommand(null, [
      '--step-ms',
      '0',
      if (tokensOnly) '--tokens-only',
    ]),
    cwd: root.path,
    prompt: prompt,
    open: fakeSessionOpener(pids.add),
    onUpdate: (_) {},
    onRefused: (_) {},
  );
  try {
    return await pending.timeout(const Duration(seconds: 20));
  } finally {
    final alive = pids
        .where((pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0)
        .toList();
    for (final pid in alive) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    if (alive.isNotEmpty) {
      try {
        await pending.timeout(const Duration(seconds: 3));
      } on Object {
        /* The failing run still owns its cleanup. */
      }
    }
    expect(pids, hasLength(1));
    expect(
      alive,
      isEmpty,
      reason: 'oneshot returned before stopping its owned fake',
    );
    expect(
      pids.where(
        (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
      ),
      isEmpty,
      reason: 'oneshot must exit its owned fake before completing',
    );
    root.deleteSync(recursive: true);
  }
}

void main() {
  group('tester: CTUI-28 oneshot fake process ownership', () {
    test(
      'two simultaneous calls keep their own authoritative and estimated costs',
      () async {
        final outcomes = await Future.wait([
          _played('text'),
          _played('text', tokensOnly: true),
        ]);
        expect(
          outcomes.map((outcome) => outcome.result),
          everyElement(isA<TurnAnswered>()),
        );
        expect(outcomes.first.costEstimated, isFalse);
        expect(outcomes.last.costEstimated, isTrue);
        expect(outcomes.first.usage!['totalTokens'], greaterThan(0));
        expect(outcomes.last.usage!['totalTokens'], greaterThan(0));
      },
      skip: fakeAgentSkip,
    );

    test(
      'an agent exit during the prompt yields failure after process cleanup',
      () async {
        final outcome = await _played('crash');
        expect(outcome.result, isA<TurnFailed>());
        expect(outcome.usage, isNull);
      },
      skip: fakeAgentSkip,
    );
  });
}
