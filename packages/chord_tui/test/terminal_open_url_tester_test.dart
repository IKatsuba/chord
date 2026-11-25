import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  _wslTesterCases();
  group('tester URL opener runner boundaries', () {
    test('URL stays one literal argument on every platform', () async {
      const url =
          "https://example.com/a b?x=界👩‍💻e\u0301&next=\$(ignored);it's‘’‚‛";
      for (final system in ['macos', 'windows', 'linux']) {
        final calls = <List<String>>[];
        expect(
          await openSystemUrl(
            url,
            operatingSystem: system,
            environment: const {},
            probes: (
              read: (_) => null,
              exists: (_) => false,
              executable: (_) => false,
            ),
            run: (exe, args) async {
              calls.add([exe, ...args]);
              return (
                exitCode: 0,
                stdout: <int>[],
                stderr: 'ignored success diagnostic',
              );
            },
          ),
          isNull,
        );
        expect(calls, hasLength(1));
        if (system == 'windows') {
          expect(
            calls.single.first,
            r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
          );
          expect(calls.single.sublist(1, 6), [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
          ]);
          final bytes = base64.decode(calls.single.last);
          expect(bytes.length.isEven, isTrue);
          final command = String.fromCharCodes([
            for (var i = 0; i < bytes.length; i += 2)
              bytes[i] | bytes[i + 1] << 8,
          ]);
          expect(
            command,
            "\$ProgressPreference = 'SilentlyContinue'; Start 'https://example.com/a b?x=界👩‍💻e\u0301&next=\$(ignored);it''s‘‘’’‚‚‛‛'",
          );
        } else {
          expect(calls.single.last, url);
          expect(calls.single.where((arg) => arg == url), hasLength(1));
        }
      }
    });

    test(
      'concurrent opener failures retain their own asynchronous results',
      () async {
        final first =
            Completer<({int exitCode, List<int> stdout, String stderr})>();
        final second =
            Completer<({int exitCode, List<int> stdout, String stderr})>();
        final calls = <String>[];
        Future<({int exitCode, List<int> stdout, String stderr})> run(
          String _,
          List<String> args,
        ) {
          calls.add(args.single);
          return calls.length == 1 ? first.future : second.future;
        }

        final a = openSystemUrl(
          'https://first.example',
          operatingSystem: 'linux',
          probes: (
            read: (_) => null,
            exists: (_) => false,
            executable: (_) => false,
          ),
          run: run,
        );
        final b = openSystemUrl(
          'https://second.example',
          operatingSystem: 'linux',
          probes: (
            read: (_) => null,
            exists: (_) => false,
            executable: (_) => false,
          ),
          run: run,
        );
        second.completeError(
          ProcessException('xdg-open', const [], 'second failed'),
        );
        expect(await b, 'second failed');
        first.completeError(
          ProcessException('xdg-open', const [], 'first failed'),
        );
        expect(await a, 'first failed');
        expect(calls, ['https://first.example', 'https://second.example']);
      },
    );
  });
}

void _wslTesterCases() {
  const powershell =
      '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
  final OpenUrlProbes probes = (
    read: (path) => path == '/proc/version' ? 'Microsoft WSL' : null,
    exists: (_) => false,
    executable: (path) => path == powershell,
  );
  group('tester CTUI-170: isolated WSL runner boundaries', () {
    test(
      'Unicode surrogate pairs and apostrophes survive encoded PowerShell',
      () async {
        const url = "https://example.com/界👩‍💻e\u0301?q=it's";
        final calls = <List<String>>[];
        expect(
          await openSystemUrl(
            url,
            operatingSystem: 'linux',
            environment: const {},
            probes: probes,
            run: (exe, args) async {
              calls.add([exe, ...args]);
              return (exitCode: 0, stdout: <int>[], stderr: '');
            },
          ),
          isNull,
        );
        final bytes = base64.decode(calls.single.last);
        final decoded = String.fromCharCodes([
          for (var i = 0; i < bytes.length; i += 2)
            bytes[i] | bytes[i + 1] << 8,
        ]);
        expect(calls.single.first, powershell);
        expect(
          decoded,
          "\$ProgressPreference = 'SilentlyContinue'; Start 'https://example.com/界👩‍💻e\u0301?q=it''s'",
        );
      },
    );
    test('concurrent WSL failures stay with their own caller', () async {
      final pending =
          <Completer<({int exitCode, List<int> stdout, String stderr})>>[];
      Future<String?> open(String url) => openSystemUrl(
        url,
        operatingSystem: 'linux',
        environment: const {},
        probes: probes,
        run: (_, _) async => throw StateError('URL needs no path conversion'),
        runIn: (exe, args, cwd) {
          expect(exe, powershell);
          expect(cwd, '/mnt/c/Windows/System32/WindowsPowerShell/v1.0');
          final result =
              Completer<({int exitCode, List<int> stdout, String stderr})>();
          pending.add(result);
          return result.future;
        },
      );
      final first = open('https://first.example');
      final second = open('https://second.example');
      // URL encoding is asynchronous before the opener is called.
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(2));
      pending[1].completeError(
        ProcessException(powershell, const [], 'second failed'),
      );
      expect(await second, 'second failed');
      pending[0].completeError(
        ProcessException(powershell, const [], 'first failed'),
      );
      expect(await first, 'first failed');
    });
  });
}
