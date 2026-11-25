import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Runs [executable] with [arguments] and gives its exit code, its stdout as
/// bytes and its stderr as text; throws [ProcessException] when there is no
/// such program.
typedef ClipboardCommandRunner =
    Future<({int exitCode, List<int> stdout, String stderr})> Function(
      String executable,
      List<String> arguments,
    );

/// What reading the system clipboard's image came to.
sealed class ClipboardImage {
  const ClipboardImage();
}

/// The clipboard's image, as the platform's tool gave it: PNG where the
/// tool converts, else the type the clipboard held.
final class ClipboardImageRead extends ClipboardImage {
  /// The image's [bytes].
  const ClipboardImageRead(this.bytes);

  /// The image, as the tool wrote it.
  final Uint8List bytes;
}

/// The clipboard holds no image.
final class ClipboardImageNone extends ClipboardImage {
  /// No image to read.
  const ClipboardImageNone();
}

/// The clipboard cannot be read here: no tool that reads it was found.
final class ClipboardImageUnavailable extends ClipboardImage {
  /// Unavailable, for [reason].
  const ClipboardImageUnavailable(this.reason);

  /// Which tools were looked for.
  final String reason;
}

/// A tool was found, but reading through it failed.
final class ClipboardImageFailed extends ClipboardImage {
  /// Failed, saying [reason].
  const ClipboardImageFailed(this.reason);

  /// What the tool said.
  final String reason;
}

/// Reads the system clipboard's image through the platform's own tools:
/// osascript on macOS, wl-paste then xclip elsewhere on Unix, PowerShell on
/// Windows. [operatingSystem] and [environment] default to the process's;
/// [run] runs each tool.
Future<ClipboardImage> readSystemClipboardImage({
  ClipboardCommandRunner run = runClipboardCommand,
  String? operatingSystem,
  Map<String, String>? environment,
}) async {
  final system = operatingSystem ?? Platform.operatingSystem;
  final env = environment ?? Platform.environment;
  try {
    return switch (system) {
      'macos' => await _macos(run),
      'windows' => await _windows(run),
      _ => await _unix(run, env),
    };
  } on ProcessException catch (error) {
    return ClipboardImageFailed(error.message);
  }
}

/// [Process.run] with stdout kept as bytes.
Future<({int exitCode, List<int> stdout, String stderr})> runClipboardCommand(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(
    executable,
    arguments,
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as List<int>,
    stderr: result.stderr as String,
  );
}

/// Whether [run] finds [executable]; a missing program is no failure.
Future<({int exitCode, List<int> stdout, String stderr})?> _found(
  ClipboardCommandRunner run,
  String executable,
  List<String> arguments,
) async {
  try {
    return await run(executable, arguments);
  } on ProcessException catch (error) {
    // errno 2: no such program on PATH.
    if (error.errorCode == 2 || error.message.contains('No such file')) {
      return null;
    }
    rethrow;
  }
}

final _pngData = RegExp(r'«data PNGf([0-9A-Fa-f]*)»');

Future<ClipboardImage> _macos(ClipboardCommandRunner run) async {
  // AppleScript converts whatever image the clipboard holds to PNG and
  // prints it as «data PNGf…» in hex.
  final result = await _found(run, 'osascript', [
    '-e',
    'the clipboard as «class PNGf»',
  ]);
  if (result == null) {
    return const ClipboardImageUnavailable('osascript was not found');
  }
  if (result.exitCode != 0) {
    // -1700: the clipboard's contents cannot be made an image.
    return result.stderr.contains('-1700')
        ? const ClipboardImageNone()
        : ClipboardImageFailed(result.stderr.trim());
  }
  final hex = _pngData.firstMatch(
    utf8.decode(result.stdout, allowMalformed: true),
  );
  if (hex == null) return const ClipboardImageNone();
  final digits = hex.group(1)!;
  final bytes = Uint8List(digits.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(digits.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return bytes.isEmpty ? const ClipboardImageNone() : ClipboardImageRead(bytes);
}

/// The type to ask for of [types], one per line: PNG first, else the first
/// image type there is.
String? _imageType(List<int> listed) {
  final types = const LineSplitter()
      .convert(utf8.decode(listed, allowMalformed: true))
      .map((line) => line.trim())
      .toList();
  if (types.contains('image/png')) return 'image/png';
  return types.where((type) => type.startsWith('image/')).firstOrNull;
}

Future<ClipboardImage> _unix(
  ClipboardCommandRunner run,
  Map<String, String> env,
) async {
  final tools = <(String, List<String>, List<String> Function(String))>[
    if ((env['WAYLAND_DISPLAY'] ?? '').isNotEmpty)
      ('wl-paste', ['--list-types'], (type) => ['--type', type]),
    if ((env['DISPLAY'] ?? '').isNotEmpty)
      (
        'xclip',
        ['-selection', 'clipboard', '-t', 'TARGETS', '-o'],
        (type) => ['-selection', 'clipboard', '-t', type, '-o'],
      ),
  ];
  for (final (tool, list, read) in tools) {
    final listed = await _found(run, tool, list);
    if (listed == null) continue;
    // An empty clipboard is a failure to both tools.
    final type = listed.exitCode == 0 ? _imageType(listed.stdout) : null;
    if (type == null) return const ClipboardImageNone();
    final image = await run(tool, read(type));
    if (image.exitCode != 0) return ClipboardImageFailed(image.stderr.trim());
    return image.stdout.isEmpty
        ? const ClipboardImageNone()
        : ClipboardImageRead(Uint8List.fromList(image.stdout));
  }
  return ClipboardImageUnavailable(
    tools.isEmpty
        ? 'no Wayland or X display'
        : 'found neither ${tools.map((tool) => tool.$1).join(' nor ')}',
  );
}

/// Writes the clipboard's image as PNG to stdout, or exits 2 with none.
const _powershell =
    r'Add-Type -AssemblyName System.Drawing; '
    r'$image = Get-Clipboard -Format Image; '
    r'if ($null -eq $image) { exit 2 }; '
    r'$stream = New-Object System.IO.MemoryStream; '
    r'$image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); '
    r'$out = [Console]::OpenStandardOutput(); '
    r'$out.Write($stream.ToArray(), 0, $stream.Length); $out.Flush()';

Future<ClipboardImage> _windows(ClipboardCommandRunner run) async {
  final result = await _found(run, 'powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    _powershell,
  ]);
  if (result == null) {
    return const ClipboardImageUnavailable('powershell was not found');
  }
  if (result.exitCode == 2) return const ClipboardImageNone();
  if (result.exitCode != 0) return ClipboardImageFailed(result.stderr.trim());
  return result.stdout.isEmpty
      ? const ClipboardImageNone()
      : ClipboardImageRead(Uint8List.fromList(result.stdout));
}
