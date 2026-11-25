import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

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
  _MemoryStdio() : super(input: const Stream.empty(), tmuxPassthrough: true);
  final writes = <String>[];
  @override
  void write(String data) => writes.add(data);
}

class _SemanticTerminal extends _MemoryTerminal {
  final effects = <Object>[];
  @override
  void setProgramStatus(ProgramStatus status) => effects.add(status);
  @override
  void clearProgramStatus({String? id}) => effects.add(('clear', id));
}

void main() {
  group("the process's terminal takes its status off as it is given back", () {
    const clear = '\x1b]7501;state=clear\x1b\\';
    test('a reported status is cleared once, by the release', () async {
      final terminal = _ReleasedStdio();
      terminal.setProgramStatus(const ProgramStatus(ProgramState.working));
      final before = terminal.writes.length;
      await terminal.leave();
      expect(terminal.writes.sublist(before), [clear]);
      await terminal.leave();
      expect(terminal.writes.where((w) => w == clear), hasLength(1));
      await terminal.close();
    });

    test('none reported, or one already cleared, writes none', () async {
      final never = _ReleasedStdio();
      await never.leave();
      expect(never.writes, isEmpty);
      await never.close();
      final cleared = _ReleasedStdio()
        ..setProgramStatus(const ProgramStatus(ProgramState.idle))
        ..clearProgramStatus();
      final before = cleared.writes.length;
      await cleared.leave();
      expect(cleared.writes.sublist(before), isEmpty);
      await cleared.close();
    });

    test('clearing one record of it leaves the root to the release', () async {
      final terminal = _ReleasedStdio()
        ..setProgramStatus(const ProgramStatus(ProgramState.idle))
        ..clearProgramStatus(id: 'a');
      final before = terminal.writes.length;
      await terminal.leave();
      expect(terminal.writes.sublist(before), [clear]);
      await terminal.close();
    });
  });

  group('program status', () {
    // Each expected report is what OpenTUI's setProgramStatus wrote for the
    // same record.
    test('records are written as OpenTUI writes them', () {
      final terminal = _MemoryTerminal();
      terminal.setProgramStatus(
        const ProgramStatus(ProgramState.idle, app: 'chord'),
      );
      terminal.setProgramStatus(
        const ProgramStatus(
          ProgramState.done,
          app: 'chord',
          title: 'slow',
          message: 'fake is waiting; for: input',
        ),
      );
      terminal.setProgramStatus(
        const ProgramStatus(
          ProgramState.blocked,
          kind: ProgramStatusKind.permission,
          progress: 40,
          app: 'chord',
          id: 'a/b',
          title: 'é',
        ),
      );
      terminal.setProgramStatus(
        const ProgramStatus(ProgramState.working, progress: 7, id: 'x'),
      );
      terminal.setProgramStatus(
        const ProgramStatus(ProgramState.working, progress: 0),
      );
      terminal.setProgramStatus(
        const ProgramStatus(ProgramState.blocked, kind: ProgramStatusKind.auth),
      );
      terminal.setProgramStatus(const ProgramStatus(ProgramState.error));
      terminal.clearProgramStatus(id: 'a');
      terminal.clearProgramStatus();
      expect(terminal.writes, [
        '\x1b]7501;state=idle:app=chord\x1b\\',
        '\x1b]7501;state=done:app=chord:title=c2xvdw==:'
            'msg=ZmFrZSBpcyB3YWl0aW5nOyBmb3I6IGlucHV0\x1b\\',
        '\x1b]7501;state=blocked:id=a/b:kind=permission:progress=40:'
            'app=chord:title=w6k=\x1b\\',
        '\x1b]7501;state=working:id=x:progress=7\x1b\\',
        '\x1b]7501;state=working:progress=0\x1b\\',
        '\x1b]7501;state=blocked:kind=auth\x1b\\',
        '\x1b]7501;state=error\x1b\\',
        '\x1b]7501;state=clear:id=a\x1b\\',
        '\x1b]7501;state=clear\x1b\\',
      ]);
    });

    test('empty text fields are left out', () {
      final terminal = _MemoryTerminal();
      terminal.setProgramStatus(
        const ProgramStatus(ProgramState.idle, app: '', title: '', message: ''),
      );
      expect(terminal.writes, ['\x1b]7501;state=idle\x1b\\']);
    });

    test('the bounds hold at their limits', () {
      final terminal = _MemoryTerminal();
      final id = List.filled(8, 'a' * 15).join('/');
      expect(id.length, 127);
      terminal.setProgramStatus(
        ProgramStatus(
          ProgramState.idle,
          id: id,
          app: 'A-z_0.9+${'x' * 24}',
          title: '界' * 64,
          message: 'x' * 2048,
        ),
      );
      expect(terminal.writes, hasLength(1));
    });

    test('a record outside the protocol is refused and nothing is written', () {
      final terminal = _MemoryTerminal();
      for (final status in [
        const ProgramStatus(ProgramState.idle, title: 'a\nb'),
        const ProgramStatus(ProgramState.idle, message: 'a\x7fb'),
        const ProgramStatus(ProgramState.idle, message: 'a\u0085b'),
        ProgramStatus(ProgramState.idle, title: 'x' * 193),
        ProgramStatus(ProgramState.idle, title: '界' * 65),
        ProgramStatus(ProgramState.idle, message: 'x' * 2049),
        const ProgramStatus(ProgramState.idle, app: 'a b'),
        ProgramStatus(ProgramState.idle, app: 'x' * 33),
        const ProgramStatus(ProgramState.idle, id: ''),
        const ProgramStatus(ProgramState.idle, id: 'a//b'),
        const ProgramStatus(ProgramState.idle, id: 'a/'),
        ProgramStatus(ProgramState.idle, id: 'x' * 33),
        ProgramStatus(ProgramState.idle, id: List.filled(9, 'a').join('/')),
        ProgramStatus(
          ProgramState.idle,
          id: List.filled(5, 'x' * 25).join('/'),
        ),
        const ProgramStatus(
          ProgramState.working,
          kind: ProgramStatusKind.question,
        ),
        const ProgramStatus(ProgramState.done, progress: 1),
        const ProgramStatus(ProgramState.working, progress: 101),
        const ProgramStatus(ProgramState.blocked, progress: -1),
      ]) {
        expect(
          () => terminal.setProgramStatus(status),
          throwsArgumentError,
          reason: '$status',
        );
      }
      for (final id in ['', 'a b', 'a//b']) {
        expect(() => terminal.clearProgramStatus(id: id), throwsArgumentError);
      }
      expect(terminal.writes, isEmpty);
    });

    test('tmux passthrough leaves program status unwrapped', () async {
      final terminal = _MemoryStdio();
      terminal.setProgramStatus(const ProgramStatus(ProgramState.idle));
      terminal.clearProgramStatus();
      terminal.notify('x', channel: NotificationChannel.osc9);
      expect(terminal.writes.take(2), [
        '\x1b]7501;state=idle\x1b\\',
        '\x1b]7501;state=clear\x1b\\',
      ]);
      expect(terminal.writes.last, startsWith('\x1bPtmux;'));
      await terminal.close();
    });

    test('an application can fake the reports without emitting bytes', () {
      final Terminal terminal = _SemanticTerminal();
      const status = ProgramStatus(ProgramState.working, app: 'chord');
      terminal.setProgramStatus(status);
      terminal.clearProgramStatus(id: 'a');
      expect((terminal as _SemanticTerminal).effects, [
        const ProgramStatus(ProgramState.working, app: 'chord'),
        ('clear', 'a'),
      ]);
      expect(terminal.writes, isEmpty);
    });

    test('records compare by value', () {
      expect(
        const ProgramStatus(ProgramState.done, title: 't'),
        ProgramStatus(ProgramState.done, title: 't' * 1),
      );
      expect(
        const ProgramStatus(ProgramState.done, title: 't'),
        isNot(const ProgramStatus(ProgramState.done, message: 't')),
      );
    });
  });

  group('tester: status release during suspension', () {
    final pty =
        !Platform.isWindows &&
        Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
    for (final fails in [false, true]) {
      test(
        'clear precedes callback, resume reports latest, failure=$fails',
        () async {
          final result = await runExpect([
            '-c',
            '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/program_status_release_tester.dart $fails
expect eof
catch wait result
exit [lindex \$result 3]
''',
          ]);
          final output = '${result.stdout}${result.stderr}';
          expect(result.exitCode, 0, reason: output);
          expect(output, contains('STATUS_RELEASE_PASS=$fails'));
        },
        skip: pty ? false : 'POSIX and expect are required',
      );
    }
  });

  group('tester: program status wire boundaries', () {
    test('every control is refused atomically in either text field', () {
      final terminal = _MemoryTerminal();
      for (final code in [
        ...List.generate(32, (i) => i),
        ...List.generate(33, (i) => i + 127),
      ]) {
        final text = 'before${String.fromCharCode(code)}after';
        for (final status in [
          ProgramStatus(ProgramState.idle, title: text),
          ProgramStatus(ProgramState.idle, message: text),
        ]) {
          expect(
            () => terminal.setProgramStatus(status),
            throwsArgumentError,
            reason: 'control $code',
          );
        }
      }
      expect(terminal.writes, isEmpty);
    });

    test(
      'Unicode payloads preserve emoji and combining marks at byte limits',
      () {
        final terminal = _MemoryTerminal();
        final title = '${'x' * 185}👩e\u0301';
        final message = '${'界' * 681}😀x';
        expect(utf8.encode(title), hasLength(192));
        expect(utf8.encode(message), hasLength(2048));
        terminal.setProgramStatus(
          ProgramStatus(
            ProgramState.blocked,
            kind: ProgramStatusKind.question,
            progress: 100,
            title: title,
            message: message,
          ),
        );
        expect(
          terminal.writes.single,
          '\x1b]7501;state=blocked:kind=question:progress=100:'
          'title=${base64.encode(utf8.encode(title))}:'
          'msg=${base64.encode(utf8.encode(message))}\x1b\\',
        );
        for (final status in [
          ProgramStatus(ProgramState.idle, title: '${title}x'),
          ProgramStatus(ProgramState.idle, message: '${message}x'),
        ]) {
          expect(() => terminal.setProgramStatus(status), throwsArgumentError);
        }
        expect(terminal.writes, hasLength(1));
      },
    );

    test('path limits apply identically to reports and clears', () {
      final terminal = _MemoryTerminal();
      final id = ['a' * 32, 'b' * 32, 'c' * 32, 'd' * 29].join('/');
      expect(id, hasLength(128));
      terminal.setProgramStatus(ProgramStatus(ProgramState.idle, id: id));
      terminal.clearProgramStatus(id: id);
      expect(terminal.writes, [
        '\x1b]7501;state=idle:id=$id\x1b\\',
        '\x1b]7501;state=clear:id=$id\x1b\\',
      ]);
      for (final invalid in [
        '${id}x',
        '/a',
        'a:b',
        'a;b',
        'a=b',
        'é',
        'a\x1b\\',
        'a\n',
      ]) {
        expect(
          () => terminal.setProgramStatus(
            ProgramStatus(ProgramState.idle, id: invalid),
          ),
          throwsArgumentError,
        );
        expect(
          () => terminal.clearProgramStatus(id: invalid),
          throwsArgumentError,
        );
      }
      expect(terminal.writes, hasLength(2));
    });

    test('a replacement carries no fields from the preceding record', () {
      final terminal = _MemoryTerminal();
      for (var i = 0; i < 1000; i++) {
        terminal.setProgramStatus(
          const ProgramStatus(
            ProgramState.blocked,
            id: 'build/test',
            app: 'A-z_0.9+',
            title: 'title',
            message: ':;=',
            kind: ProgramStatusKind.question,
            progress: 100,
          ),
        );
        terminal.setProgramStatus(
          const ProgramStatus(ProgramState.idle, id: 'build/test'),
        );
      }
      expect(terminal.writes, hasLength(2000));
      expect(
        terminal.writes.where(
          (s) => s == '\x1b]7501;state=idle:id=build/test\x1b\\',
        ),
        hasLength(1000),
      );
      expect(terminal.writes.first, contains(':msg=Ojs9'));
    });
  });
}

class _ReleasedStdio extends StdioTerminal {
  _ReleasedStdio() : super(input: const Stream.empty());
  final writes = <String>[];
  @override
  void write(String data) => writes.add(data);
}
