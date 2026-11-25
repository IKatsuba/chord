import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

class _MemoryTerminal extends Terminal {
  final writes = <String>[];
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) => writes.add(data);
}

class _MemoryStdio extends StdioTerminal {
  _MemoryStdio({super.environment = const {}, super.tmuxPassthrough})
    : super(input: const Stream.empty());
  final writes = <String>[];
  @override
  void write(String data) => writes.add(data);
}

class _SemanticTerminal extends _MemoryTerminal {
  final effects = <Object>[];
  @override
  void copyToClipboard(String text) => effects.add(('copy', text));
  @override
  void bell() => effects.add('bell');
  @override
  void notify(
    String message, {
    required NotificationChannel channel,
    String title = '',
  }) => effects.add(('notify', message, channel, title));
  @override
  void setTitle(String title) => effects.add(('title', title));
}

class _FailedTerminal extends _MemoryTerminal {
  @override
  void write(String data) => throw StateError('write failed');
}

void main() {
  test('clipboard writes UTF8 base64 including empty and control payloads', () {
    final terminal = _MemoryTerminal();
    for (final text in [
      '',
      'hello',
      '日本語 👩‍💻 e\u0301',
      '\x1b]2;payload\x07',
    ]) {
      terminal.copyToClipboard(text);
      final bytes = terminal.writes.last;
      expect(bytes, '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07');
      expect(
        utf8.decode(base64.decode(bytes.substring(7, bytes.length - 1))),
        text,
      );
    }
    expect(terminal.writes, hasLength(4));
  });
  test('notification channels and title flatten all OSC control fields', () {
    final terminal = _MemoryTerminal();
    const text = 'ready;日本語\x00\x07\x1b\x1f\x7f\x80\x9f';
    terminal.bell();
    terminal.notify(text, channel: NotificationChannel.bell, title: text);
    terminal.notify(text, channel: NotificationChannel.osc9, title: 'unused');
    terminal.notify(text, channel: NotificationChannel.osc777, title: text);
    terminal.setTitle(text);
    terminal.setTitle('');
    terminal.notify('', channel: NotificationChannel.osc777);
    expect(terminal.writes, [
      '\x07',
      '\x07',
      '\x1b]9;ready;日本語       \x07',
      '\x1b]777;notify;ready,日本語       ;ready,日本語       \x07',
      '\x1b]2;ready;日本語       \x07',
      '\x1b]2;\x07',
      '\x1b]777;notify;;\x07',
    ]);
  });
  test(
    'tmux forwards only OSC clipboard and notifications, title stays local',
    () async {
      final terminal = _MemoryStdio(environment: const {'TMUX': 'present'});
      terminal.copyToClipboard('x');
      terminal.notify('ready', channel: NotificationChannel.osc9);
      terminal.notify(
        'ready',
        channel: NotificationChannel.osc777,
        title: 'title',
      );
      terminal.notify('ready', channel: NotificationChannel.bell);
      terminal.bell();
      terminal.setTitle('local');
      expect(terminal.writes, [
        '\x1bPtmux;\x1b\x1b]52;c;eA==\x07\x1b\\',
        '\x1bPtmux;\x1b\x1b]9;ready\x07\x1b\\',
        '\x1bPtmux;\x1b\x1b]777;notify;title;ready\x07\x1b\\',
        '\x07',
        '\x07',
        '\x1b]2;local\x07',
      ]);
      await terminal.close();
    },
  );
  test('tmux overrides and empty environment are deterministic', () async {
    for (final (env, override, forwarded) in [
      (<String, String>{}, null, false),
      ({'TMUX': ''}, null, false),
      ({'TMUX': 'present'}, false, false),
      (<String, String>{}, true, true),
    ]) {
      final terminal = _MemoryStdio(
        environment: env,
        tmuxPassthrough: override,
      );
      terminal.copyToClipboard('');
      expect(terminal.writes.single.startsWith('\x1bPtmux;'), forwarded);
      await terminal.close();
    }
  });
  test('an application can fake semantic effects without emitting bytes', () {
    final Terminal terminal = _SemanticTerminal();
    terminal.copyToClipboard('text');
    terminal.bell();
    terminal.notify('ready', channel: NotificationChannel.osc9, title: 'title');
    terminal.setTitle('title');
    expect((terminal as _SemanticTerminal).effects, [
      ('copy', 'text'),
      'bell',
      ('notify', 'ready', NotificationChannel.osc9, 'title'),
      ('title', 'title'),
    ]);
    expect(terminal.writes, isEmpty);
  });
  test('failed writes propagate from every effect', () {
    final terminal = _FailedTerminal();
    for (final effect in <void Function()>[
      () => terminal.copyToClipboard('text'),
      terminal.bell,
      () => terminal.notify('ready', channel: NotificationChannel.osc9),
      () => terminal.notify('ready', channel: NotificationChannel.osc777),
      () => terminal.setTitle('title'),
    ]) {
      expect(effect, throwsStateError);
    }
  });

  group('CTUI-159: the terminal user variable', () {
    test('userVariableBytes is OSC 1337 SetUserVar, its value base64 UTF-8', () {
      expect(
        userVariableBytes('chord_session', 'abc-123'),
        '\x1b]1337;SetUserVar=chord_session=YWJjLTEyMw==\x07',
      );
      expect(
        userVariableBytes('chord_session', ''),
        '\x1b]1337;SetUserVar=chord_session=\x07',
      );
      expect(
        userVariableBytes('A_9', '日本\x1b;=\n'),
        '\x1b]1337;SetUserVar=A_9=${base64.encode(utf8.encode('日本\x1b;=\n'))}\x07',
      );
    });

    test('a name outside letters, digits and _ is refused', () {
      for (final name in ['', 'a=b', 'a b', 'a;b', 'a\x07', 'é', 'a-b']) {
        expect(
          () => userVariableBytes(name, 'x'),
          throwsArgumentError,
          reason: name,
        );
        expect(
          () => _MemoryTerminal().setUserVariable(name, 'x'),
          throwsArgumentError,
        );
      }
    });

    test('tmuxPassthrough doubles each ESC inside a DCS', () {
      expect(
        tmuxPassthrough('\x1b]1337;SetUserVar=a=\x07'),
        '\x1bPtmux;\x1b\x1b]1337;SetUserVar=a=\x07\x1b\\',
      );
      expect(tmuxPassthrough('plain'), '\x1bPtmux;plain\x1b\\');
    });

    test('a terminal writes it as it is; StdioTerminal through tmux when '
        'inside it', () async {
      final plain = _MemoryTerminal()..setUserVariable('v', 'x');
      expect(plain.writes, ['\x1b]1337;SetUserVar=v=eA==\x07']);
      final outside = _MemoryStdio()..setUserVariable('v', 'x');
      expect(outside.writes, ['\x1b]1337;SetUserVar=v=eA==\x07']);
      final inside = _MemoryStdio(environment: const {'TMUX': 'present'})
        ..setUserVariable('v', 'x')
        ..setUserVariable('v', '');
      expect(inside.writes, [
        '\x1bPtmux;\x1b\x1b]1337;SetUserVar=v=eA==\x07\x1b\\',
        '\x1bPtmux;\x1b\x1b]1337;SetUserVar=v=\x07\x1b\\',
      ]);
      final forced = _MemoryStdio(
        tmuxPassthrough: false,
        environment: const {'TMUX': 'present'},
      )..setUserVariable('v', 'x');
      expect(forced.writes, ['\x1b]1337;SetUserVar=v=eA==\x07']);
      for (final terminal in [outside, inside, forced]) {
        await terminal.close();
      }
    });
  });
}
