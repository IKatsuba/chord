/// The official provider executables a limits reader runs: found on `PATH`,
/// a native binary (Codex's npm launcher with an existing Node), and saying
/// its version as the provider's own does. Compatibility does not establish
/// publisher or authentication identity. From the original's
/// `platform/resource_executable.ts`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:process_run/which.dart';

import 'resource_process.dart';
import 'resources.dart'
    show ExecutableFound, ExecutableUnavailable, ResourceExecutable;

final _versionOutput = {
  'codex': RegExp(r'^codex-cli (\S+)$'),
  'claude': RegExp(r'^(\S+) \(Claude Code\)$'),
};

/// What resolution reads of the machine, given so tests use fakes.
abstract interface class ExecutableInspection {
  /// The platform, as Node names it: `darwin`, `linux`.
  String get platform;

  /// The architecture, as Node names it: `arm64`, `x64`.
  String get arch;

  /// [name]'s real path on `PATH`, or null when it is not there.
  Future<String?> lookup(String name);

  /// Whether the file at [path] is a native executable.
  Future<bool> native(String path);

  /// What the executable at [path] says to `--version`, run in [cwd].
  Future<String> version(String path, String cwd, CancellationToken cancelled);
}

/// Whether [head], a file's first bytes, is a Mach-O or ELF binary, as
/// `file-type` 22.3.0 reads them: ELF's magic, a thin Mach-O's in either
/// byte order and width, or a universal Mach-O, whose magic Java class files
/// share, told apart by its architecture count of 1 to 30.
bool isNativeExecutable(List<int> head) {
  bool starts(List<int> magic) =>
      head.length >= magic.length &&
      [
        for (var i = 0; i < magic.length; i++) head[i] == magic[i],
      ].every((same) => same);
  if (starts(const [0x7F, 0x45, 0x4C, 0x46])) return true;
  if (starts(const [0xFE, 0xED, 0xFA, 0xCE]) ||
      starts(const [0xFE, 0xED, 0xFA, 0xCF]) ||
      starts(const [0xCE, 0xFA, 0xED, 0xFE]) ||
      starts(const [0xCF, 0xFA, 0xED, 0xFE])) {
    return true;
  }
  if (starts(const [0xCA, 0xFE, 0xBA, 0xBE]) && head.length >= 8) {
    final count = head[4] << 24 | head[5] << 16 | head[6] << 8 | head[7];
    return count > 0 && count <= 30;
  }
  return false;
}

Future<bool> _native(String path) async {
  final file = await File(path).open();
  try {
    return isNativeExecutable(await file.read(4100));
  } finally {
    await file.close();
  }
}

/// What [path] says to `--version` in [cwd]: its trimmed output, or empty
/// when it fails, says more than 4096 bytes, or takes more than 3 s.
Future<String> readVersion(
  String path,
  String cwd,
  CancellationToken cancelled,
) => withResourceProcess(
  [path, '--version'],
  cwd: cwd,
  cancelled: cancelled,
  read: (group, within, _) async {
    final output = <int>[];
    var bytes = 0;
    final done = Completer<void>();
    group.stdout.listen(
      (chunk) {
        bytes += chunk.length;
        if (bytes <= 4096) output.addAll(chunk);
      },
      onDone: done.complete,
      onError: (_) {},
      cancelOnError: false,
    );
    final (exit, _) = await resourceStep(
      (group.exit, done.future).wait,
      within,
      const Duration(seconds: 3),
    );
    if (exit.code != 0 || bytes > 4096) return '';
    return utf8.decode(output, allowMalformed: true).trim();
  },
);

String _nodeArch() => switch (Abi.current()) {
  Abi.macosArm64 || Abi.linuxArm64 => 'arm64',
  Abi.macosX64 || Abi.linuxX64 => 'x64',
  final abi => '$abi',
};

final class _Machine implements ExecutableInspection {
  const _Machine();

  @override
  String get platform => switch (Platform.operatingSystem) {
    'macos' => 'darwin',
    final os => os,
  };

  @override
  String get arch => _nodeArch();

  @override
  Future<String?> lookup(String name) async {
    final path = await which(name);
    return path == null ? null : File(path).resolveSymbolicLinks();
  }

  @override
  Future<bool> native(String path) => _native(path);

  @override
  Future<String> version(
    String path,
    String cwd,
    CancellationToken cancelled,
  ) => readVersion(path, cwd, cancelled);
}

/// The machine's own inspection.
const ExecutableInspection machineInspection = _Machine();

/// [provider]'s official executable to read limits with: found on `PATH`,
/// verified native (Codex's npm launcher with Node on `PATH`), its version
/// read; or why not, in the original's words. A [customCommand] is never
/// read for, as nothing ties it to the provider's own authentication.
Future<ResourceExecutable> resolveResourceExecutable(
  String provider, {
  required String cwd,
  required CancellationToken cancelled,
  required bool customCommand,
  ExecutableInspection inspect = machineInspection,
}) async {
  if (customCommand) {
    return const ExecutableUnavailable(
      'Custom ACP command has no verified association with the official '
      'native provider authentication.',
    );
  }
  if (inspect.platform != 'darwin' || inspect.arch != 'arm64') {
    return const ExecutableUnavailable(
      'Resource collector compatibility is not verified on this platform.',
    );
  }
  try {
    final path = await inspect.lookup(provider);
    if (path == null) {
      return const ExecutableUnavailable(
        'Official native provider executable is missing from PATH.',
      );
    }
    if (!await inspect.native(path)) {
      if (provider != 'codex') {
        return const ExecutableUnavailable(
          'The Claude collector requires the official native executable.',
        );
      }
      if (await inspect.lookup('node') == null) {
        return const ExecutableUnavailable(
          'The official npm Codex launcher requires an existing Node '
          'installation.',
        );
      }
    }
    final version = _versionOutput[provider]!
        .firstMatch(await inspect.version(path, cwd, cancelled))
        ?.group(1);
    if (version == null) {
      return const ExecutableUnavailable(
        'Native provider version could not be read.',
      );
    }
    return ExecutableFound(path, version);
  } on Object catch (error) {
    if (cancelled.isCancelled ||
        (error is ResourceReadError && error.kind == 'cleanup')) {
      rethrow;
    }
    return const ExecutableUnavailable(
      'Official provider executable could not be verified.',
    );
  }
}
