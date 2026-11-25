// The original's tests/session/codex_resources_test.ts: Codex's app server
// read through json_rpc_2 and the adapter that adds and takes off
// "jsonrpc".
@TestOn('posix')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/wire.dart' show MessageTooLargeError;
import 'package:chord/platform/resource_process.dart';
import 'package:chord/session/codex_resources.dart';
import 'package:path/path.dart' as p;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

bool _dead(int pid) => !Process.killPid(pid, ProcessSignal.sigcont);

void main() {
  group('CTUI-37 tester: byte-line framing boundaries', () {
    Future<({List<String> lines, List<Object> errors})> capture(
      String text,
      int cap,
    ) async {
      final output = StreamController<List<int>>();
      final input = StreamController<List<int>>();
      final drain = input.stream.listen((_) {});
      final channel = lineChannel(output.stream, input.sink, maxLineBytes: cap);
      final lines = <String>[], errors = <Object>[];
      final done = Completer<void>();
      final subscription = channel.stream.listen(
        lines.add,
        onError: errors.add,
        onDone: done.complete,
      );
      try {
        for (final byte in utf8.encode(text)) {
          output.add([byte]);
        }
        await output.close();
        await done.future.timeout(const Duration(seconds: 5));
        return (lines: lines, errors: errors);
      } finally {
        await output.close();
        await subscription.cancel();
        await channel.sink.close();
        await input.close();
        await drain.cancel();
      }
    }

    test(
      'the cap counts UTF-8 bytes even when each byte is a separate chunk',
      () async {
        const message = '{"x":"é"}';
        final bytes = utf8.encode(message).length;
        final exact = await capture('$message\n', bytes);
        expect(exact.lines, [message]);
        expect(exact.errors, isEmpty);
        final tooSmall = await capture('$message\n', bytes - 1);
        expect(tooSmall.lines, isEmpty);
        expect(tooSmall.errors, [isA<MessageTooLargeError>()]);
      },
    );

    test(
      'EOF preserves a final complete object and refuses a torn object',
      () async {
        final complete = await capture('{"x":"界👩‍💻"}', 1024);
        expect(complete.lines.map(jsonDecode), [
          {'x': '界👩‍💻'},
        ]);
        expect(complete.errors, isEmpty);
        final torn = await capture('{"x":', 1024);
        expect(torn.lines, isEmpty);
        expect(torn.errors, [isA<FormatException>()]);
      },
    );
  });

  group("the adapter between json_rpc_2 and Codex's messages", () {
    test('adds "jsonrpc" to what Codex sends, takes it off what chord sends, '
        'and fails a line that is not an object', () async {
      final fromCodex = StreamController<String>();
      final toCodex = <String>[];
      final codex = StreamChannel<String>(
        fromCodex.stream,
        StreamController<String>()..stream.listen(toCodex.add),
      );
      final channel = codexChannel(codex);
      final heard = <Object?>[];
      final errors = <Object>[];
      channel.stream.listen(heard.add, onError: errors.add);
      channel.sink.add({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize'});
      fromCodex
        ..add('{"id":0,"result":{"userAgent":"fake"}}')
        ..add('[1]');
      await pumpEventQueue();
      expect(toCodex, ['{"id":0,"method":"initialize"}']);
      expect(heard, [
        {
          'jsonrpc': '2.0',
          'id': 0,
          'result': {'userAgent': 'fake'},
        },
      ]);
      expect(errors.single, isA<FormatException>());
    });
  });

  group("a line past the framing's cap", () {
    for (final mode in ['oversize', 'growing']) {
      test('$mode is refused as it passes the cap, and the group is seen '
          'gone', () async {
        final dir = Directory.systemTemp.createTempSync('chord-codex-flood-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final record = p.join(dir.path, 'events.jsonl');
        final started = DateTime.now();
        await expectLater(
          collectCodexResources(
            [
              Platform.resolvedExecutable,
              p.join(
                Directory.current.path,
                'test',
                'fixtures',
                'codex_flood_fake.dart',
              ),
              mode,
              record,
            ],
            cwd: dir.path,
            cancelled: CancellationToken(),
            maxLineBytes: 64 * 1024,
          ),
          throwsA(
            isA<ResourceReadError>()
                .having((e) => e.kind, 'kind', 'protocol')
                .having(
                  (e) => e.message,
                  'message',
                  'The collector failed to return supported resource facts.',
                ),
          ),
        );
        // Refused as the line passed the cap, never at the 20 s total.
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 10)),
        );
        final pid =
            (jsonDecode(File(record).readAsLinesSync().first) as Map)['pid']
                as int;
        expect(_dead(pid), isTrue);
      });
    }

    test('the cap is the ACP framing\'s own unless given', () async {
      final stdout = StreamController<List<int>>();
      final channel = lineChannel(
        stdout.stream,
        StreamController<List<int>>(),
        maxLineBytes: 8,
      );
      final heard = <String>[];
      final errors = <Object>[];
      channel.stream.listen(heard.add, onError: errors.add);
      stdout
        ..add(utf8.encode('{"id":1}\n'))
        ..add(utf8.encode('{"id":2,"x":1}\n'));
      await pumpEventQueue();
      expect(heard, ['{"id":1}']);
      expect(errors.single, isA<MessageTooLargeError>());
    });
  }, timeout: const Timeout(Duration(minutes: 1)));
}
