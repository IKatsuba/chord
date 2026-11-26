import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../foundation/geometry.dart';
import 'clipboard_image.dart';
import 'open_url.dart';
import 'settle_input_stub.dart' if (dart.library.ffi) 'settle_input_ffi.dart';

/// Whether an app currently owns its terminal or has lent it to a child.
enum TerminalState {
  /// No app owns the terminal.
  inactive,

  /// The terminal is drawing and accepting input for an app.
  active,

  /// An app has released the terminal until its callback completes.
  suspended,
}

/// Launches an editor command with inherited stdio and returns its exit code.
typedef EditorLauncher =
    Future<int> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      required Map<String, String> environment,
      required ProcessStartMode mode,
    });

/// The terminal escape used for a desktop notification.
enum NotificationChannel {
  /// A terminal bell, with no text payload.
  bell,

  /// An OSC 9 desktop notification.
  osc9,

  /// An OSC 777 notification with a title and message.
  osc777,
}

/// The state a program reports through the Program Status Protocol.
enum ProgramState {
  /// Nothing is running and nothing is asked.
  idle,

  /// Work is under way.
  working,

  /// The work finished.
  done,

  /// The program waits on the person.
  blocked,

  /// The work failed.
  error,
}

/// What a [ProgramState.blocked] record waits on.
enum ProgramStatusKind {
  /// A permission to approve or refuse.
  permission,

  /// A question to answer.
  question,

  /// A sign-in to complete.
  auth,
}

/// One OSC 7501 record a program reports about itself, which replaces the
/// record at [id] whole: a field left out is gone from it afterwards.
final class ProgramStatus {
  /// A record in [state]; [kind] needs [ProgramState.blocked], [progress]
  /// (0 to 100) needs working or blocked. [id] is a path such as `build/test`
  /// of at most 8 segments, each 1 to 32 of `[A-Za-z0-9_.+-]`, and at most 128
  /// bytes; null addresses the root record. [app] is at most 32 such bytes.
  /// [title] (192 UTF-8 bytes) and [message] (2048) carry no control
  /// characters; empty ones are left out. A record outside these bounds is
  /// refused with an [ArgumentError] when it is written.
  const ProgramStatus(
    this.state, {
    this.id,
    this.app,
    this.title,
    this.message,
    this.kind,
    this.progress,
  });

  /// What the program is doing.
  final ProgramState state;

  /// The record's path, or null for the root record.
  final String? id;

  /// The program's stable identifier, such as `chord`.
  final String? app;

  /// A short label for the record.
  final String? title;

  /// One line saying what the record does, waits for, or finished.
  final String? message;

  /// What a blocked record waits on.
  final ProgramStatusKind? kind;

  /// How far the work is, 0 to 100.
  final int? progress;

  @override
  bool operator ==(Object other) =>
      other is ProgramStatus &&
      other.state == state &&
      other.id == id &&
      other.app == app &&
      other.title == title &&
      other.message == message &&
      other.kind == kind &&
      other.progress == progress;

  @override
  int get hashCode =>
      Object.hash(state, id, app, title, message, kind, progress);

  @override
  String toString() =>
      'ProgramStatus(${[state.name, if (id != null) 'id: $id', if (app != null) 'app: $app', if (title != null) 'title: $title', if (message != null) 'message: $message', if (kind != null) 'kind: ${kind!.name}', if (progress != null) 'progress: $progress'].join(', ')})';
}

/// What the framework needs from a terminal.
abstract class Terminal {
  /// For implementations.
  const Terminal();

  /// The window's size, in cells.
  Size get size;

  /// What the terminal sends: keys, pastes and replies, as text.
  Stream<String> get input;

  /// The window's new size each time it changes.
  Stream<Size> get resizes;

  /// Sends [data] to the terminal as it is.
  void write(String data);

  /// Takes the terminal over for the app's drawing and input.
  void enter();

  /// Gives the terminal back as it was before [enter].
  Future<void> leave();

  /// Synchronous ownership transitions; custom terminals may expose none.
  Stream<TerminalState> get states => const Stream.empty();

  /// Releases an active terminal around [action], restoring it in finally.
  Future<T> suspend<T>(Future<T> Function() action) =>
      Future.error(StateError('This terminal cannot suspend.'));

  /// Runs the editor on a caller-owned file while the app is suspended.
  /// Uses a nonblank [command], then VISUAL, EDITOR or vi through the user's
  /// shell. Returns the exit code after restoration; launch failures reject.
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) => Future.error(StateError('This terminal cannot run an editor.'));

  /// Writes an OSC 52 clipboard offer; the host does not acknowledge it.
  void copyToClipboard(String text) => write(_clipboardBytes(text));

  /// Reads the system clipboard's image, which no terminal escape offers:
  /// through the platform's tools where the terminal is the process's own.
  Future<ClipboardImage> readClipboardImage() => Future.value(
    const ClipboardImageUnavailable('this terminal reads no clipboard'),
  );

  /// Opens [url] in the system's browser, which no terminal escape does:
  /// through the platform's opener where the terminal is the process's own.
  /// Returns why the opener could not be started, or null when it was.
  Future<String?> openUrl(String url) =>
      Future.value('this terminal opens no links');

  /// Rings the terminal bell.
  void bell() => write('\x07');

  /// Writes a notification on the explicitly selected [channel].
  void notify(
    String message, {
    required NotificationChannel channel,
    String title = '',
  }) => write(_notificationBytes(message, channel, title));

  /// Sets the terminal's window title, flattening control characters.
  void setTitle(String title) => write('\x1b]2;${_cleanOsc(title)}\x07');

  /// Sets the terminal's user variable [name] to [value] with OSC 1337
  /// `SetUserVar`; terminals without it ignore it. Throws [ArgumentError]
  /// for a name [userVariableBytes] refuses.
  void setUserVariable(String name, String value) =>
      write(userVariableBytes(name, value));

  /// Reports [status] with OSC 7501; terminals without the protocol ignore it.
  /// Never wrapped for a multiplexer, as OpenTUI writes it. The process's
  /// own terminal clears what was reported as it is lent or given back. Throws
  /// [ArgumentError] for a record outside the protocol's bounds.
  void setProgramStatus(ProgramStatus status) =>
      write(_programStatusBytes(status));

  /// Removes the record at [id], the root when null, and every record beneath.
  void clearProgramStatus({String? id}) =>
      write('\x1b]7501;state=clear${_programId(id)}\x1b\\');
}

/// The process's own terminal: stdin, stdout and SIGWINCH.
class StdioTerminal extends Terminal {
  /// Uses [input] as bytes, or stdin; the creator must [close] this terminal.
  /// A supplied source remains caller-owned; close cancels only its subscription.
  /// [environment] defaults to the process environment. [tmuxPassthrough]
  /// defaults to whether TMUX is nonempty there, forwarding clipboard and
  /// notification OSCs through tmux while leaving the window title local.
  /// [editorLauncher] may replace process startup, honoring inherited stdio.
  /// [clipboardRunner] runs the tools that read the clipboard's image and
  /// the opener that opens a link, PowerShell from WSL included.
  /// [openUrlProbes] replaces what the opener reads of the machine to tell
  /// WSL apart.
  /// [output] receives the bytes written, stdout by default. Giving the
  /// terminal back waits at most [flushDeadline] for that output to drain,
  /// as a terminal that has gone away never takes it; a flush that fails or
  /// runs out of time is reported once the rest of the release has run,
  /// unless the terminal hung up (its own tty input ended), when no one is
  /// left to tell.
  /// Without [mouse] the terminal keeps the mouse: its own selection, and
  /// no pointer reports.
  StdioTerminal({
    Stream<List<int>>? input,
    Map<String, String>? environment,
    bool? tmuxPassthrough,
    EditorLauncher? editorLauncher,
    ClipboardCommandRunner? clipboardRunner,
    OpenUrlProbes? openUrlProbes,
    IOSink? output,
    this.flushDeadline = const Duration(seconds: 1),
    this.mouse = true,
  }) : _output = output ?? stdout,
       _environment = Map.unmodifiable(environment ?? Platform.environment),
       _editorLauncher = editorLauncher ?? _launchEditor,
       _clipboardRunner = clipboardRunner ?? runClipboardCommand,
       // A runner given in place of the system's runs every opener, so
       // nothing real is started; without one, the opener's own ways.
       _openRunner = clipboardRunner,
       _openUrlProbes = openUrlProbes,
       _bytes = input ?? stdin,
       _ownInput = input == null,
       _tmuxPassthrough =
           tmuxPassthrough ??
           ((environment ?? Platform.environment)['TMUX'] ?? '').isNotEmpty;

  /// How long giving the terminal back waits for its output to drain.
  final Duration flushDeadline;

  /// Whether the app takes the mouse: pointer and wheel reports while it
  /// has the terminal.
  final bool mouse;

  final Stream<List<int>> _bytes;

  /// Whether input is the process's own stdin rather than a supplied stream.
  final bool _ownInput;

  // A tty's input ends only when the terminal hangs up: raw mode reads
  // Ctrl+D as a byte, not as the end.
  bool _ttyInput = false;
  bool _ttyInputEnded = false;

  // Set once giving back a hung-up terminal could not flush its output.
  bool _hungUp = false;
  final IOSink _output;
  final bool _tmuxPassthrough;
  final Map<String, String> _environment;
  final EditorLauncher _editorLauncher;
  final ClipboardCommandRunner _clipboardRunner;
  final ClipboardCommandRunner? _openRunner;
  final OpenUrlProbes? _openUrlProbes;

  @override
  Future<ClipboardImage> readClipboardImage() => readSystemClipboardImage(
    run: _clipboardRunner,
    environment: _environment,
  );

  @override
  Future<String?> openUrl(String url) => openSystemUrl(
    url,
    run: _openRunner,
    environment: _environment,
    probes: _openUrlProbes,
  );
  final _states = StreamController<TerminalState>.broadcast(sync: true);
  var _state = TerminalState.inactive;
  Completer<void>? _suspensionDone;
  Completer<void>? _leaveDone;
  bool _leaveRequested = false;
  bool _screenOwned = false;
  bool _rawOwned = false;
  bool _mouseTrackingOwned = false;
  bool _mouseSgrOwned = false;
  bool _mouseMotionOwned = false;

  /// A program status record was reported and not yet cleared: the
  /// terminal takes it off as it is given back, as OpenTUI's renderer does.
  bool _programStatusOwned = false;

  @override
  void setProgramStatus(ProgramStatus status) {
    super.setProgramStatus(status);
    _programStatusOwned = true;
  }

  @override
  void clearProgramStatus({String? id}) {
    super.clearProgramStatus(id: id);
    if (id == null) _programStatusOwned = false;
  }

  @override
  Stream<TerminalState> get states => _states.stream;

  void _setState(TerminalState state) {
    if (_state == state) return;
    _state = state;
    _states.add(state);
  }

  @override
  void copyToClipboard(String text) => write(_forward(_clipboardBytes(text)));

  @override
  void setUserVariable(String name, String value) =>
      write(_forward(userVariableBytes(name, value)));

  @override
  void notify(
    String message, {
    required NotificationChannel channel,
    String title = '',
  }) {
    final bytes = _notificationBytes(message, channel, title);
    write(channel == NotificationChannel.bell ? bytes : _forward(bytes));
  }

  String _forward(String bytes) =>
      _tmuxPassthrough ? tmuxPassthrough(bytes) : bytes;

  StreamSubscription<String>? _source;
  Future<void>? _closing;
  bool _closed = false;

  String? _savedStty;
  bool _linefeedIsEnter = false;

  /// Whether Enter arrives as LF: when `stty raw` failed and raw mode came
  /// from turning line mode off, which may leave CR turned into LF.
  bool get linefeedIsEnter => _linefeedIsEnter;
  Stream<String>? _input;
  StreamController<String>? _inputController;

  @override
  Size get size {
    try {
      return Size(stdout.terminalColumns, stdout.terminalLines);
    } on StdoutException {
      return const Size(80, 24);
    }
  }

  @override
  Stream<String> get input {
    if (_closed) throw StateError('The terminal input is closed.');
    return _input ??= _makeInput();
  }

  Stream<String> _makeInput() {
    // Keep the real source subscription: asBroadcastStream cancels through a
    // wrapper whose future does not wait for asynchronous source cleanup.
    late final StreamController<String> shared;
    shared = StreamController<String>.broadcast(
      sync: true,
      onListen: () {
        if (_closed) return;
        final source = _source;
        if (source != null) {
          if (source.isPaused && _state != TerminalState.suspended) {
            source.resume();
          }
          return;
        }
        _ttyInput = _ownInput && stdin.hasTerminal;
        _source = _bytes
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(
              (data) {
                if (!_closed) shared.add(data);
              },
              onError: (Object error, StackTrace stack) {
                // On Linux, dart:io reports a hung-up tty as an "error
                // event" just before its end, where macOS ends it plainly:
                // the terminal's own tty failing is that tty gone, its
                // input's end, not a failure of the app (CTUI-192).
                if (_ttyInput) {
                  _ttyInputEnded = true;
                  return;
                }
                if (!_closed) shared.addError(error, stack);
              },
              onDone: () {
                if (_ttyInput) _ttyInputEnded = true;
                unawaited(shared.close());
              },
            );
      },
      onCancel: () => _source?.pause(),
    );
    _inputController = shared;
    // A cached stream must check disposal too, before connecting its source.
    return Stream<String>.multi((listener) {
      if (_closed) {
        listener.closeSync();
        return;
      }
      final subscription = shared.stream.listen(
        listener.addSync,
        onError: listener.addErrorSync,
        onDone: listener.closeSync,
      );
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  /// Permanently releases input, including a paused source; safe to call again.
  /// Each app restores the screen with [leave] before its owner closes input.
  Future<void> close() => _closing ??= () async {
    _closed = true;
    final failures = <(Object, StackTrace)>[];
    for (final step in <Future<void> Function()>[
      leave,
      () async {
        await _source?.cancel();
      },
    ]) {
      try {
        await step();
      } catch (error, stack) {
        failures.add((error, stack));
      }
    }
    unawaited(_states.close());
    // Closing a controller must not wait on a consumer's paused listener.
    final controller = _inputController;
    if (controller != null) unawaited(controller.close());
    _throwFailures(failures);
  }();

  @override
  Stream<Size> get resizes => Platform.isWindows
      ? const Stream.empty()
      : ProcessSignal.sigwinch.watch().map((_) => size);

  @override
  void write(String data) => _output.add(utf8.encode(data));

  @override
  void enter() {
    if (_closed) throw StateError('The terminal is closed.');
    if (_leaveDone != null) throw StateError('The terminal is being released.');
    if (_state == TerminalState.active) return;
    if (_suspensionDone != null) {
      throw StateError('The terminal is suspended.');
    }
    _leaveRequested = false;
    _acquire();
    _setState(TerminalState.active);
  }

  void _acquire() {
    _setRaw();
    _rawOwned = true;
    _screenOwned = true;
    write('\x1b[?1049h\x1b[?25l\x1b[?2004h');
    if (!mouse) return;
    _mouseTrackingOwned = true;
    write('\x1b[?1000h');
    _mouseMotionOwned = true;
    write('\x1b[?1002h');
    _mouseSgrOwned = true;
    write('\x1b[?1006h');
  }

  @override
  Future<void> leave() {
    _leaveRequested = true;
    final running = _leaveDone;
    if (running != null) return running.future;
    final done = Completer<void>();
    _leaveDone = done;
    // Gate app dispatch and frames before the first ownership-changing step.
    // A suspended callback retains ownership until it gives the terminal back.
    if (_state == TerminalState.active) _setState(TerminalState.inactive);
    unawaited(
      () async {
        try {
          await _suspensionDone?.future;
          await _release();
        } finally {
          _setState(TerminalState.inactive);
          _leaveDone = null;
        }
      }().then(done.complete, onError: done.completeError),
    );
    return done.future;
  }

  Future<void> _release() async {
    final failures = <(Object, StackTrace)>[];
    for (final (owned, bytes) in [
      (_mouseTrackingOwned, '\x1b[?1000l'),
      (_mouseMotionOwned, '\x1b[?1002l'),
      (_mouseSgrOwned, '\x1b[?1006l'),
    ]) {
      if (!owned) continue;
      try {
        write(bytes);
      } catch (error, stack) {
        failures.add((error, stack));
      }
    }
    _mouseTrackingOwned = false;
    _mouseMotionOwned = false;
    _mouseSgrOwned = false;
    // Nothing of the app's stays on a terminal lent or given back.
    if (_programStatusOwned) {
      _programStatusOwned = false;
      try {
        write('\x1b]7501;state=clear\x1b\\');
      } catch (error, stack) {
        failures.add((error, stack));
      }
    }
    if (_screenOwned) {
      _screenOwned = false;
      for (final bytes in [
        '\x1b[?2004l',
        '\x1b[0m',
        '\x1b[0 q',
        '\x1b[?25h',
        '\x1b[?1049l',
      ]) {
        try {
          write(bytes);
        } catch (error, stack) {
          failures.add((error, stack));
        }
      }
      try {
        await _output.flush().timeout(flushDeadline);
      } catch (error, stack) {
        // A terminal that hung up takes no output, and there is no one left
        // to tell; its failure must not decide how the process ends (CTUI-73).
        if (_ttyInputEnded) {
          _hungUp = true;
        } else {
          failures.add((error, stack));
        }
      }
    }
    if (_rawOwned) {
      _rawOwned = false;
      try {
        _restore();
      } catch (error, stack) {
        failures.add((error, stack));
      }
    }
    _throwFailures(failures);
  }

  @override
  Future<T> suspend<T>(Future<T> Function() action) {
    if (_closed ||
        _leaveRequested ||
        _state != TerminalState.active ||
        _suspensionDone != null) {
      return Future.error(
        StateError('An active terminal may suspend only once.'),
      );
    }
    final done = Completer<void>();
    _suspensionDone = done;
    _setState(TerminalState.suspended);
    _source?.pause();
    return () async {
      final failures = <(Object, StackTrace)>[];
      late T result;
      try {
        await _release();
        result = await action();
      } catch (error, stack) {
        failures.add((error, stack));
      } finally {
        if (!_closed && !_leaveRequested) {
          try {
            _acquire();
            _source?.resume();
            _setState(TerminalState.active);
          } catch (error, stack) {
            failures.add((error, stack));
            // A live run must clean up even when its caller catches the error.
            if (_states.hasListener) _states.addError(error, stack);
          }
        }
        _suspensionDone = null;
        done.complete();
      }
      _throwFailures(failures);
      return result;
    }();
  }

  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) => suspend(() {
    String? nonblank(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final selected =
        nonblank(command) ??
        nonblank(_environment['VISUAL']) ??
        nonblank(_environment['EDITOR']) ??
        'vi';
    final shell = nonblank(_environment['SHELL']) ?? '/bin/sh';
    return _editorLauncher(
      shell,
      ['-c', '$selected "\$1"', 'editor', path],
      workingDirectory: workingDirectory,
      environment: _environment,
      mode: ProcessStartMode.inheritStdio,
    );
  });

  void _setRaw() {
    _savedStty = null;
    _linefeedIsEnter = false;
    if (!Platform.isWindows) {
      final saved = Process.runSync('sh', ['-c', 'stty -g < /dev/tty']);
      if (saved.exitCode == 0) {
        _savedStty = (saved.stdout as String).trim();
        final raw = Process.runSync('sh', ['-c', 'stty raw -echo < /dev/tty']);
        if (raw.exitCode == 0) return;
      }
    }
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
      _linefeedIsEnter = true;
    } on StdinException {
      // Not a terminal; input is read as it comes.
    }
  }

  void _restore() {
    final saved = _savedStty;
    if (saved != null) {
      final restored = Process.runSync('sh', ['-c', 'stty $saved < /dev/tty']);
      if (restored.exitCode == 0 && Platform.isMacOS) {
        final flags = saved
            .split(':')
            .where((part) => part.startsWith('lflag='));
        final local = flags.isEmpty
            ? null
            : int.tryParse(flags.single.substring(6), radix: 16);
        if (local != null && local & 0x20000000 == 0) {
          // XNU sets PENDIN on return to ICANON and preserves it across
          // tcsetattr. FIONREAD settles that reinput without taking bytes.
          settlePendingInput();
        }
      }
      return;
    }
    try {
      stdin.lineMode = true;
      stdin.echoMode = true;
    } on StdinException {
      // Not a terminal.
    }
  }
}

final _userVariableName = RegExp(r'^[A-Za-z0-9_]+$');

/// The OSC 1337 `SetUserVar` sequence that sets the terminal's user
/// variable [name] to [value], the value base64 of its UTF-8 as the
/// protocol asks; an empty [value] sets it empty. Throws [ArgumentError]
/// for a [name] that is empty or holds anything but ASCII letters, digits
/// and `_`.
String userVariableBytes(String name, String value) {
  if (!_userVariableName.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'is not a user variable name');
  }
  return '\x1b]1337;SetUserVar=$name=${base64.encode(utf8.encode(value))}\x07';
}

/// [bytes] inside tmux's passthrough: a DCS with each ESC doubled, which
/// tmux hands to the terminal outside when `allow-passthrough` is on.
String tmuxPassthrough(String bytes) =>
    '\x1bPtmux;${bytes.replaceAll('\x1b', '\x1b\x1b')}\x1b\\';

String _clipboardBytes(String text) =>
    '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07';

final _oscControls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
String _cleanOsc(String text, {bool separator = false}) {
  final flat = text.replaceAll(_oscControls, ' ');
  return separator ? flat.replaceAll(';', ',') : flat;
}

String _notificationBytes(
  String message,
  NotificationChannel channel,
  String title,
) => switch (channel) {
  NotificationChannel.bell => '\x07',
  NotificationChannel.osc9 => '\x1b]9;${_cleanOsc(message)}\x07',
  NotificationChannel.osc777 =>
    '\x1b]777;notify;${_cleanOsc(title, separator: true)};'
        '${_cleanOsc(message, separator: true)}\x07',
};

final _programName = RegExp(r'^[A-Za-z0-9_.+-]{1,32}$');
final _programControls = RegExp(r'[\x00-\x1f\x7f-\x9f]');

String _programId(String? id) {
  if (id == null) return '';
  final segments = id.split('/');
  if (id.length > 128 ||
      segments.length > 8 ||
      !segments.every(_programName.hasMatch)) {
    throw ArgumentError.value(id, 'id', 'is not a program status path');
  }
  return ':id=$id';
}

String _programText(String name, String? text, int limit) {
  if (text == null || text.isEmpty) return '';
  final bytes = utf8.encode(text);
  if (bytes.length > limit || _programControls.hasMatch(text)) {
    throw ArgumentError.value(
      text,
      name,
      'exceeds $limit bytes or has controls',
    );
  }
  return ':${name == 'message' ? 'msg' : name}=${base64.encode(bytes)}';
}

String _programStatusBytes(ProgramStatus status) {
  final ProgramStatus(:state, :kind, :progress, :app) = status;
  if (kind != null && state != ProgramState.blocked) {
    throw ArgumentError.value(kind, 'kind', 'needs the blocked state');
  }
  if (progress != null &&
      (state != ProgramState.working && state != ProgramState.blocked ||
          progress < 0 ||
          progress > 100)) {
    throw ArgumentError.value(
      progress,
      'progress',
      'needs 0..100, working or blocked',
    );
  }
  if (app != null && app.isNotEmpty && !_programName.hasMatch(app)) {
    throw ArgumentError.value(app, 'app', 'is not a program identifier');
  }
  return '\x1b]7501;state=${state.name}${_programId(status.id)}'
      '${kind == null ? '' : ':kind=${kind.name}'}'
      '${progress == null ? '' : ':progress=$progress'}'
      '${app == null || app.isEmpty ? '' : ':app=$app'}'
      '${_programText('title', status.title, 192)}'
      '${_programText('message', status.message, 2048)}\x1b\\';
}

Future<int> _launchEditor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Map<String, String> environment,
  required ProcessStartMode mode,
}) async {
  final child = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
    mode: mode,
  );
  return child.exitCode;
}

/// Whether [terminal] hung up under its app: its own tty input ended and
/// its output could not be flushed. For runApp only; the package does not
/// export it.
bool terminalHungUp(Terminal terminal) =>
    terminal is StdioTerminal && terminal._hungUp;

void _throwFailures(List<(Object, StackTrace)> failures) {
  if (failures.length == 1) {
    Error.throwWithStackTrace(failures.single.$1, failures.single.$2);
  }
  if (failures.isNotEmpty) throw _TerminalFailures(List.unmodifiable(failures));
}

final class _TerminalFailures implements Exception {
  _TerminalFailures(this.causes);
  final List<(Object, StackTrace)> causes;
  @override
  String toString() =>
      'Terminal failures: ${causes.map((cause) => cause.$1).join('; ')}';
}
