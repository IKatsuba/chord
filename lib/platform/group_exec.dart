/// The launcher an agent is started through, so it leads a process group of
/// its own: chord runs itself with [groupExecFlag], and that copy calls
/// `setsid` and `execv`s the agent in place, keeping the pid `Process.start`
/// returned along with its pipes and exit code.
///
/// ```text
/// --chord-group-exec <nonce> <path> -- <argv0> <args…>
/// ```
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// The first argument that turns chord into the launcher.
const groupExecFlag = '--chord-group-exec';

const _sigpipe = 13;
const _enoent = 2;

/// The JIT path's entry: `dart` runs this file directly as the launcher.
void main(List<String> args) => groupExec(args);

/// Becomes the program `args` name, leading a session and group of its own,
/// or exits 126 (127 when the program is missing), saying why on fd 2.
///
/// Before `execv` it writes the frame `chord-exec <nonce> ok` on fd 2, so the
/// parent knows the group exists; a failure writes
/// `chord-exec <nonce> fail setsid|exec <errno>` instead.
Never groupExec(List<String> args) {
  final call = _LauncherCall.parse(args);
  if (call == null) {
    _write('chord: malformed $groupExecFlag call\n');
    _exit(126);
  }
  final frame = 'chord-exec ${call.nonce}';

  // Dart's children inherit SIGPIPE ignored, and an ignored signal stays
  // ignored across exec; node's children, the original's agents, get it as
  // the default.
  _signal(_sigpipe, nullptr);

  if (_setsid() == -1) {
    _write('$frame fail setsid ${_errno()}\n');
    _exit(126);
  }
  // Through libc: Dart's stderr writes asynchronously, and exec would drop
  // what is still buffered.
  _write('$frame ok\n');

  final path = _cString(call.path);
  final argv = _malloc(
    sizeOf<Pointer>() * (call.argv.length + 1),
  ).cast<Pointer<Uint8>>();
  for (final (index, word) in call.argv.indexed) {
    argv[index] = _cString(word);
  }
  argv[call.argv.length] = nullptr;
  _execv(path, argv);

  final errno = _errno();
  _write('$frame fail exec $errno\n');
  _exit(errno == _enoent ? 127 : 126);
}

/// A launcher call whose shape was checked: a hex nonce, an absolute path,
/// `--`, and at least the program's `argv0`.
class _LauncherCall {
  _LauncherCall(this.nonce, this.path, this.argv);

  final String nonce;
  final String path;
  final List<String> argv;

  static final _hex = RegExp(r'^[0-9a-f]+$');

  static _LauncherCall? parse(List<String> args) {
    if (args.length < 5 ||
        args[0] != groupExecFlag ||
        !_hex.hasMatch(args[1]) ||
        !args[2].startsWith('/') ||
        args[3] != '--') {
      return null;
    }
    return _LauncherCall(args[1], args[2], args.sublist(4));
  }
}

final _libc = DynamicLibrary.process();

final _signal = _libc
    .lookupFunction<
      Pointer<Void> Function(Int32, Pointer<Void>),
      Pointer<Void> Function(int, Pointer<Void>)
    >('signal');

final _setsid = _libc.lookupFunction<Int32 Function(), int Function()>(
  'setsid',
);

final _writeFd = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, Size),
      int Function(int, Pointer<Uint8>, int)
    >('write');

final _execv = _libc
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>)
    >('execv');

final _exitNow = _libc.lookupFunction<Void Function(Int32), void Function(int)>(
  '_exit',
);

final _malloc = _libc
    .lookupFunction<Pointer<Void> Function(Size), Pointer<Void> Function(int)>(
      'malloc',
    );

final _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );

int _errno() => _errnoLocation().value;

Never _exit(int code) {
  _exitNow(code);
  throw StateError('_exit returned');
}

/// `text` on fd 2, whole, past any of Dart's buffering. Nothing is freed:
/// the process is replaced or exits right after.
void _write(String text) {
  final bytes = utf8.encode(text);
  final buffer = _malloc(bytes.length).cast<Uint8>();
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  var done = 0;
  while (done < bytes.length) {
    final wrote = _writeFd(2, buffer + done, bytes.length - done);
    if (wrote <= 0) return;
    done += wrote;
  }
}

Pointer<Uint8> _cString(String text) {
  final bytes = utf8.encode(text);
  final buffer = _malloc(bytes.length + 1).cast<Uint8>();
  buffer.asTypedList(bytes.length + 1)
    ..setAll(0, bytes)
    ..[bytes.length] = 0;
  return buffer;
}
