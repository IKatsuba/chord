import 'dart:async';

import 'package:chord/kept.dart';
import 'package:test/test.dart';

// Awaited, as the way out awaits it: a timeout on the future itself hears
// an error another zone's await would not.
Future<T> awaited<T>(Future<T> future) async => await future;

void main() {
  group('tester: kept leave outcomes across error zones', () {
    test(
      'a late failure reaches concurrent and repeated foreign waiters',
      () async {
        late Kept<void> kept;
        late Completer<void> close;
        late void Function() reject;
        final error = StateError('late close failure');
        final stack = StackTrace.fromString('tester close origin');
        runZonedGuarded(() {
          close = Completer<void>();
          kept = Kept(close.future);
          reject = () => close.completeError(error, stack);
        }, (_, _) => fail('the source zone must consume the failure'));

        Future<void> observe() async {
          try {
            await awaited(kept.future).timeout(const Duration(seconds: 2));
            fail('the failed close must reject');
          } catch (caught, trace) {
            expect(caught, same(error));
            expect(trace.toString(), stack.toString());
          }
        }

        final first = observe();
        final secondDone = Completer<void>();
        runZonedGuarded(() async {
          await observe();
          secondDone.complete();
        }, (error, stack) => secondDone.completeError(error, stack));
        reject();
        await Future.wait([first, secondDone.future]);
        await observe();
      },
    );

    test(
      'an already completed nullable value survives multiple zones',
      () async {
        late Kept<int?> kept;
        final captured = Completer<void>();
        runZonedGuarded(() async {
          final value = Future<int?>.value(null);
          kept = Kept(value);
          await value;
          captured.complete();
        }, (error, stack) => captured.completeError(error, stack));
        await captured.future;
        expect(await awaited(kept.future), isNull);
        final other = Completer<int?>();
        runZonedGuarded(() async {
          other.complete(await kept.future);
        }, (error, stack) => other.completeError(error, stack));
        expect(await other.future.timeout(const Duration(seconds: 2)), isNull);
      },
    );
  });

  // CTUI-114: a failed future made in one error zone never resumes a waiter
  // in another; Kept gives that waiter a future of its own zone.
  test('a failure kept in another error zone reaches a waiter here', () async {
    late Kept<void> kept;
    runZonedGuarded(() {
      kept = Kept(Future<void>.error(StateError('close failed')));
    }, (_, _) => fail('the kept failure is handled where it was made'));
    await expectLater(
      awaited(kept.future).timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>()),
    );
  });

  test('a value kept in another error zone reaches a waiter here', () async {
    late Kept<int> kept;
    runZonedGuarded(() {
      kept = Kept(Future.value(7));
    }, (_, _) {});
    expect(await awaited(kept.future), 7);
  });

  test('a waiter in the zone that made it gets the future itself', () {
    final future = Future<void>.value();
    final kept = Kept(future);
    expect(identical(kept.future, future), isTrue);
    expect(identical(kept.future, kept.future), isTrue);
  });
}
