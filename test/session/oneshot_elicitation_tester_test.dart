import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/oneshot.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../acp/connection_test.dart' show Harness;

class _Shot {
  _Shot(this.clock, this.gate) {
    runOneshot(
      agent: 'memory',
      command: 'memory',
      cwd: '.',
      prompt: 'ask',
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
            harness.process,
            onTraffic: onTraffic,
            onPermission: onPermission,
            relay: relay,
            cancellationToken: cancellationToken,
          ),
      onUpdate: (_) {},
      onRefused: (_) {},
      onDeclined: (form) {
        told.add(form.message);
        return gate.future;
      },
    ).then((value) => outcome = value);
    clock.flushMicrotasks();
    harness.answer(harness.lastRequest('initialize')['id'], {
      'protocolVersion': 1,
    });
    clock.flushMicrotasks();
    harness.answer(harness.lastRequest('session/new')['id'], {
      'sessionId': 's1',
    });
    clock.flushMicrotasks();
    promptId = harness.lastRequest('session/prompt')['id'];
  }
  final FakeAsync clock;
  final Completer<void> gate;
  final harness = Harness();
  final told = <String>[];
  Object? promptId;
  OneshotOutcome? outcome;

  void ask(String id, {bool link = false}) {
    harness.process.send({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'elicitation/create',
      'params': {
        'sessionId': 's1',
        'mode': link ? 'url' : 'form',
        'message': link ? 'Link' : 'Form',
        if (link) 'url': 'https://example.com',
        if (link) 'elicitationId': 'link',
        if (!link)
          'requestedSchema': {
            'type': 'object',
            'properties': <String, Object?>{},
          },
      },
    });
    clock.flushMicrotasks();
  }

  Map<String, Object?>? answer(String id) => harness.written
      .where((m) => m['id'] == id && !m.containsKey('method'))
      .firstOrNull;
  void finish() {
    harness.answer(promptId, {'stopReason': 'end_turn'});
    clock.elapse(const Duration(seconds: 2));
  }
}

void main() {
  group('tester oneshot async elicitation ordering', () {
    test(
      'form waits for callback while a simultaneous link cancels immediately',
      () {
        fakeAsync((clock) {
          final gate = Completer<void>();
          final shot = _Shot(clock, gate);
          shot.ask('form');
          expect(shot.told, ['Form']);
          expect(shot.answer('form'), isNull);
          shot.ask('link', link: true);
          expect(shot.answer('link')!['result'], {'action': 'cancel'});
          expect(shot.told, ['Form']);
          gate.complete();
          clock.flushMicrotasks();
          expect(shot.answer('form')!['result'], {'action': 'decline'});
          shot.finish();
          expect(shot.outcome!.result, isA<TurnAnswered>());
          expect(shot.harness.process.exited, isTrue);
        });
      },
    );

    test(
      'withdrawn request can finish before callback and ignores its late completion',
      () {
        fakeAsync((clock) {
          final gate = Completer<void>();
          final shot = _Shot(clock, gate);
          shot.ask('form');
          shot.harness.process.send({
            'jsonrpc': '2.0',
            'method': r'$/cancel_request',
            'params': {'requestId': 'form'},
          });
          clock.flushMicrotasks();
          expect(shot.answer('form')!['result'], {'action': 'cancel'});
          shot.finish();
          expect(shot.outcome, isNotNull);
          expect(gate.isCompleted, isFalse);
          expect(shot.harness.process.exited, isTrue);
          final count = shot.harness.written.length;
          gate.complete();
          clock.flushMicrotasks();
          expect(shot.harness.written, hasLength(count));
        });
      },
    );

    test('concurrent oneshots hold independent callback gates', () {
      fakeAsync((clock) {
        final firstGate = Completer<void>(), secondGate = Completer<void>();
        final first = _Shot(clock, firstGate),
            second = _Shot(clock, secondGate);
        first.ask('same');
        second.ask('same');
        firstGate.complete();
        clock.flushMicrotasks();
        expect(first.answer('same')!['result'], {'action': 'decline'});
        expect(second.answer('same'), isNull);
        first.finish();
        expect(first.outcome, isNotNull);
        expect(second.outcome, isNull);
        secondGate.complete();
        clock.flushMicrotasks();
        expect(second.answer('same')!['result'], {'action': 'decline'});
        second.finish();
        expect(second.outcome, isNotNull);
      });
    });
  });
}
