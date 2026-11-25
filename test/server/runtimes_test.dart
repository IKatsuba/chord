// The original's tests/server/runtimes_test.ts: a stub probe for the
// reads, fake_async for the bound, and the fake agent for the probe.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/rpc.dart' show OnCancel;
import 'package:chord/server/runtimes.dart';
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';

const Offered offered = (
  models: (available: [(id: 'm', name: 'M')], current: 'm'),
  modes: (available: [(id: 'plan', name: 'Plan')], current: 'plan'),
  efforts: (
    option: 'effort',
    available: [(id: 'low', name: 'Low'), (id: 'high', name: 'High')],
    current: 'low',
  ),
);

/// An offer as plain values, for comparing.
Object? plain(RuntimeOffer? offer) => switch (offer) {
  null => null,
  OfferError(:final error) => {'error': error},
  Offer() => {
    'models': [
      for (final m in offer.models)
        {
          'id': m.id,
          'name': m.name,
          if (m.efforts != null) 'efforts': [for (final e in m.efforts!) e.id],
          if (m.effort != null) 'effort': m.effort,
        },
    ],
    'current': offer.current,
    if (offer.modes != null) 'modes': [for (final m in offer.modes!) m.id],
    if (offer.currentMode != null) 'currentMode': offer.currentMode,
    if (offer.efforts != null)
      'efforts': [for (final e in offer.efforts!) e.id],
    if (offer.currentEffort != null) 'currentEffort': offer.currentEffort,
  },
};

const offer = {
  'models': [
    {
      'id': 'm',
      'name': 'M',
      'efforts': ['low', 'high'],
      'effort': 'low',
    },
  ],
  'current': 'm',
  'modes': ['plan'],
  'currentMode': 'plan',
};

/// A probe that never answers until its token is cancelled.
Future<Offered> hanging(String runtime, CancellationToken token) {
  final gaveUp = Completer<Offered>();
  OnCancel(gaveUp.completeError).listen(token);
  return gaveUp.future;
}

void main() {
  testerRuntimeTests();
  test('a runtime is read once for the window, and never unasked', () async {
    final probed = <String>[];
    final runtimes = Runtimes(
      probe: (runtime, _) async {
        probed.add(runtime);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return offered;
      },
    );
    expect(await runtimes.read('claude', probe: false), isNull);
    final [one, two] = await Future.wait([
      runtimes.read('claude', probe: true),
      runtimes.read('claude', probe: true),
    ]);
    expect(plain(one), offer);
    expect(identical(one, two), isTrue);
    expect(identical(await runtimes.read('claude', probe: false), one), isTrue);
    expect(probed, ['claude']);
  });

  test(
    "an open session's offer is the runtime's, with no session started",
    () async {
      final runtimes = Runtimes(
        probe: (_, _) => Future.error(StateError('not to be started')),
      );
      runtimes.heard('fake', offered);
      expect(plain(await runtimes.read('fake', probe: true)), offer);
    },
  );

  test(
    'a session that has said nothing yet leaves its runtime unread',
    () async {
      final runtimes = Runtimes(probe: (_, _) async => offered);
      runtimes.heard('fake', (models: null, modes: null, efforts: null));
      expect(await runtimes.read('fake', probe: false), isNull);
    },
  );

  test('a runtime that offers modes and no models gives its modes', () async {
    final runtimes = Runtimes(
      probe: (_, _) async =>
          (models: null, modes: offered.modes, efforts: null),
    );
    expect(plain(await runtimes.read('modal', probe: true)), {
      'models': <Object>[],
      'current': null,
      'modes': ['plan'],
      'currentMode': 'plan',
    });
  });

  test('a runtime that names no model it is on gives its efforts beside its '
      'models', () async {
    final runtimes = Runtimes(
      probe: (_, _) async => (
        models: (available: [(id: 'm', name: 'M')], current: null),
        modes: null,
        efforts: offered.efforts,
      ),
    );
    expect(plain(await runtimes.read('vague', probe: true)), {
      'models': [
        {'id': 'm', 'name': 'M'},
      ],
      'current': null,
      'efforts': ['low', 'high'],
      'currentEffort': 'low',
    });
  });

  test(
    'a runtime that fails says why, and is tried again when asked again',
    () async {
      var tries = 0;
      final runtimes = Runtimes(
        probe: (_, _) {
          tries++;
          return Future.error(StateError('npx: not found'));
        },
      );
      expect(plain(await runtimes.read('codex', probe: true)), {
        'error': 'npx: not found',
      });
      expect(plain(await runtimes.read('codex', probe: true)), {
        'error': 'npx: not found',
      });
      expect(tries, 2);
    },
  );

  test('a probe that throws at once is tried again when asked again', () async {
    var tries = 0;
    final runtimes = Runtimes(
      probe: (_, _) {
        tries++;
        throw StateError('npx: not found');
      },
    );
    for (var n = 0; n < 2; n++) {
      expect(plain(await runtimes.read('codex', probe: true)), {
        'error': 'npx: not found',
      });
    }
    expect(tries, 2);
  });

  test('a runtime that does not answer in 60 s is given up on', () {
    fakeAsync((async) {
      final runtimes = Runtimes(probe: hanging);
      RuntimeOffer? read;
      runtimes.read('slow', probe: true).then((offer) => read = offer);
      async.elapse(const Duration(seconds: 59));
      expect(read, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(plain(read), {'error': 'it did not open a session within 60 s'});
    });
  });

  test('a short bound is said in seconds as the original says it', () async {
    final runtimes = Runtimes(
      probe: hanging,
      bound: const Duration(milliseconds: 20),
    );
    expect(plain(await runtimes.read('slow', probe: true)), {
      'error': 'it did not open a session within 0.02 s',
    });
  });

  test('closing the window gives up on a read under way', () async {
    final runtimes = Runtimes(probe: hanging);
    final reading = runtimes.read('slow', probe: true);
    runtimes.close();
    expect(plain(await reading), {'error': 'chord is closing'});
  });

  test('the probe starts nothing for a runtime whose command was refused, '
      'and says why (CHD-466)', () async {
    var opened = false;
    final probe = sessionProbe(
      refusedOf: (_) =>
          'codex not started: agents.codex.command in '
          '.chord/settings.json: expected a string, got a number',
      open: (_, _) {
        opened = true;
        return Future.error(StateError('started'));
      },
    );
    final runtimes = Runtimes(probe: probe);
    expect(plain(await runtimes.read('codex', probe: true)), {
      'error':
          'codex not started: agents.codex.command in '
          '.chord/settings.json: expected a string, got a number',
    });
    expect(opened, isFalse);
  });

  test("the probe reads the fake agent's two models, three modes and its "
      "model's efforts from a session it closes", () async {
    final dir = Directory.systemTemp.createTempSync('chord-probe-');
    final pids = <int>[];
    try {
      final probe = sessionProbe(
        refusedOf: (_) => null,
        open: (runtime, token) => openSession(
          agent: runtime,
          command: fakeAgentCommand(),
          cwd: dir.path,
          open: fakeOpenerWith(onPid: pids.add),
          noMcpServers: true,
          cancellationToken: token,
        ),
      );
      final read = await probe('fake', CancellationToken());
      // Records holding lists compare by the lists' identity: by text.
      expect(
        '${read.models}',
        '${(available: [(id: 'fake-large', name: 'Fake Large with a 1M context window'), (id: 'fake-small', name: 'Fake Small')], current: 'fake-large')}',
      );
      expect(
        '${read.modes}',
        '${(available: [(id: 'default', name: 'Default'), (id: 'acceptEdits', name: 'Accept edits'), (id: 'plan', name: 'Plan')], current: 'default')}',
      );
      expect(
        '${read.efforts}',
        '${(option: 'effort', available: [(id: 'low', name: 'Low'), (id: 'medium', name: 'Medium'), (id: 'high', name: 'High')], current: 'medium')}',
      );
      expect(pids, hasLength(1));
      expect(
        Process.runSync('kill', ['-0', '${pids.single}']).exitCode,
        isNot(0),
        reason: 'the probe closed its session',
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, skip: fakeAgentSkip);
}

void testerRuntimeTests() {
  group('tester: runtime read recovery and isolation', () {
    test(
      'synchronous failure recovers to one shared and cached success',
      () async {
        var attempts = 0;
        final success = Completer<Offered>();
        final runtimes = Runtimes(
          probe: (_, _) {
            attempts++;
            if (attempts == 1) throw StateError('first failed');
            return success.future;
          },
        );
        addTearDown(runtimes.close);
        expect(plain(await runtimes.read('fake', probe: true)), {
          'error': 'first failed',
        });
        final reads = [
          for (var i = 0; i < 1000; i++) runtimes.read('fake', probe: true),
        ];
        expect(attempts, 2);
        success.complete(offered);
        final results = await Future.wait(reads);
        expect(results, everyElement(same(results.first)));
        expect(plain(results.first), offer);
        expect(await runtimes.read('fake', probe: true), same(results.first));
        expect(attempts, 2);
      },
    );

    test('timeout leaves the runtime retryable and cancels its timer', () {
      fakeAsync((async) {
        var attempts = 0;
        final runtimes = Runtimes(
          probe: (runtime, token) {
            attempts++;
            return attempts == 1
                ? hanging(runtime, token)
                : Future.value(offered);
          },
        );
        RuntimeOffer? first, next;
        runtimes.read('fake', probe: true).then((value) => first = value);
        async.elapse(const Duration(seconds: 60));
        expect(plain(first), {
          'error': 'it did not open a session within 60 s',
        });
        runtimes.read('fake', probe: true).then((value) => next = value);
        async.flushMicrotasks();
        expect(plain(next), offer);
        expect(attempts, 2);
        expect(async.pendingTimers, isEmpty);
        runtimes.close();
      });
    });

    test(
      'different runtimes read separately and close cancels every outstanding read',
      () {
        fakeAsync((async) {
          final probed = <String>[];
          final runtimes = Runtimes(
            probe: (runtime, token) {
              probed.add(runtime);
              return hanging(runtime, token);
            },
          );
          final results = <RuntimeOffer?>[];
          for (final runtime in ['first', 'second', 'first']) {
            runtimes.read(runtime, probe: true).then(results.add);
          }
          expect(probed, ['first', 'second']);
          async.elapse(const Duration(seconds: 59));
          expect(results, isEmpty);
          runtimes.close();
          runtimes.close();
          async.flushMicrotasks();
          expect(results, hasLength(3));
          expect(
            results.map(plain),
            everyElement({'error': 'chord is closing'}),
          );
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  });
}
