import 'dart:convert';
import 'dart:io';

import 'clipboard_image.dart' show ClipboardCommandRunner, runClipboardCommand;

/// Runs [executable] with [arguments] in [workingDirectory]: how
/// [openSystemUrl] starts Windows' PowerShell from WSL, in its own folder.
typedef OpenUrlRunnerIn =
    Future<({int exitCode, List<int> stdout, String stderr})> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

/// Runs a process in [workingDirectory], for [openSystemUrl].
Future<({int exitCode, List<int> stdout, String stderr})> runOpenUrlCommandIn(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as List<int>,
    stderr: result.stderr as String,
  );
}

/// What [openSystemUrl] reads of the machine to tell WSL apart, each
/// replaceable in a test: a file's text, or null when it cannot be read;
/// whether a path exists; whether a file may be executed.
typedef OpenUrlProbes = ({
  String? Function(String path) read,
  bool Function(String path) exists,
  bool Function(String path) executable,
});

/// The machine's own files, read as [openSystemUrl] reads them.
final OpenUrlProbes systemOpenUrlProbes = (
  read: (path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  },
  exists: (path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound,
  executable: (path) {
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
  },
);

/// Opens [url] in the system's browser through the platform's own opener,
/// as the `open` package does: `open` on macOS, PowerShell's `Start` on
/// Windows, and from WSL where Windows' PowerShell can be reached,
/// `xdg-open` elsewhere. [operatingSystem] defaults to the process's; [run]
/// runs the opener and [runIn] PowerShell in its own folder under WSL;
/// [environment] tells WSL apart, with [probes], and names Windows' own
/// folder, as `SYSTEMROOT` or `windir`. A [run] given without [runIn] runs
/// PowerShell too, in no folder of its own, so a caller that replaces the
/// system's runner never has a real process started.
///
/// As `open` does when it does not wait for the app, PowerShell is waited
/// for until it ends, since it is killed with a parent that leaves first,
/// and `open` and `xdg-open` are started detached and not waited for; no
/// opener's exit code is read. Returns why the opener could not be
/// started, or null when it was.
Future<String?> openSystemUrl(
  String url, {
  ClipboardCommandRunner? run,
  OpenUrlRunnerIn? runIn,
  String? operatingSystem,
  Map<String, String>? environment,
  OpenUrlProbes? probes,
}) async {
  final system = operatingSystem ?? Platform.operatingSystem;
  final runner = run ?? runClipboardCommand;
  final start = run ?? _startDetached;
  final runnerIn =
      runIn ??
      (run == null
          ? runOpenUrlCommandIn
          : (executable, arguments, _) => run(executable, arguments));
  try {
    final env = environment ?? Platform.environment;
    if (system == 'windows') {
      await runner(
        _windowsPowerShell(env),
        await _powerShellArguments(url, null),
      );
      return null;
    }
    final powerShell = system == 'linux'
        ? _wslPowerShell(env, probes ?? systemOpenUrlProbes)
        : null;
    if (powerShell != null) {
      // Started from its own folder: the Linux one may be a UNC path
      // Windows' user cannot traverse.
      await runnerIn(
        powerShell,
        await _powerShellArguments(url, runner),
        powerShell.substring(0, powerShell.lastIndexOf('/')),
      );
      return null;
    }
    final (executable, arguments) = switch (system) {
      'macos' => ('open', [url]),
      _ => ('xdg-open', [url]),
    };
    await start(executable, arguments);
    return null;
  } on ProcessException catch (error) {
    return error.message;
  }
}

/// Starts [executable] on its own, its output nowhere, as `open` starts
/// `open` and `xdg-open`: what it does after starting is not waited for.
Future<({int exitCode, List<int> stdout, String stderr})> _startDetached(
  String executable,
  List<String> arguments,
) async {
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  return (exitCode: 0, stdout: const <int>[], stderr: '');
}

/// Windows' PowerShell as `powershell-utils` names it on Windows: under
/// `SYSTEMROOT`, else `windir`, else `C:\Windows`.
String _windowsPowerShell(Map<String, String> environment) {
  String? set(String name) {
    final value = environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  final root = set('SYSTEMROOT') ?? set('windir') ?? r'C:\Windows';
  return '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
}

/// Windows' PowerShell as the `open` package reaches it from WSL: WSL as
/// `is-wsl` tells it, outside a container and an SSH session, with
/// PowerShell executable under the drives' mount point; else null.
String? _wslPowerShell(Map<String, String> environment, OpenUrlProbes probes) {
  bool microsoft(String path) =>
      probes.read(path)?.toLowerCase().contains('microsoft') ?? false;
  final wsl =
      microsoft('/proc/sys/kernel/osrelease') ||
      microsoft('/proc/version') ||
      probes.exists('/proc/sys/fs/binfmt_misc/WSLInterop') ||
      probes.exists('/run/WSL');
  final container =
      probes.exists('/run/.containerenv') ||
      probes.exists('/.dockerenv') ||
      (probes.read('/proc/self/cgroup')?.contains('docker') ?? false);
  final ssh = [
    'SSH_CONNECTION',
    'SSH_CLIENT',
    'SSH_TTY',
  ].any((name) => (environment[name] ?? '').isNotEmpty);
  if (!wsl || container || ssh) return null;
  final path =
      '${_mountPoint(probes.read('/etc/wsl.conf'))}'
      'c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
  return probes.executable(path) ? path : null;
}

/// The Windows drives' mount point, as `wsl-utils` reads `/etc/wsl.conf`:
/// its first `root =`, unquoted, with a trailing slash; `/mnt/` without.
String _mountPoint(String? config) {
  for (final line in (config ?? '').split('\n')) {
    if (RegExp(r'^\s*#').hasMatch(line)) continue;
    final match = RegExp(
      r'''^\s*root\s*=\s*("[^"]*"|'[^']*'|[^#]*)''',
    ).firstMatch(line);
    if (match == null) continue;
    final root = match[1]!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    return root.endsWith('/') ? root : '$root/';
  }
  return '/mnt/';
}

/// `Start` of [target] as the `open` package asks PowerShell for it,
/// encoded in UTF-16LE base64: under WSL, where [run] is given, a path
/// through `wslpath -aw` first; a URL, or anything on Windows, as it is.
Future<List<String>> _powerShellArguments(
  String target,
  ClipboardCommandRunner? run,
) async {
  final windows =
      run == null ||
          RegExp(r'^[a-z]+://', caseSensitive: false).hasMatch(target)
      ? target
      : await _windowsPath(target, run);
  // PowerShell reads the typographic single quotes as quotes too.
  final escaped = windows.replaceAllMapped(
    RegExp("['‘’‚‛]"),
    (m) => '${m[0]}${m[0]}',
  );
  final command = "\$ProgressPreference = 'SilentlyContinue'; Start '$escaped'";
  return [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
    base64.encode([
      for (final unit in command.codeUnits) ...[unit & 0xff, unit >> 8],
    ]),
  ];
}

/// [path] as Windows names it, by `wslpath -aw`; as it is if that fails.
Future<String> _windowsPath(String path, ClipboardCommandRunner run) async {
  try {
    final result = await run('wslpath', [
      '-aw',
      if (path.startsWith('-')) '--',
      path,
    ]);
    if (result.exitCode != 0) return path;
    final said = utf8
        .decode(result.stdout, allowMalformed: true)
        .replaceFirst(RegExp(r'\r?\n$'), '');
    return said.isEmpty ? path : said;
  } on ProcessException {
    return path;
  }
}
