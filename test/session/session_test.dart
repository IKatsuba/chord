// A session's turns on the original's fake agent: the original's
// tests/session/session_test.ts, the cases M1 covers. Left for later:
// tokens and costs, modes, models and options set from chord, commands,
// mentions, MCP servers, initial options, forks, resume, steering and
// prompt suggestions.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

/// What `crash`'s agent leaves on stderr before it exits mid-turn.
const _crashWords =
    'fatal: out of memory reading tests/parse/fixtures/huge.json';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The pids of the processes whose command line holds [tag].
List<int> _tagged(String tag) {
  final found = Process.runSync('pgrep', ['-f', tag]);
  return [
    for (final line in '${found.stdout}'.split('\n'))
      ?int.tryParse(line.trim()),
  ];
}

Future<void> _cancelSlowTurn(
  Session session,
  Future<void> Function(Turn turn) cancel,
) async {
  final (turn: _, :updates, :result) = await run(
    session,
    'slow',
    onUpdate: (so, turn) {
      if (so.length == 3) cancel(turn).ignore();
    },
  );

  expect((result as TurnAnswered).cancelled, isTrue);
  // The fake turn is a thousand chunks long; stopping early is the agent
  // honouring cancel.
  expect(updates.length, lessThan(100));
}

void main() {
  final skip = fakeAgentSkip;

  test(
    'a failed turn says why, and the session takes the next prompt',
    () async {
      await withSession((session, _) async {
        final (turn: _, :updates, :result) = await run(session, 'error');

        expect(said(updates), ['About to fail.']);
        expect(
          (result as TurnFailed).message,
          'The fake agent failed on purpose.',
        );
        expect(result.code, -32603);
        expect((await run(session, 'text')).result, isA<TurnAnswered>());
        // The agent is still up: the failure is the turn's, not an exit.
        expect(session.gone(), isNull);
      });
    },
    skip: skip,
  );

  test('an agent that exits mid-turn fails the turn, and its last words are '
      'what it left on stderr', () async {
    await withSession((session, _) async {
      expect(session.gone(), isNull);

      final (turn: _, updates: _, :result) = await run(session, 'crash');

      expect((result as TurnFailed).message, 'The agent exited: $_crashWords');
      expect(result.code, isNull);
      expect(session.gone(), _crashWords);
      await session.exited;

      // A prompt after the exit is drawn and fails at once with the same
      // words, as the original's.
      expect(
        (await session.prompt('text').result as TurnFailed).message,
        'The agent exited: $_crashWords',
      );
    });
  }, skip: skip);

  test('a slow turn stops when the turn is cancelled', () async {
    await withSession(
      (session, _) => _cancelSlowTurn(session, (turn) => turn.cancel()),
    );
  }, skip: skip);

  test('a slow turn stops when the session cancels its active turn', () async {
    await withSession(
      (session, _) => _cancelSlowTurn(session, (_) => session.cancel()),
    );
  }, skip: skip);

  test('closing mid-turn ends the turn and the agent', () async {
    await withSession((session, _) async {
      final first = Completer<void>();
      final unsubscribe = session.subscribe((_) {
        if (!first.isCompleted) first.complete();
      });
      final turn = session.prompt('slow');

      await first.future;
      unsubscribe();
      await session.close();

      final result = await turn.result;

      expect(
        result is TurnAnswered && result.stopReason == 'end_turn',
        isFalse,
      );
    });
  }, skip: skip);

  test("the scenario can come from the agent's command line", () async {
    await withSession((session, _) async {
      expect(said(await collect(session, 'anything')), [
        'Here is',
        ' the answer.',
      ]);
    }, scenario: 'thought');
  }, skip: skip);

  test("the session's traffic reaches its own hook after the ingress, "
      "enriched", () async {
    await withSession((session, traffic) async {
      await collect(session, 'tools');

      final last = traffic.updates.lastWhere(
        (u) => u['sessionUpdate'] == 'tool_call_update',
      );

      expect(last['title'], 'Read README.md');
      expect(last['_meta'], containsPair('chord/filled', ['title', 'kind']));
    });
  }, skip: skip);

  test('an agent that cannot start fails the open and leaves nothing '
      'running', () async {
    final dir = Directory.systemTemp.createTempSync('chord-session-');
    addTearDown(() => dir.deleteSync(recursive: true));

    await expectLater(
      openSession(
        agent: 'missing',
        command: ['${dir.path}/no-such-agent'],
        cwd: dir.path,
        open: fakeSessionOpener(),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'closing comes back and kills an agent whose turn ignores its cancel',
    () async {
      await withSession((session, _) async {
        final turn = session.prompt('text');

        turn.result.ignore();
        session.cancel().ignore();
        // Long enough for the request to be out to the agent.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final watch = Stopwatch()..start();

        await session.close();
        expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
        expect(session.gone(), isNotNull);
      }, flags: ['--hang', 'turn']);
    },
    skip: skip,
  );

  test('an open given up while the agent never answers its start leaves '
      'nothing running', () async {
    final dir = Directory.systemTemp.createTempSync('chord-session-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tag = 'chord-wedged-${Random().nextInt(1 << 32)}';
    final stop = CancellationToken();
    final opening = openSession(
      agent: 'fake',
      command: fakeAgentCommand(null, ['--hang', 'start', tag]),
      cwd: dir.path,
      open: fakeSessionOpener(),
      cancellationToken: stop,
    );

    opening.ignore();
    while (_tagged(tag).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final watch = Stopwatch()..start();

    stop.cancel();
    await expectLater(opening, throwsA(isA<Exception>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(_tagged(tag).where(_alive), isEmpty);
  }, skip: skip);

  group('tester: concurrent fake sessions', () {
    test(
      'cancelling one agent leaves another session answering and reusable',
      () async {
        await withSession((first, _) async {
          await withSession((second, _) async {
            final a = run(
              first,
              'slow',
              onUpdate: (updates, turn) {
                if (updates.length == 3) turn.cancel().ignore();
              },
            );
            final b = run(second, 'text');
            final results = await Future.wait([a, b]);
            expect((results[0].result as TurnAnswered).cancelled, isTrue);
            expect((results[1].result as TurnAnswered).stopReason, 'end_turn');
            expect(
              said(results[1].updates).join(),
              'Hello, world. This reply came in chunks.',
            );
            expect(first.gone(), isNull);
            expect(second.gone(), isNull);
            expect((await run(first, 'text')).result, isA<TurnAnswered>());
            expect((await run(second, 'thought')).result, isA<TurnAnswered>());
          });
        });
      },
      skip: skip,
    );
  });

  tearDownAll(() {
    expect(
      [
        for (final pid in fakeAgentPids)
          if (_alive(pid)) pid,
      ],
      isEmpty,
      reason: 'fake agents left running',
    );
  });
}
