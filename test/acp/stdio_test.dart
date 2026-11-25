import 'dart:async';
import 'dart:convert';

import 'package:chord/acp/stdio.dart';
import 'package:test/test.dart';

/// A sink whose flushes the test holds, fails and counts.
class HeldSink implements OutputSink {
  final lines = <Map<String, Object?>>[];
  final _added = <int>[];
  final flushes = <Completer<void>>[];
  var adds = 0;
  var closed = false;
  Object? failAdd;

  /// Every flush settles as soon as it is asked for.
  var open = false;

  @override
  void add(List<int> bytes) {
    if (failAdd case final error?) throw error;
    adds++;
    _added.addAll(bytes);
  }

  @override
  Future<void> flush() {
    final text = utf8.decode(_added);
    _added.clear();
    for (final line in const LineSplitter().convert(text)) {
      lines.add(jsonDecode(line) as Map<String, Object?>);
    }
    if (open) return Future.value();
    final flush = Completer<void>();
    flushes.add(flush);
    return flush.future;
  }

  @override
  Future<void> close() async => closed = true;
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

Map<String, Object?> answer(Object? id) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': <String, Object?>{},
};

Map<String, Object?> update(String text) => {
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'text': text},
};

void main() {
  late HeldSink sink;
  late Output output;
  late List<Object> failures;

  setUp(() {
    sink = HeldSink();
    failures = [];
    output = Output(sink, onFailed: failures.add);
  });

  test('lines go in order, one flush at a time, those queued meanwhile in '
      'one batch', () async {
    output.send(update('a'));
    output.send(update('b'));
    output.send(update('c'));
    expect(sink.flushes, hasLength(1));
    expect(sink.lines.map((l) => (l['params'] as Map)['text']), ['a']);
    expect(sink.adds, 1);
    sink.flushes.single.complete();
    await pump();
    expect(sink.flushes, hasLength(2));
    expect(sink.adds, 2, reason: 'b and c go in one add');
    expect(sink.lines.map((l) => (l['params'] as Map)['text']), [
      'a',
      'b',
      'c',
    ]);
  });

  test('expect settles once the flush carrying that answer completes, '
      'by id value and type', () async {
    output.send(update('first'));
    final one = output.expect(1);
    final text = output.expect('1');
    var oneWritten = false;
    var textWritten = false;
    one.then((_) => oneWritten = true);
    text.then((_) => textWritten = true);
    output.send(answer(1));
    sink.flushes[0].complete();
    await pump();
    expect(oneWritten, isFalse, reason: 'its flush is still in flight');
    sink.flushes[1].complete();
    await pump();
    expect(oneWritten, isTrue);
    expect(textWritten, isFalse);
  });

  test('a request with the id is no answer to it', () async {
    sink.open = true;
    var written = false;
    output.expect(7).then((_) => written = true);
    output.send({
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'session/request_permission',
    });
    await pump();
    expect(written, isFalse);
    output.send(answer(7));
    await pump();
    expect(written, isTrue);
  });

  test('drained waits for every expected answer', () async {
    final drained = Completer<void>();
    output.expect(1);
    output.expect(2);
    output.drained().then((_) => drained.complete());
    output.send(answer(1));
    sink.flushes.single.complete();
    await pump();
    expect(drained.isCompleted, isFalse);
    output.send(answer(2));
    sink.flushes.last.complete();
    await pump();
    expect(drained.isCompleted, isTrue);
  });

  test('drained waits for an answer expected after it was asked for', () async {
    var drained = false;
    output.expect(1);
    output.drained().then((_) => drained = true);
    output.expect(2);
    output.send(answer(1));
    sink.flushes.single.complete();
    await pump();
    expect(drained, isFalse);
    output.send(answer(2));
    sink.flushes.last.complete();
    await pump();
    expect(drained, isTrue);
  });

  test('drained with nothing expected settles at once', () async {
    await output.drained().timeout(const Duration(seconds: 1));
  });

  test('a failing flush marks it failed, settles every expectation and '
      'drops what follows', () async {
    final expected = output.expect(1);
    output.send(update('a'));
    output.send(answer(1));
    sink.flushes.single.completeError(const SocketLikeError('EPIPE'));
    await pump();
    expect(output.failed, isTrue);
    expect(failures, [const SocketLikeError('EPIPE')]);
    await expected.timeout(const Duration(seconds: 1));
    await output.drained().timeout(const Duration(seconds: 1));
    output.send(update('after'));
    expect(sink.flushes, hasLength(1));
    await output.expect(9).timeout(const Duration(seconds: 1));
  });

  test('a sink that throws on add fails as a failing flush does', () async {
    sink.failAdd = StateError('closed');
    output.send(update('a'));
    expect(output.failed, isTrue);
    expect(failures, hasLength(1));
  });

  test('close gives up on what is expected and returns at once with a '
      'flush held; the sink closes after it', () async {
    output.send(update('a'));
    final expected = output.expect(1);
    output.close();
    await expected.timeout(const Duration(seconds: 1));
    expect(sink.closed, isFalse);
    output.send(answer(1));
    sink.flushes.single.complete();
    await pump();
    expect(sink.closed, isTrue);
    expect(sink.lines, hasLength(1));
  });

  test('close with nothing in flight closes the sink', () async {
    output.close();
    await pump();
    expect(sink.closed, isTrue);
  });
  group('tester U2 output boundaries', () {
    test(
      'a pending drain includes expectations added before it settles',
      () async {
        final first = output.expect(1);
        var drained = false;
        output.drained().then((_) => drained = true);
        final second = output.expect(2);
        output.send(answer(1));
        sink.flushes.single.complete();
        await first;
        await pump();
        expect(drained, isFalse, reason: 'answer 2 is still expected');
        output.send(answer(2));
        sink.flushes.last.complete();
        await second;
        await pump();
        expect(drained, isTrue);
      },
    );

    test(
      'a thousand queued updates preserve Unicode and control text in two adds',
      () async {
        output.send(update('first'));
        final texts = [
          for (var i = 0; i < 1000; i++) '$i 界👩‍💻e\u0301\n\u001b[31m',
        ];
        for (final text in texts) {
          output.send(update(text));
        }
        var written = false;
        output.expect(null).then((_) => written = true);
        output.send(answer(null));
        expect(sink.adds, 1);
        sink.flushes.first.complete();
        await pump();
        expect(sink.adds, 2);
        expect(sink.flushes, hasLength(2));
        expect(
          sink.lines
              .skip(1)
              .take(1000)
              .map((m) => (m['params'] as Map)['text']),
          texts,
        );
        expect(written, isFalse);
        sink.flushes.last.complete();
        await pump();
        expect(written, isTrue);
        output.close();
        await pump();
        expect(sink.closed, isTrue);
      },
    );

    test(
      'close drops queued updates and answers without another add',
      () async {
        output.send(update('in flight'));
        output.send(update('queued'));
        output.send(answer('queued answer'));
        var written = false;
        output.expect('queued answer').then((_) => written = true);
        output.close();
        output.close();
        await pump();
        expect(written, isTrue);
        expect(sink.closed, isFalse);
        expect(sink.adds, 1);
        sink.flushes.single.complete();
        await pump();
        expect(sink.closed, isTrue);
        expect(sink.adds, 1);
        expect(sink.lines, [update('in flight')]);
        await output.drained();
        await output.expect('after close');
      },
    );

    test(
      'a failure callback can close and attempt writes without restarting output',
      () async {
        var calls = 0;
        output = Output(
          sink,
          onFailed: (_) {
            calls++;
            output.close();
            output.send(update('late'));
          },
        );
        final expected = output.expect(9);
        output.send(update('first'));
        output.send(answer(9));
        sink.flushes.single.completeError(StateError('EPIPE'));
        await expected;
        await pump();
        expect(calls, 1);
        expect(output.failed, isTrue);
        expect(sink.adds, 1);
        expect(sink.flushes, hasLength(1));
        await output.drained();
      },
    );
  });
}

final class SocketLikeError {
  const SocketLikeError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is SocketLikeError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
