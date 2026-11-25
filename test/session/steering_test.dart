import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../acp/connection_test.dart' show Harness;

const _adapter = '@agentclientprotocol/claude-agent-acp';

Session _open(
  FakeAsync async,
  Harness h, {
  bool advertised = true,
  String adapter = _adapter,
  ResolveMentionLinks? resolve,
}) {
  Session? session;
  openSession(
    agent: 'scripted',
    command: const ['scripted'],
    cwd: '/project',
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => connectAgent(
          h.process,
          onTraffic: onTraffic,
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
    resolveMentions: resolve ?? (paths, cwd, {cancellationToken}) async => [],
  ).then<void>((value) => session = value);
  async.flushMicrotasks();
  h.answer(h.lastRequest('initialize')['id'], {
    'protocolVersion': 1,
    'agentInfo': {'name': adapter, 'version': '1'},
    '_meta': {
      'steering': {'supported': advertised},
    },
  });
  async.flushMicrotasks();
  h.answer(h.lastRequest('session/new')['id'], {'sessionId': 'running'});
  async.flushMicrotasks();
  return session!;
}

List<Map<String, Object?>> _requests(Harness h, String method) =>
    h.written.where((m) => m['method'] == method).toList();

void main() {
  _testerSteeringLifetimes();
  group('session personal steering', () {
    for (final (wire, expected) in [
      ('injected', SteerOutcome.injected),
      ('startedNewTurn', SteerOutcome.startedNewTurn),
      ('promptRequired', SteerOutcome.refused),
      ('future-outcome', SteerOutcome.refused),
      (null, SteerOutcome.refused),
    ]) {
      test('maps $wire without manufacturing a prompt turn', () {
        fakeAsync((async) {
          final h = Harness();
          final active = _open(async, h);
          SteerOutcome? outcome;
          active
              .steer('held shell context\n@a.dart')
              .then<void>((value) => outcome = value);
          async.flushMicrotasks();
          final request = h.lastRequest('_session/steering');
          expect(request['params'], {
            'sessionId': 'running',
            'prompt': [
              {'type': 'text', 'text': 'held shell context\n@a.dart'},
            ],
            '_meta': {
              'steering': {'idleBehavior': 'promptRequired'},
            },
          });
          h.answer(request['id'], {'outcome': wire});
          async.flushMicrotasks();
          expect(outcome, expected);
          expect(_requests(h, 'session/prompt'), isEmpty);
          active.close();
          async.flushMicrotasks();
        });
      });
    }
    test('advertisement and exact adapter identity stay separate', () {
      fakeAsync((async) {
        for (final (advertised, name) in [(false, _adapter), (true, 'other')]) {
          final h = Harness();
          final active = _open(async, h, advertised: advertised, adapter: name);
          expect(active.steers(), advertised);
          expect(active.cutsCallsOnSteer(), name == _adapter);
          if (!advertised) {
            Object? error;
            active
                .steer('unsent')
                .then<void>((_) {}, onError: (Object e) => error = e);
            async.flushMicrotasks();
            expect(error, isA<AgentCapabilityError>());
            expect(_requests(h, '_session/steering'), isEmpty);
          }
          active.close();
          async.flushMicrotasks();
        }
      });
    });
    test(
      'resolves frozen mention paths then captures exact actual wire content once',
      () {
        fakeAsync((async) {
          final h = Harness(), pending = Completer<List<acp.ContentBlock>>();
          final submitted = <SubmittedContent>[];
          final session = _open(
            async,
            h,
            resolve: (paths, cwd, {cancellationToken}) {
              expect(paths, ['a.dart']);
              expect(() => paths.add('bad'), throwsUnsupportedError);
              expect(cwd, '/project');
              return pending.future;
            },
          );
          final paths = ['a.dart'];
          session.steer(
            'literal @a.dart',
            mentions: paths,
            turnId: 'queued-7',
            onSubmitted: submitted.add,
          );
          paths.add('late.dart');
          async.flushMicrotasks();
          expect(submitted, isEmpty);
          expect(_requests(h, '_session/steering'), isEmpty);
          final link = <String, Object?>{
            'type': 'resource_link',
            'name': 'a.dart',
            'uri': 'file:///project/a.dart',
            'futureFact': 1.5,
          };
          pending.complete([acp.ContentBlock.fromJson(link)]);
          async.flushMicrotasks();
          expect(submitted, hasLength(1));
          expect(submitted.single.turnId, 'queued-7');
          expect(submitted.single.prompt, 'literal @a.dart');
          expect(submitted.single.links.single, link);
          h.answer(h.lastRequest('_session/steering')['id'], {
            'outcome': 'injected',
          });
          async.flushMicrotasks();
          link['futureFact'] = 9;
          expect(submitted.single.links.single['futureFact'], 1.5);
          expect(() => submitted.single.links.clear(), throwsUnsupportedError);
          session.close();
          async.flushMicrotasks();
        });
      },
    );
    test('failed mention resolution retains literal text', () {
      fakeAsync((async) {
        final h = Harness();
        final session = _open(
          async,
          h,
          resolve: (paths, cwd, {cancellationToken}) async =>
              throw StateError('walk failed'),
        );
        session.steer('@missing');
        // With no paths the resolver is not invoked.
        async.flushMicrotasks();
        h.answer(h.lastRequest('_session/steering')['id'], {
          'outcome': 'injected',
        });
        session.steer('@missing', mentions: ['missing']);
        async.flushMicrotasks();
        expect(
          (h.lastRequest('_session/steering')['params'] as Map)['prompt'],
          [
            {'type': 'text', 'text': '@missing'},
          ],
        );
        h.answer(h.lastRequest('_session/steering')['id'], {
          'outcome': 'promptRequired',
        });
        async.flushMicrotasks();
        session.close();
        async.flushMicrotasks();
      });
    });
    test('turn cancellation keeps an on-wire steering response observable', () {
      fakeAsync((async) {
        final h = Harness();
        final session = _open(async, h);
        final turn = session.prompt('still running');
        turn.result.ignore();
        async.flushMicrotasks();
        SteerOutcome? outcome;
        session.steer('late accepted').then<void>((value) => outcome = value);
        async.flushMicrotasks();
        final steer = h.lastRequest('_session/steering');
        session.cancel();
        async.flushMicrotasks();
        expect(_requests(h, 'session/cancel'), hasLength(1));
        h.answer(steer['id'], {'outcome': 'injected'});
        async.flushMicrotasks();
        expect(outcome, SteerOutcome.injected);
        session.close();
        async.flushMicrotasks();
      });
    });
    test(
      'ordinary cancel keeps dispatched mention resolution and late outcome',
      () {
        fakeAsync((async) {
          final h = Harness(), pending = Completer<List<acp.ContentBlock>>();
          CancellationToken? token;
          final session = _open(
            async,
            h,
            resolve: (paths, cwd, {cancellationToken}) {
              token = cancellationToken;
              return pending.future;
            },
          );
          final turn = session.prompt('running');
          turn.result.ignore();
          SteerOutcome? outcome;
          final submitted = <SubmittedContent>[];
          session
              .steer(
                'dispatched @a.dart',
                mentions: ['a.dart'],
                onSubmitted: submitted.add,
              )
              .then<void>((value) => outcome = value);
          async.flushMicrotasks();
          expect(_requests(h, '_session/steering'), isEmpty);
          expect(submitted, isEmpty);
          session.cancel();
          async.flushMicrotasks();
          expect(token!.isCancelled, isFalse);
          expect(_requests(h, 'session/cancel'), hasLength(1));
          h.answer(h.lastRequest('session/prompt')['id'], {
            'stopReason': 'cancelled',
          });
          async.flushMicrotasks();
          pending.complete([
            acp.ContentBlock.fromJson({
              'type': 'resource_link',
              'name': 'a.dart',
              'uri': 'file:///project/a.dart',
            }),
          ]);
          async.flushMicrotasks();
          expect(_requests(h, '_session/steering'), hasLength(1));
          expect(submitted.single.prompt, 'dispatched @a.dart');
          expect(submitted.single.links.single['name'], 'a.dart');
          expect(outcome, isNull);
          h.answer(h.lastRequest('_session/steering')['id'], {
            'outcome': 'injected',
          });
          async.flushMicrotasks();
          expect(outcome, SteerOutcome.injected);
          expect(_requests(h, 'session/prompt'), hasLength(1));
          session.close();
          async.flushMicrotasks();
        });
      },
    );
    for (final preWire in [true, false]) {
      test(
        'close cancels ${preWire ? 'resolving' : 'on-wire'} steering without late admission',
        () {
          fakeAsync((async) {
            final h = Harness(), pending = Completer<List<acp.ContentBlock>>();
            CancellationToken? token;
            final session = _open(
              async,
              h,
              resolve: (paths, cwd, {cancellationToken}) {
                token = cancellationToken;
                return pending.future;
              },
            );
            Object? error;
            var submissions = 0;
            session
                .steer(
                  'closing',
                  mentions: preWire ? ['a'] : [],
                  onSubmitted: (_) => submissions++,
                )
                .then<void>((_) {}, onError: (Object e) => error = e);
            async.flushMicrotasks();
            final beforeClose = submissions;
            session.close();
            async.flushMicrotasks();
            expect(error, isA<CancelledException>());
            if (preWire) {
              expect(token!.isCancelled, isTrue);
              pending.complete([acp.ContentBlock.text('late')]);
            }
            async.flushMicrotasks();
            expect(submissions, beforeClose);
            expect(
              _requests(h, '_session/steering'),
              hasLength(preWire ? 0 : 1),
            );
            expect(h.process.stdin.ended, isTrue);
          });
        },
      );
    }
  });
}

void _testerSteeringLifetimes() {
  group('tester: independent steering request lifetimes', () {
    test(
      'silent steering stays pending after cancellation until its late answer',
      () {
        fakeAsync((async) {
          final h = Harness();
          final session = _open(async, h);
          final turn = session.prompt('running');
          turn.result.ignore();
          final submitted = <SubmittedContent>[];
          SteerOutcome? outcome;
          session
              .steer(
                '界 😀 é\n\u001b[31m literal',
                turnId: 'held',
                onSubmitted: submitted.add,
              )
              .then<void>((value) => outcome = value);
          async.flushMicrotasks();
          final request = h.lastRequest('_session/steering');
          session.cancel();
          async.flushMicrotasks();
          h.answer(h.lastRequest('session/prompt')['id'], {
            'stopReason': 'cancelled',
          });
          async.flushMicrotasks();
          async.elapse(const Duration(hours: 1));
          expect(outcome, isNull);
          expect(submitted.single.prompt, '界 😀 é\n\u001b[31m literal');
          expect(submitted.single.turnId, 'held');
          expect(_requests(h, '_session/steering'), hasLength(1));
          expect(_requests(h, 'session/prompt'), hasLength(1));
          h.answer(request['id'], {'outcome': 'startedNewTurn'});
          async.flushMicrotasks();
          expect(outcome, SteerOutcome.startedNewTurn);
          expect(submitted, hasLength(1));
          session.close();
          async.flushMicrotasks();
          expect(h.process.stdin.ended, isTrue);
        });
      },
    );

    test(
      'matching request and turn ids in simultaneous sessions never cross',
      () {
        fakeAsync((async) {
          final first = Harness(), second = Harness();
          final a = _open(async, first), b = _open(async, second);
          final sentA = <SubmittedContent>[], sentB = <SubmittedContent>[];
          SteerOutcome? resultA, resultB;
          Object? errorA;
          a
              .steer('first only', turnId: 'same', onSubmitted: sentA.add)
              .then<void>(
                (value) => resultA = value,
                onError: (Object e) => errorA = e,
              );
          b
              .steer('second only', turnId: 'same', onSubmitted: sentB.add)
              .then<void>((value) => resultB = value);
          async.flushMicrotasks();
          expect(
            first.lastRequest('_session/steering')['id'],
            second.lastRequest('_session/steering')['id'],
          );
          a.close();
          async.flushMicrotasks();
          expect(errorA, isA<CancelledException>());
          second.answer(second.lastRequest('_session/steering')['id'], {
            'outcome': 'injected',
          });
          async.flushMicrotasks();
          expect(resultA, isNull);
          expect(resultB, SteerOutcome.injected);
          expect(sentA.single.prompt, 'first only');
          expect(sentB.single.prompt, 'second only');
          expect(_requests(first, 'session/prompt'), isEmpty);
          expect(_requests(second, 'session/prompt'), isEmpty);
          b.close();
          async.flushMicrotasks();
          expect(first.process.stdin.ended, isTrue);
          expect(second.process.stdin.ended, isTrue);
        });
      },
    );

    test('out-of-order steering answers retain their own admission facts', () {
      fakeAsync((async) {
        final h = Harness();
        final session = _open(async, h);
        final submitted = <SubmittedContent>[];
        final outcomes = <String, SteerOutcome>{};
        for (final id in ['one', 'two']) {
          session
              .steer('literal $id', turnId: id, onSubmitted: submitted.add)
              .then<void>((value) => outcomes[id] = value);
        }
        async.flushMicrotasks();
        final requests = _requests(h, '_session/steering');
        h.answer(requests.last['id'], {'outcome': 'promptRequired'});
        async.flushMicrotasks();
        expect(outcomes, {'two': SteerOutcome.refused});
        h.answer(requests.first['id'], {'outcome': 'injected'});
        async.flushMicrotasks();
        expect(outcomes, {
          'two': SteerOutcome.refused,
          'one': SteerOutcome.injected,
        });
        expect(submitted.map((s) => (s.turnId, s.prompt)), [
          ('one', 'literal one'),
          ('two', 'literal two'),
        ]);
        expect(_requests(h, 'session/prompt'), isEmpty);
        session.close();
        async.flushMicrotasks();
      });
    });

    test(
      'a throwing submission observer cannot suppress the admitted answer',
      () {
        fakeAsync((async) {
          final h = Harness();
          final session = _open(async, h);
          var calls = 0;
          SteerOutcome? outcome;
          session
              .steer(
                'already admitted',
                onSubmitted: (_) {
                  calls++;
                  throw StateError('observer failed');
                },
              )
              .then<void>((value) => outcome = value);
          async.flushMicrotasks();
          expect(calls, 1);
          h.answer(h.lastRequest('_session/steering')['id'], {
            'outcome': 'injected',
          });
          async.flushMicrotasks();
          expect(outcome, SteerOutcome.injected);
          expect(calls, 1);
          expect(_requests(h, 'session/prompt'), isEmpty);
          session.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}
