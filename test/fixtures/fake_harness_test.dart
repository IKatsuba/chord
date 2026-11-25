@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:test/test.dart';

import 'fake_harness.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// What a run left, checked by a tearDown registered before the harness's,
/// so run after it.
final class _Left {
  int? pid;
  String? cwd;

  _Left() {
    addTearDown(() {
      expect(pid, isNotNull, reason: 'the process never started');
      expect(_alive(pid!), isFalse, reason: 'the agent is still running');
      expect(Directory(cwd!).existsSync(), isFalse);
    });
  }
}

void main() {
  group('startFake', skip: fakeAgentSkip, () {
    test(
      'records traffic from before the start and closes the agent',
      () async {
        final left = _Left();
        final run = startFake(scenario: 'text');
        left.cwd = run.cwd;
        left.pid = (await run.process).pid;
        final agent = await run.agent;
        final first = run.traffic.heard.first;
        expect(first, isA<ChordTraffic>());
        expect((first as ChordTraffic).message['method'], 'initialize');
        expect(agent.pid, left.pid);
        expect(Directory(run.cwd).existsSync(), isTrue);
      },
    );

    test('gives up a start still pending and stops its process', () async {
      final left = _Left();
      final run = startFake(flags: ['--hang', 'start']);
      left.cwd = run.cwd;
      left.pid = (await run.process).pid;
      final first = await run.traffic.next((t) => t is ChordTraffic);
      expect((first as ChordTraffic).message['method'], 'initialize');
      expect(_alive(left.pid!), isTrue);
    });
  });

  group('tester recorder isolation', () {
    test(
      'replays earlier traffic and wakes every matching waiter once',
      () async {
        final recorder = TrafficRecorder();
        final first = Traffic.stderr('first');
        final second = Traffic.stderr('second');
        final a = recorder.next((t) => identical(t, first));
        final b = recorder.next((t) => identical(t, first));
        final later = recorder.next((t) => identical(t, second));
        recorder.add(first);
        expect(await a, same(first));
        expect(await b, same(first));
        expect(await recorder.next((t) => identical(t, first)), same(first));
        recorder.add(second);
        expect(await later, same(second));
        expect(recorder.heard, [first, second]);
        expect(recorder.stderr, 'firstsecond');
      },
    );

    test('a burst preserves order independently for each recorder', () {
      final recorder = TrafficRecorder();
      final other = TrafficRecorder();
      final burst = List.generate(1000, (i) => Traffic.stderr('$i,'));
      for (final traffic in burst) {
        recorder.add(traffic);
      }
      expect(recorder.heard, orderedEquals(burst));
      expect(recorder.stderr, List.generate(1000, (i) => '$i,').join());
      expect(other.heard, isEmpty);
      expect(other.stderr, isEmpty);
    });
  });

  group('tester concurrent harness cleanup', skip: fakeAgentSkip, () {
    test(
      'separate starts have separate processes directories and traffic',
      () async {
        final firstLeft = _Left();
        final secondLeft = _Left();
        final first = startFake(scenario: 'text');
        final second = startFake(scenario: 'text');
        firstLeft.cwd = first.cwd;
        secondLeft.cwd = second.cwd;
        firstLeft.pid = (await first.process).pid;
        secondLeft.pid = (await second.process).pid;
        final agents = await Future.wait([first.agent, second.agent]);
        expect(agents[0].pid, isNot(agents[1].pid));
        expect(first.cwd, isNot(second.cwd));
        expect(first.traffic, isNot(same(second.traffic)));
        expect(first.traffic.heard.first, isA<ChordTraffic>());
        expect(second.traffic.heard.first, isA<ChordTraffic>());
      },
    );
  });
}
