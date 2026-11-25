import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

// No machine here is WSL, whatever the host is.
final OpenUrlProbes _notWsl = (
  read: (_) => null,
  exists: (_) => false,
  executable: (_) => false,
);

void main() {
  const url = 'https://example.com/a?b=c';

  test("each platform's opener is asked with the link", () async {
    for (final (system, executable, arguments) in [
      ('macos', 'open', [url]),
      ('linux', 'xdg-open', [url]),
    ]) {
      final ran = <List<String>>[];
      final said = await openSystemUrl(
        url,
        operatingSystem: system,
        probes: _notWsl,
        run: (exe, args) async {
          ran.add([exe, ...args]);
          return (exitCode: 0, stdout: <int>[], stderr: '');
        },
      );
      expect(said, isNull);
      expect(ran, [
        [executable, ...arguments],
      ]);
    }
  });

  test('Windows starts the link through PowerShell, as powershell-utils '
      'names and encodes it', () async {
    const odd = "https://example.com/it's?x=’";
    for (final (environment, executable) in [
      (
        {'SYSTEMROOT': r'D:\Win', 'windir': r'E:\Other'},
        r'D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe',
      ),
      (
        {'SYSTEMROOT': '', 'windir': r'E:\Other'},
        r'E:\Other\System32\WindowsPowerShell\v1.0\powershell.exe',
      ),
      (
        <String, String>{},
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      ),
    ]) {
      final ran = <List<String>>[];
      final said = await openSystemUrl(
        odd,
        operatingSystem: 'windows',
        environment: environment,
        probes: _notWsl,
        run: (exe, args) async {
          ran.add([exe, ...args]);
          return (exitCode: 0, stdout: <int>[], stderr: '');
        },
        runIn: (_, _, _) => throw StateError('Windows runs in no folder'),
      );
      expect(said, isNull);
      final [exe, ...args] = ran.single;
      expect(exe, executable);
      expect(args.take(5), [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
      ]);
      expect(args, hasLength(6));
      final bytes = base64.decode(args[5]);
      expect(
        String.fromCharCodes([
          for (var i = 0; i < bytes.length; i += 2)
            bytes[i] | bytes[i + 1] << 8,
        ]),
        "\$ProgressPreference = 'SilentlyContinue'; "
        "Start 'https://example.com/it''s?x=’’'",
      );
    }
  });

  test('a path on Windows is started as it is, with no wslpath', () async {
    final ran = <String>[];
    await openSystemUrl(
      r'C:\x\a.html',
      operatingSystem: 'windows',
      environment: const {},
      probes: _notWsl,
      run: (exe, args) async {
        ran.add(exe);
        return (exitCode: 0, stdout: <int>[], stderr: '');
      },
    );
    expect(ran, hasLength(1));
    expect(ran.single, endsWith('powershell.exe'));
  });

  test('only an opener that cannot start says why: no exit code is '
      'read', () async {
    for (final system in ['macos', 'linux', 'windows']) {
      for (final result in [
        (exitCode: 3, stdout: <int>[], stderr: 'no browser\n'),
        (exitCode: 4, stdout: <int>[], stderr: ''),
      ]) {
        expect(
          await openSystemUrl(
            url,
            operatingSystem: system,
            environment: const {},
            probes: _notWsl,
            run: (_, _) async => result,
          ),
          isNull,
          reason: system,
        );
      }
      expect(
        await openSystemUrl(
          url,
          operatingSystem: system,
          environment: const {},
          probes: _notWsl,
          run: (exe, _) => throw ProcessException(exe, [], 'not found'),
        ),
        'not found',
        reason: system,
      );
    }
  });

  test("the process's terminal opens through its runner", () async {
    final ran = <String>[];
    final terminal = StdioTerminal(
      input: const Stream.empty(),
      openUrlProbes: _notWsl,
      clipboardRunner: (exe, args) async {
        ran.add(args.last);
        return (exitCode: 0, stdout: <int>[], stderr: '');
      },
    );
    expect(await terminal.openUrl(url), isNull);
    expect(ran, [url]);
  });
}
