// What the Dart fake does as a process: a bad flag ends it at once, and a
// wedged one outlives SIGTERM and its stdin, going only with SIGKILL.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../fake.dart';

void main() {
  test(
    'an unknown scenario or flag value ends it with 1, saying which',
    () async {
      for (final (flags, words) in [
        (['--scenario', 'nope'], 'unknown scenario "nope"'),
        (['--hang', 'later'], 'unknown step to hang at "later"'),
        (['--mcp-transports', 'ws'], 'unknown MCP transport to advertise "ws"'),
      ]) {
        final command = dartFakeCommand(null, flags);
        final result = await Process.run(
          command.first,
          command.skip(1).toList(),
        );
        expect(result.exitCode, 1, reason: '$flags');
        expect(result.stderr, contains(words));
      }
    },
  );

  test(
    'a wait with a timeout keeps it alive no longer than its client',
    () async {
      final command = dartFakeCommand('texttillsteered', const [
        '--step-ms',
        '1',
      ]);
      final process = await Process.start(
        command.first,
        command.skip(1).toList(),
      );
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
          .asBroadcastStream();
      Future<Map<String, Object?>> answer(int id) =>
          lines.firstWhere((message) => message['id'] == id);
      void send(Map<String, Object?> message) =>
          process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...message}));
      final dir = Directory.systemTemp.createTempSync('chord-fake-exit-');
      addTearDown(() => dir.deleteSync(recursive: true));

      final initialized = answer(0);
      send({
        'id': 0,
        'method': 'initialize',
        'params': {'protocolVersion': 1},
      });
      await initialized;
      final opened = answer(1);
      send({
        'id': 1,
        'method': 'session/new',
        'params': {'cwd': dir.path, 'mcpServers': []},
      });
      final sessionId = ((await opened)['result'] as Map)['sessionId'];
      final replied = answer(2);
      final said = lines.firstWhere(
        (message) => jsonEncode(message).contains(' came in chunks.'),
      );
      send({
        'id': 2,
        'method': 'session/prompt',
        'params': {
          'sessionId': sessionId,
          'prompt': [
            {'type': 'text', 'text': 'go'},
          ],
        },
      });
      await said;
      send({
        'method': 'session/cancel',
        'params': {'sessionId': sessionId},
      });
      expect((await replied)['result'], {'stopReason': 'cancelled'});
      await process.stdin.close();
      expect(
        await process.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => -1,
        ),
        0,
        reason: 'its 10 s timeout must not hold it',
      );
    },
  );

  test('with --hang start it never answers initialize, and SIGTERM and the '
      'end of its stdin leave it running', () async {
    final command = dartFakeCommand(null, const ['--hang', 'start']);
    final process = await Process.start(
      command.first,
      command.skip(1).toList(),
    );
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final out = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(out.write);
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'initialize',
        'params': {'protocolVersion': 1},
      }),
    );
    await process.stdin.flush();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    process.kill();
    await process.stdin.close();
    final early = await process.exitCode.timeout(
      const Duration(milliseconds: 700),
      onTimeout: () => -1,
    );
    expect(early, -1, reason: 'it is still running');
    expect(out.toString(), isEmpty);
    process.kill(ProcessSignal.sigkill);
    expect(await process.exitCode, isNot(0));
  });
}
