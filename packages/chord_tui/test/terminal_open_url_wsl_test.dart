// openSystemUrl under WSL, as the original's `open` 11.0.4 does it, with
// is-wsl, is-inside-container, is-in-ssh, wsl-utils and powershell-utils.
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _url = 'https://example.com/a?b=c';
const _ps = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';

typedef _Result = ({int exitCode, List<int> stdout, String stderr});
const _Result _ok = (exitCode: 0, stdout: <int>[], stderr: '');

OpenUrlProbes _machine({
  Map<String, String> files = const {},
  Set<String> paths = const {},
  Set<String> executables = const {_ps},
}) => (
  read: (path) => files[path],
  exists: (path) => paths.contains(path) || files.containsKey(path),
  executable: executables.contains,
);

const _wsl = {
  '/proc/sys/kernel/osrelease': '5.15.153.1-microsoft-standard-WSL2\n',
};

/// What PowerShell was asked to run, decoded.
String _decoded(List<String> arguments) {
  expect(arguments.take(5), [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
  ]);
  final bytes = base64.decode(arguments[5]);
  return String.fromCharCodes([
    for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
  ]);
}

void main() {
  _isolation();
  late List<List<String>> ran;
  late List<(String, List<String>, String)> ranIn;
  Future<String?> open(
    String target, {
    OpenUrlProbes? probes,
    Map<String, String> environment = const {},
    String system = 'linux',
    _Result result = _ok,
    _Result Function(String, List<String>)? answer,
  }) => openSystemUrl(
    target,
    operatingSystem: system,
    environment: environment,
    probes: probes ?? _machine(files: _wsl),
    run: (exe, args) async {
      ran.add([exe, ...args]);
      return answer?.call(exe, args) ?? _ok;
    },
    runIn: (exe, args, dir) async {
      ranIn.add((exe, args, dir));
      return result;
    },
  );

  setUp(() {
    ran = [];
    ranIn = [];
  });

  test('WSL starts the link through PowerShell, from its own folder', () async {
    expect(await open(_url), isNull);
    expect(ran, isEmpty);
    final (exe, args, dir) = ranIn.single;
    expect(exe, _ps);
    expect(dir, '/mnt/c/Windows/System32/WindowsPowerShell/v1.0');
    expect(
      _decoded(args),
      "\$ProgressPreference = 'SilentlyContinue'; Start '$_url'",
    );
  });

  test('each of is-wsl\'s signs tells WSL', () async {
    for (final probes in [
      _machine(files: {'/proc/version': 'Linux version 5.15 (Microsoft@x)'}),
      _machine(paths: {'/proc/sys/fs/binfmt_misc/WSLInterop'}),
      _machine(paths: {'/run/WSL'}),
    ]) {
      ranIn.clear();
      await open(_url, probes: probes);
      expect(ranIn, hasLength(1));
    }
    expect(ran, isEmpty);
  });

  test('a container, an SSH session, no PowerShell or another system takes '
      'the platform opener', () async {
    for (final (probes, environment) in <(OpenUrlProbes, Map<String, String>)>[
      (_machine(files: _wsl, paths: {'/run/.containerenv'}), const {}),
      (_machine(files: _wsl, paths: {'/.dockerenv'}), const {}),
      (
        _machine(files: {..._wsl, '/proc/self/cgroup': '0::/docker/abc'}),
        const {},
      ),
      for (final name in ['SSH_CONNECTION', 'SSH_CLIENT', 'SSH_TTY'])
        (_machine(files: _wsl), {name: 'x'}),
      (_machine(files: _wsl, executables: {}), const {}),
      (_machine(), const {}),
    ]) {
      ran.clear();
      await open(_url, probes: probes, environment: environment);
      expect(ran, [
        ['xdg-open', _url],
      ]);
    }
    ran.clear();
    await open(_url, system: 'macos');
    expect(ran, [
      ['open', _url],
    ]);
    expect(ranIn, isEmpty);
  });

  test("the drives' mount point is wsl.conf's root", () async {
    for (final (config, root) in [
      ('[automount]\nroot = /win\n', '/win/'),
      ('# root = /no\n[automount]\nroot = "/q/"  \n', '/q/'),
      ("root='/s' # mine\n", '/s/'),
      ('[automount]\nenabled = true\n', '/mnt/'),
    ]) {
      final path =
          '${root}c/Windows/System32/WindowsPowerShell/v1.0/'
          'powershell.exe';
      ranIn.clear();
      await open(
        _url,
        probes: _machine(
          files: {..._wsl, '/etc/wsl.conf': config},
          executables: {path},
        ),
      );
      expect(ranIn.single.$1, path, reason: config);
    }
  });

  test('every single quote PowerShell reads as one is doubled', () async {
    await open("https://x.test/it's\u2018\u2019\u201A\u201B");
    expect(
      _decoded(ranIn.single.$2),
      "\$ProgressPreference = 'SilentlyContinue'; "
      "Start 'https://x.test/it''s\u2018\u2018\u2019\u2019\u201A\u201A\u201B\u201B'",
    );
  });

  test(
    'a path goes through wslpath -aw, kept as it is if that fails',
    () async {
      await open(
        '/home/me/a b.html',
        answer: (_, _) =>
            (exitCode: 0, stdout: utf8.encode('C:\\x\\a b.html\n'), stderr: ''),
      );
      expect(ran, [
        ['wslpath', '-aw', '/home/me/a b.html'],
      ]);
      expect(_decoded(ranIn.single.$2), endsWith("Start 'C:\\x\\a b.html'"));
      ran.clear();
      ranIn.clear();
      await open(
        '-odd',
        answer: (_, _) => (exitCode: 1, stdout: <int>[], stderr: 'no'),
      );
      expect(ran, [
        ['wslpath', '-aw', '--', '-odd'],
      ]);
      expect(_decoded(ranIn.single.$2), endsWith("Start '-odd'"));
    },
  );

  test('PowerShell is waited for but its exit code is not read; one '
      'that cannot start says why', () async {
    expect(
      await open(_url, result: (exitCode: 1, stdout: <int>[], stderr: 'no\n')),
      isNull,
    );
    expect(
      await open(_url, result: (exitCode: 2, stdout: <int>[], stderr: '')),
      isNull,
    );
    expect(ranIn, hasLength(2));
    expect(
      await openSystemUrl(
        _url,
        operatingSystem: 'linux',
        environment: const {},
        probes: _machine(files: _wsl),
        runIn: (_, _, _) => throw const ProcessException('p', [], 'gone'),
      ),
      'gone',
    );
  });
}

void _isolation() {
  test('under WSL a supplied runner alone runs PowerShell too: nothing '
      'real is started without a runner in a folder given', () async {
    final ran = <List<String>>[];
    final said = await openSystemUrl(
      _url,
      operatingSystem: 'linux',
      environment: const {},
      probes: _machine(files: _wsl),
      run: (exe, args) async {
        ran.add([exe, ...args]);
        return _ok;
      },
    );
    expect(said, isNull);
    expect(ran.single.first, _ps);
    expect(
      _decoded(ran.single.sublist(1)),
      "\$ProgressPreference = 'SilentlyContinue'; Start '$_url'",
    );
  });

  test("a terminal given a runner runs WSL's PowerShell through it", () async {
    final ran = <String>[];
    final terminal = StdioTerminal(
      input: const Stream.empty(),
      environment: const {},
      openUrlProbes: _machine(files: _wsl),
      clipboardRunner: (exe, args) async {
        ran.add(exe);
        return _ok;
      },
    );
    if (Platform.operatingSystem != 'linux') {
      // The probes are read on Linux alone.
      expect(await terminal.openUrl(_url), isNull);
      return;
    }
    expect(await terminal.openUrl(_url), isNull);
    expect(ran, [_ps]);
  });
}
