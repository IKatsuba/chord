import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../turn.dart';
import 'misbehaving.dart';

final class _Capture {
  _Capture([void Function(Map update)? onUpdate]) {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        final update = (message['params'] as Map)['update'] as Map;
        updates.add(update);
        onUpdate?.call(update);
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }
  final input = StreamController<List<int>>();
  final updates = <Map>[];
  late final Connection connection;
  void close() {
    connection.close();
    unawaited(input.close());
  }
}

void main() {
  group('tester: CTUI-147 misbehaving cancellation and late output', () {
    setUp(() => options.args = ['--step-ms', '1']);

    test(
      'flood cancellation counts actual 64 KiB chunks and stops after twenty',
      () {
        fakeAsync((clock) {
          final abort = Aborter();
          var chunks = 0;
          final capture = _Capture((update) {
            final text = (update['content'] as Map)['text'] as String;
            expect(text, 'x' * (64 * 1024));
            if (++chunks == 20) abort.abort();
          });
          String? result;
          misbehaving['flood']!(
            Turn(capture.connection.client, 'tester-flood', abort.signal),
          ).then((value) => result = value);
          clock.elapse(const Duration(milliseconds: 100));
          expect(result, 'cancelled');
          expect(chunks, 20);
          expect(capture.updates, hasLength(20));
          capture.close();
          clock.flushMicrotasks();
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'ignorescancel stays open through turn cancellation until its bound',
      () {
        fakeAsync((clock) {
          final capture = _Capture();
          final abort = Aborter();
          String? result;
          misbehaving['ignorescancel']!(
            Turn(capture.connection.client, 'tester-held', abort.signal),
          ).then((value) => result = value);
          clock.elapse(const Duration(milliseconds: 1));
          expect(capture.updates, hasLength(1));
          abort.abort();
          clock.elapse(const Duration(milliseconds: 29999));
          expect(result, isNull);
          clock.elapse(const Duration(milliseconds: 1));
          expect(result, 'end_turn');
          capture.close();
          clock.flushMicrotasks();
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'late output follows the returned answer and is ignored after close',
      () {
        fakeAsync((clock) {
          final capture = _Capture();
          var returned = false;
          misbehaving['late']!(
            Turn(capture.connection.client, 'tester-late', Aborter().signal),
          ).then((_) => returned = true);
          clock.elapse(const Duration(milliseconds: 1));
          expect(returned, isTrue);
          expect(capture.updates, hasLength(1));
          capture.close();
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 4));
          expect(capture.updates, hasLength(1));
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}
