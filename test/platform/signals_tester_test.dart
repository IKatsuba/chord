import 'dart:async';
import 'dart:io';

import 'package:chord/platform/signals.dart';
import 'package:test/test.dart';

void main() {
  group('tester: signal identity through failed cleanup', () {
    for (final first in leaveSignals) {
      for (final synchronous in [true, false]) {
        test(
          '$first survives ${synchronous ? 'synchronous' : 'delayed'} failure',
          () async {
            final cancelled = <ProcessSignal>[];
            final raised = <ProcessSignal>[];
            final sources = {
              for (final signal in leaveSignals)
                signal: StreamController<ProcessSignal>.broadcast(
                  sync: true,
                  onCancel: () => cancelled.add(signal),
                ),
            };
            final pending = Completer<void>();
            var calls = 0;
            final off = dieBySignal(
              () {
                calls++;
                if (synchronous) throw StateError('release failed immediately');
                return pending.future;
              },
              watch: (signal) => sources[signal]!.stream,
              raise: (signal) {
                raised.add(signal);
              },
            );
            addTearDown(() async {
              off();
              await Future.wait(sources.values.map((source) => source.close()));
            });
            sources[first]!.add(first);
            if (!synchronous) {
              for (var i = 0; i < 1000; i++) {
                final signal = leaveSignals[i % leaveSignals.length];
                sources[signal]!.add(signal);
              }
              expect(calls, 1);
              expect(cancelled, isEmpty);
              expect(raised, isEmpty);
              pending.completeError(StateError('release failed later'));
            }
            await Future<void>.delayed(Duration.zero);
            expect(calls, 1);
            expect(raised, [first]);
            for (final signal in leaveSignals) {
              sources[signal]!.add(signal);
            }
            await Future<void>.delayed(Duration.zero);
            expect(calls, 1);
            expect(raised, [first]);
          },
        );
      }
    }
  });
}
