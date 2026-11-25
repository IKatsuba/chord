import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-159: user variable output sink', () {
    for (final (environment, override, wrapped) in [
      (<String, String>{}, null, false),
      ({'TMUX': 'present'}, null, true),
      ({'TMUX': 'present'}, false, false),
      (<String, String>{}, true, true),
    ]) {
      test(
        'sink preserves a thousand updates wrapped=$wrapped override=$override',
        () async {
          final dir = Directory.systemTemp.createTempSync('terminal-user-var-');
          final file = File('${dir.path}/output');
          final sink = file.openWrite();
          final terminal = StdioTerminal(
            input: const Stream.empty(),
            output: sink,
            environment: environment,
            tmuxPassthrough: override,
          );
          final expected = StringBuffer();
          try {
            for (var i = 0; i < 1000; i++) {
              final value = i.isEven ? '' : '界👩‍💻é\x1b]a;=\x07 $i';
              terminal.setUserVariable('session_9', value);
              final plain =
                  '\x1b]1337;SetUserVar=session_9=${base64.encode(utf8.encode(value))}\x07';
              expected.write(
                wrapped
                    ? '\x1bPtmux;${plain.replaceAll('\x1b', '\x1b\x1b')}\x1b\\'
                    : plain,
              );
            }
            await sink.flush();
            expect(file.readAsBytesSync(), utf8.encode('$expected'));
            final before = file.lengthSync();
            for (final name in [
              'invalid\n',
              'name\x1b',
              'name\u007f',
              '界',
              'a-b',
            ]) {
              expect(
                () => terminal.setUserVariable(name, 'payload'),
                throwsArgumentError,
              );
            }
            await sink.flush();
            expect(file.lengthSync(), before);
          } finally {
            await terminal.close();
            await sink.close();
            dir.deleteSync(recursive: true);
          }
        },
      );
    }
  });
  group('tester: terminal effect encoding boundaries', () {
    test(
      'every C0 DEL and C1 control flattens without changing neighbors',
      () async {
        final terminal = _RecordedTerminal();
        for (final code in [
          for (var i = 0; i < 32; i++) i,
          for (var i = 127; i < 160; i++) i,
        ]) {
          final text = ' ~\u00a0界👩‍💻e\u0301${String.fromCharCode(code)};end';
          terminal.setTitle(text);
          terminal.notify(text, channel: NotificationChannel.osc9, title: text);
          terminal.notify(
            text,
            channel: NotificationChannel.osc777,
            title: text,
          );
          const clean = ' ~\u00a0界👩‍💻e\u0301 ;end';
          const field = ' ~\u00a0界👩‍💻e\u0301 ,end';
          expect(terminal.writes.sublist(terminal.writes.length - 3), [
            '\x1b]2;$clean\x07',
            '\x1bPtmux;\x1b\x1b]9;$clean\x07\x1b\\',
            '\x1bPtmux;\x1b\x1b]777;notify;$field;$field\x07\x1b\\',
          ], reason: 'control $code');
        }
        await terminal.close();
      },
    );

    test(
      'clipboard offers preserve long text and embedded protocol strings',
      () async {
        final terminal = _RecordedTerminal();
        final text = List.filled(
          1000,
          '界👩‍💻e\u0301\x1b]52;c;evil\x07\x1b\\',
        ).join();
        terminal.copyToClipboard(text);
        final expected =
            '\x1bPtmux;\x1b\x1b]52;c;'
            '${base64.encode(utf8.encode(text))}\x07\x1b\\';
        expect(terminal.writes, [expected]);
        terminal.bell();
        terminal.setTitle('');
        terminal.copyToClipboard('');
        expect(terminal.writes.skip(1), [
          '\x07',
          '\x1b]2;\x07',
          '\x1bPtmux;\x1b\x1b]52;c;\x07\x1b\\',
        ]);
        await terminal.close();
      },
    );

    test('forwarded effects propagate the exact write error', () async {
      final terminal = _RecordedTerminal();
      final failure = StateError('test write failure');
      terminal.failure = failure;
      for (final effect in <void Function()>[
        () => terminal.copyToClipboard(''),
        () => terminal.notify('', channel: NotificationChannel.osc9),
        () => terminal.notify('', channel: NotificationChannel.osc777),
        () => terminal.notify('', channel: NotificationChannel.bell),
        () => terminal.setTitle(''),
      ]) {
        expect(effect, throwsA(same(failure)));
      }
      expect(terminal.writes, isEmpty);
      await terminal.close();
    });
  });
}

class _RecordedTerminal extends StdioTerminal {
  _RecordedTerminal()
    : super(input: const Stream.empty(), tmuxPassthrough: true);
  final writes = <String>[];
  Object? failure;
  @override
  void write(String data) {
    if (failure case final error?) throw error;
    writes.add(data);
  }
}
