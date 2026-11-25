/// Processes as chord starts and stops them: a child leading a process group
/// of its own, so a signal reaches whatever it started too.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';

import 'group_exec.dart';

/// How a process ended.
class Exit {
  /// An exit by [code], or by [signal], whose code is then 128 and the
  /// signal's number, as a shell's `$?` reads it.
  const Exit(this.code, [this.signal]);

  /// Dart's exit code, where `-n` means signal `n`.
  factory Exit.fromExitCode(int exitCode) => exitCode >= 0
      ? Exit(exitCode)
      : Exit(128 - exitCode, _signalNames[-exitCode] ?? 'SIG${-exitCode}');

  final int code;

  /// The signal's name, as `SIGTERM`; null for a plain exit.
  final String? signal;

  @override
  bool operator ==(Object other) =>
      other is Exit && other.code == code && other.signal == signal;

  @override
  int get hashCode => Object.hash(code, signal);

  @override
  String toString() => signal == null ? 'Exit($code)' : 'Exit($code, $signal)';
}

// The numbers POSIX systems share; others are named by number.
const _signalNames = {
  1: 'SIGHUP',
  2: 'SIGINT',
  3: 'SIGQUIT',
  4: 'SIGILL',
  6: 'SIGABRT',
  8: 'SIGFPE',
  9: 'SIGKILL',
  11: 'SIGSEGV',
  13: 'SIGPIPE',
  14: 'SIGALRM',
  15: 'SIGTERM',
};

/// Why a program did not start: `cannot start <program>: <reason>`.
class CannotStart implements Exception {
  /// [program] as it was written, and why it did not start.
  const CannotStart(this.program, this.reason, {this.code});

  final String program;
  final String reason;

  /// The launcher's exit code when its `execv` failed: 127 for a program
  /// not found, else 126.
  final int? code;

  @override
  String toString() => 'cannot start $program: $reason';
}

/// The argv that runs the launcher for [path], up to and including `--`;
/// the agent's own argv follows it. Tests wrap the real one.
typedef Launcher = List<String> Function(String nonce, String path);

/// chord's binary itself when compiled, else `dart` running
/// `group_exec.dart`, both with absolute paths so the current directory does
/// not matter.
List<String> defaultLauncher(String nonce, String path) => [
  Platform.resolvedExecutable,
  if (!const bool.fromEnvironment('dart.vm.product')) ...[
    '--packages=${Isolate.packageConfigSync!.toFilePath()}',
    Isolate.resolvePackageUriSync(
      Uri.parse('package:chord/platform/group_exec.dart'),
    )!.toFilePath(),
  ],
  groupExecFlag,
  nonce,
  path,
  '--',
];

/// `kill(2)`: 0, or the errno it failed with.
typedef Kill = int Function(int pid, int signal);

const _eperm = 1;

/// A child leading a process group of its own, started through the launcher.
class GroupProcess {
  /// A group over [_process]; tests give their own [kill].
  GroupProcess._(this._process, this.program, String nonce, this._kill)
    : _handshake = GroupHandshake(nonce) {
    // A pipe the child closed fails a write; unheard, that error would end
    // chord. The exit is what tells of it.
    _process.stdin.done.catchError((_) {});
    _process.stderr.listen(
      _hear,
      onError: (_) {},
      onDone: _stderrEnded,
      cancelOnError: false,
    );
    _process.exitCode.then(_exited);
    started.ignore();
    exit.ignore();
  }

  final Process _process;
  final GroupHandshake _handshake;
  final Kill _kill;

  /// The program as it was written.
  final String program;

  final _started = Completer<void>();
  final _exit = Completer<Exit>();
  final _stderr = StreamController<List<int>>();
  final _stderrDone = Completer<void>();
  bool _exitSeen = false;

  /// The process id, which is also its group's.
  int get pid => _process.pid;

  /// What chord writes to it.
  IOSink get stdin => _process.stdin;

  /// What it writes.
  Stream<List<int>> get stdout => _process.stdout;

  /// What it writes to stderr, the launcher's frames taken out.
  Stream<List<int>> get stderr => _stderr.stream;

  /// Settles once its group exists; rejects with [CannotStart] when it never
  /// will.
  Future<void> get started => _started.future;

  /// Settles once it exits; rejects as [started] does, or with [CannotStart]
  /// when the program could not be executed after the group existed.
  Future<Exit> get exit => _exit.future;

  void _hear(List<int> chunk) {
    final through = _handshake.add(chunk);
    _settleStart();
    if (through.isNotEmpty) _stderr.add(through);
  }

  void _stderrEnded() {
    final through = _handshake.close();
    _settleStart();
    if (through.isNotEmpty) _stderr.add(through);
    _stderr.close();
    _stderrDone.complete();
  }

  void _settleStart() {
    if (_started.isCompleted) return;
    switch (_handshake.state) {
      case HandshakeState.started:
        _started.complete();
      case HandshakeState.failed:
        _started.completeError(CannotStart(program, _handshake.failure!));
      case HandshakeState.waiting:
        break;
    }
  }

  Future<void> _exited(int code) async {
    _exitSeen = true;
    // Its frames and its exit come on different pipes in no fixed order,
    // and load can hold the frame back well after the exit is heard.
    // Before `ok` the launcher has started nothing that could hold its
    // stderr, so that ends; after it, the frame is in the pipe: either
    // settles the start, however late, and is waited for.
    if (_handshake.state == HandshakeState.waiting) {
      await Future.any([
        _stderrDone.future,
        _started.future.then((_) {}, onError: (Object _) {}),
      ]);
    }
    // A `fail exec` frame is waited for briefly: past `ok` what the
    // program started may hold stderr open, saying nothing, for ever.
    if (!_handshake.settled) {
      await _stderrDone.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }
    if (!_started.isCompleted) {
      _started.completeError(
        CannotStart(program, 'it ended before it started'),
      );
    }
    final execErrno = _handshake.execErrno;
    if (execErrno != null) {
      _exit.completeError(
        CannotStart(program, strerror(execErrno), code: code),
      );
    } else if (_handshake.state != HandshakeState.started) {
      _exit.completeError(
        CannotStart(
          program,
          _handshake.failure ?? 'it ended before it started',
        ),
      );
    } else {
      _exit.complete(Exit.fromExitCode(code));
    }
  }

  /// Sends [signal] to its group, or to the process alone while no group
  /// with its id exists yet (a stop before the launcher's `setsid`); whether
  /// anything took it.
  bool signal(ProcessSignal signal) =>
      signalGroup(_kill, pid, signal.signalNumber, exited: _exitSeen);

  /// Whether anything is left in its group; a process that died and waits
  /// to be reaped counts.
  bool alive() {
    final errno = _kill(-pid, 0);
    // macOS refuses even signal 0 to a group left with only unreaped
    // processes, where an empty one is ESRCH.
    return errno == 0 || errno == _eperm;
  }
}

/// Sends [signal] to group [pid] through [kill], or, when that fails while
/// the process has not [exited], to [pid] alone: before the launcher's
/// `setsid` no group with that id exists. Whether anything took it.
bool signalGroup(Kill kill, int pid, int signal, {required bool exited}) {
  if (kill(-pid, signal) == 0) return true;
  // Not on ESRCH alone: errno is read by a second FFI call, and between the
  // two the VM may make syscalls of its own, so the errno seen need not be
  // kill's (CTUI-192). Only while it runs: once it is reaped its pid may be
  // someone else's.
  return !exited && kill(pid, signal) == 0;
}

/// Where the launcher's handshake stands.
enum HandshakeState {
  /// No frame yet.
  waiting,

  /// `chord-exec <nonce> ok`: the group exists.
  started,

  /// A fail frame, or something else first, or stderr's end before `ok`.
  failed,
}

/// Reads the launcher's frames off the front of a child's stderr and passes
/// everything else through: `chord-exec <nonce> ok` or
/// `chord-exec <nonce> fail setsid <errno>` as the first line, and
/// `chord-exec <nonce> fail exec <errno>` right after `ok`.
class GroupHandshake {
  /// A handshake expecting frames that carry [nonce].
  GroupHandshake(String nonce)
    : _ok = ascii.encode('chord-exec $nonce ok\n'),
      _failSetsid = ascii.encode('chord-exec $nonce fail setsid '),
      _failExec = ascii.encode('chord-exec $nonce fail exec ');

  final List<int> _ok;
  final List<int> _failSetsid;
  final List<int> _failExec;

  final _held = <int>[];
  bool _execWindow = false;

  /// Where it stands.
  HandshakeState state = HandshakeState.waiting;

  /// Why it failed, as `setsid: <reason>`, once [state] is failed.
  String? failure;

  /// The errno of a failed `execv` after `ok`.
  int? execErrno;

  /// Whether nothing more of it can change: past `ok` and the place a
  /// `fail exec` frame would be, or failed.
  bool get settled =>
      state == HandshakeState.failed ||
      (state == HandshakeState.started && !_execWindow);

  /// Takes [chunk] of stderr; returns what of it is the program's own.
  List<int> add(List<int> chunk) {
    if (settled) return chunk;
    _held.addAll(chunk);
    return _read(ended: false);
  }

  /// stderr ended; returns what was held of the program's own.
  List<int> close() {
    if (settled) return const [];
    return _read(ended: true);
  }

  List<int> _read({required bool ended}) {
    if (state == HandshakeState.waiting) {
      if (_startsWith(_held, _ok)) {
        state = HandshakeState.started;
        _execWindow = true;
        _held.removeRange(0, _ok.length);
      } else if (_frame(_failSetsid) case final errno?) {
        state = HandshakeState.failed;
        failure = 'setsid: ${strerror(errno)}';
        return _rest();
      } else if (ended || !_couldBe(_ok) && !_couldBe(_failSetsid)) {
        state = HandshakeState.failed;
        failure = 'it ended before it started';
        return _rest();
      } else {
        return const [];
      }
    }
    if (_frame(_failExec) case final errno?) {
      execErrno = errno;
      _execWindow = false;
      return _rest();
    }
    if (ended || !_couldBe(_failExec) || _held.contains(0x0A)) {
      _execWindow = false;
      return _rest();
    }
    return const [];
  }

  List<int> _rest() {
    final rest = List<int>.of(_held);
    _held.clear();
    return rest;
  }

  /// The errno of the whole frame line `prefix<errno>\n` at the front, which
  /// is then dropped.
  int? _frame(List<int> prefix) {
    if (!_startsWith(_held, prefix)) return null;
    final end = _held.indexOf(0x0A, prefix.length);
    if (end < 0) return null;
    // Only digits: anything else on the line is the program's own stderr.
    final digits = _held.sublist(prefix.length, end);
    if (digits.isEmpty || digits.any((b) => b < 0x30 || b > 0x39)) return null;
    final errno = int.tryParse(String.fromCharCodes(digits));
    if (errno == null) return null;
    _held.removeRange(0, end + 1);
    return errno;
  }

  /// Whether what is held could still turn into [frame].
  bool _couldBe(List<int> frame) {
    final n = min(_held.length, frame.length);
    for (var i = 0; i < n; i++) {
      if (_held[i] != frame[i]) return false;
    }
    if (_held.length <= frame.length) return true;
    // Past the prefix: an errno's digits, then the newline.
    for (var i = frame.length; i < _held.length; i++) {
      final byte = _held[i];
      if (byte == 0x0A) return i > frame.length;
      if (byte < 0x30 || byte > 0x39) return false;
    }
    return true;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}

/// Every group chord spawned, from its spawn until nothing is left in it.
class ProcessGroups {
  /// An empty registry; tests make their own.
  ProcessGroups();

  /// The registry [spawnGroup] uses unless given another.
  static final instance = ProcessGroups();

  final _spawned = <GroupProcess>{};
  final _left = <GroupProcess>{};

  void _add(GroupProcess group) {
    _forgetEmpty();
    _spawned.add(group);
    group._process.exitCode.then((_) {
      _left.add(group);
      _forgetEmpty();
    });
  }

  void _forgetEmpty() {
    for (final group in [..._left]) {
      if (!group.alive()) {
        _left.remove(group);
        _spawned.remove(group);
      }
    }
  }

  /// SIGKILL to every group that still holds a process, without waiting:
  /// the last thing a way out does. Returns their pids.
  List<int> killAll() {
    _forgetEmpty();
    final pids = [for (final group in _spawned) group.pid];
    for (final group in _spawned) {
      group.signal(ProcessSignal.sigkill);
    }
    return pids;
  }
}

/// Starts [program] with [args] leading a process group of its own, through
/// the launcher. [program] is resolved first: against [cwd] when it holds a
/// `/`, else on `PATH` from chord's environment with [env] laid over it;
/// one missing or not executable throws [CannotStart] and nothing starts.
/// With [ownEnvironment], [env] is its whole environment, chord's left out.
Future<GroupProcess> spawnGroup(
  String program,
  List<String> args, {
  required String cwd,
  Map<String, String>? env,
  bool ownEnvironment = false,
  Launcher launcher = defaultLauncher,
  ProcessGroups? groups,
  Kill? kill,
}) async {
  final path = ownEnvironment
      ? resolveProgram(program, cwd: cwd, env: env, only: true)
      : resolveProgram(program, cwd: cwd, env: env);
  final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
  final command = [...launcher(nonce, path), program, ...args];
  final Process process;
  try {
    process = await Process.start(
      command.first,
      command.sublist(1),
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: !ownEnvironment,
    );
  } on ProcessException catch (error) {
    throw CannotStart(program, error.message);
  }
  final group = GroupProcess._(process, program, nonce, kill ?? _libcKill);
  (groups ?? ProcessGroups.instance)._add(group);
  return group;
}

/// [program]'s absolute path, as [spawnGroup] resolves it; with [only],
/// on [env]'s `PATH` alone.
String resolveProgram(
  String program, {
  required String cwd,
  Map<String, String>? env,
  bool only = false,
}) {
  final base = p.absolute(cwd);
  if (program.contains('/')) {
    final path = p.normalize(p.join(base, program));
    final stat = FileStat.statSync(path);
    if (stat.type == FileSystemEntityType.notFound) {
      throw CannotStart(program, strerror(2));
    }
    if (stat.type != FileSystemEntityType.file || stat.mode & 0x49 == 0) {
      throw CannotStart(program, strerror(13));
    }
    return path;
  }
  final environment = {if (!only) ...Platform.environment, ...?env};
  // process_run joins a relative entry with chord's own directory; the
  // original's spawn looks it up after the child's chdir, so against the
  // agent's, and an empty entry means that directory itself.
  final path = environment['PATH'];
  if (path != null) {
    environment['PATH'] = [
      for (final entry in path.split(':')) p.normalize(p.join(base, entry)),
    ].join(':');
  }
  final found = whichSync(
    program,
    environment: environment,
    includeParentEnvironment: false,
  );
  if (found == null) throw CannotStart(program, strerror(2));
  return found;
}

final _libc = DynamicLibrary.process();

final _killFn = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'kill',
    );

final _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );

final _strerror = _libc
    .lookupFunction<
      Pointer<Uint8> Function(Int32),
      Pointer<Uint8> Function(int)
    >('strerror');

// A failure is never 0, whatever errno reads by then.
int _libcKill(int pid, int signal) {
  if (_killFn(pid, signal) == 0) return 0;
  final errno = _errnoLocation().value;
  return errno == 0 ? -1 : errno;
}

/// libc's words for [errno], as `No such file or directory`.
String strerror(int errno) {
  final text = _strerror(errno);
  var length = 0;
  while (text[length] != 0) {
    length++;
  }
  return utf8.decode(text.asTypedList(length));
}
