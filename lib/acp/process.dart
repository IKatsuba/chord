/// An agent's process as chord starts and stops it: the command it names,
/// the end of its stderr, and the one way it is stopped.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';

import '../platform/process.dart';

export '../platform/process.dart' show Exit, CannotStart;

/// How much of the agent's stderr is kept for an error that quotes it.
const stderrTailLength = 4096;

/// How many of its stderr's last lines a start failure keeps.
const stderrLines = 6;

/// The most of one stderr line kept; a longer one is cut there, with `…`.
const stderrLineMax = 1024;

/// How long an agent's last words wait for its stderr to end. The end comes
/// within milliseconds of an exit; only a process the agent left behind
/// holding the pipe keeps it open, and an error is not held for that past
/// half a second, which a person does not notice as a delay.
const stderrSettle = Duration(milliseconds: 500);

/// The end of a stream, as lines, and how many non-empty lines came before.
class Tail {
  /// [lines] as they came, and [cut], how many came before them.
  const Tail(this.lines, this.cut);

  final List<String> lines;
  final int cut;

  @override
  bool operator ==(Object other) =>
      other is Tail &&
      other.cut == cut &&
      other.lines.length == lines.length &&
      Iterable.generate(lines.length).every((i) => other.lines[i] == lines[i]);

  @override
  int get hashCode => Object.hash(cut, Object.hashAll(lines));

  @override
  String toString() => 'Tail($lines, cut: $cut)';
}

/// An agent's stderr as it comes, kept two ways: its last
/// [stderrTailLength] characters, and its last [stderrLines] non-empty lines
/// of at most [stderrLineMax] characters each.
class StderrTail {
  var _tail = '';
  final _ring = <String>[];
  var _ended = 0;
  var _open = _OpenLine();

  /// Takes the next piece of stderr.
  void add(String text) {
    _tail = _lastOf(_tail + text, stderrTailLength);
    for (final (index, part) in text.split('\n').indexed) {
      if (index > 0) {
        final line = _open.kept();
        if (line != null) {
          _ended += 1;
          _ring.add(line);
          if (_ring.length > stderrLines) {
            _ring.removeRange(0, _ring.length - stderrLines);
          }
        }
        _open = _OpenLine();
      }
      _open.grow(part);
    }
  }

  /// Its last [stderrTailLength] characters, as they came.
  String get tail => _tail;

  /// Its last non-empty lines, an unfinished last one too, and how many came
  /// before them.
  Tail end() {
    final last = _open.kept();
    final all = [..._ring, ?last];
    final lines = all.length > stderrLines
        ? all.sublist(all.length - stderrLines)
        : all;
    return Tail(lines, _ended + (last == null ? 0 : 1) - lines.length);
  }

  static String _lastOf(String text, int length) =>
      text.length > length ? text.substring(text.length - length) : text;
}

/// A stderr line as it comes: its first [stderrLineMax] characters, whether
/// any came past them, and whether any of it, kept or not, held something.
class _OpenLine {
  var _kept = '';
  var _cut = false;
  var _filled = false;

  void grow(String part) {
    final room = stderrLineMax - _kept.length;
    _kept += part.length > room ? part.substring(0, room) : part;
    _cut = _cut || part.length > room;
    _filled = _filled || part.trim().isNotEmpty;
  }

  /// The line as kept, marked `…` where it was cut; none when it held
  /// nothing.
  String? kept() {
    if (!_filled) return null;
    final kept = _kept.endsWith('\r')
        ? _kept.substring(0, _kept.length - 1)
        : _kept;
    return _cut ? '$kept…' : kept.trimRight();
  }
}

/// The argv [command] names: a list as it is, a string split as a shell
/// would split it, with `$NAME` left as written, since the shell that would
/// expand it already did for a flag, and a settings file names no shell.
///
/// Throws a [FormatException] for a command that holds shell syntax
/// (operators, globs, comments) or is empty.
List<String> commandArgv(Object command) {
  final List<String> words;
  switch (command) {
    case String():
      words = [
        for (final word in _parse(command))
          if (word is String)
            word
          else
            throw FormatException(
              'The agent command "$command" holds shell syntax; '
              'give a plain command line.',
            ),
      ];
    case List<String>():
      words = [...command];
    default:
      throw ArgumentError.value(command, 'command', 'a String or List<String>');
  }
  if (words.isEmpty || words.first.isEmpty) {
    throw const FormatException('The agent command is empty.');
  }
  return words;
}

// A port of shell-quote 1.12.0's `parse`, kept to what commandArgv calls:
// an env that returns `$NAME` for every name, and no options. Its words are
// strings; an operator, a glob or a comment is a _Syntax.

class _Syntax {
  const _Syntax();
}

const _control =
    '(?:'
    r'\|\||'
    r'\&(?:\&|>>?)|'
    r';;\&?|'
    r'[;|]\&|'
    r'\<\(|'
    r'\<\<\<|'
    r'\<\<-|'
    r'\<\<(?!\()|'
    r'>>|'
    r'>[&|(]|'
    r'<[&>]|'
    r'[&;()|<>]'
    ')';
final _controlRe = RegExp('^$_control\$');
const _meta = r'|&;()<> \t';
const _singleQuote = r"'([^']*?)'";
const _ansiCBody = r"(?:\\[\s\S]|[^\\'])*?";
const _ansiCQuote = "\\\$'$_ansiCBody'";
final _ansiCAt = RegExp("\\\$'$_ansiCBody(?:(')|\\\\?\$)");
const _ansiCLetters = 'abeEfnrtv';
const _ansiCChars = '\x07\b\x1B\x1B\f\n\r\t\v';
final _bareword =
    "(\\\\['\"\$\\\\$_meta]|\\\$\\\$|\\\$(?!${_ansiCQuote.substring(2)})|"
    "[^\\s'\"\$$_meta])+";
const _doubleQuote = r'"(?:\\[\s\S]|[^"\\])*"';
final _chunker = RegExp(
  '($_control)|($_ansiCQuote|$_bareword|$_doubleQuote|$_singleQuote)+',
);
final _ansiCEscape = RegExp(
  r'''\\([0-7]{1,3}|x[\dA-Fa-f]{1,2}|u[\dA-Fa-f]{1,4}|U[\dA-Fa-f]{1,8}|c(?:\\\\|[\s\S])|[abeEfnrtv\\'"?])''',
);

String _expandAnsiCEscape(Match match) {
  final escape = match[1]!;
  final kind = escape[0];
  if (kind == 'c') {
    final ctrl = escape[1];
    return ctrl == '?'
        ? '\x7F'
        : String.fromCharCode(ctrl.codeUnitAt(0) & 0x1F);
  }
  if (kind == 'x' || kind == 'u' || kind == 'U') {
    final cp = int.parse(escape.substring(1), radix: 16);
    if (cp > 0x10FFFF) return match[0]!;
    return String.fromCharCodes(
      cp > 0xFFFF ? [0xD7C0 + (cp >> 10), 0xDC00 + (cp & 0x3FF)] : [cp],
    );
  }
  if (kind.compareTo('0') >= 0 && kind.compareTo('7') <= 0) {
    return String.fromCharCode(int.parse(escape, radix: 8) & 0xFF);
  }
  final letter = _ansiCLetters.indexOf(escape);
  return letter < 0 ? escape : _ansiCChars[letter];
}

// Like bash, a NUL ends the string.
String _expandAnsiC(String body) =>
    body.replaceAllMapped(_ansiCEscape, _expandAnsiCEscape).split('\x00')[0];

List<Object> _parse(String string) {
  var commented = false;
  final entries = <Object>[];
  for (final match in _chunker.allMatches(string)) {
    final s = match[0]!;
    if (s.isEmpty || commented) continue;
    if (_controlRe.hasMatch(s)) {
      entries.add(const _Syntax());
      continue;
    }

    String? quote;
    var esc = false;
    var out = '';
    var isGlob = false;
    var i = 0;
    Object? entry;

    String parseEnvVar() {
      i += 1;
      final String varname;
      final char = i < s.length ? s[i] : '';
      if (char == '{') {
        i += 1;
        if (i < s.length && s[i] == '}') {
          throw FormatException(
            'Bad substitution: ${s.substring(i - 2, i + 1)}',
          );
        }
        // Braces matched by depth, so a nested `${` keeps its inner `}` from
        // ending the outer substitution.
        var depth = 1;
        var varend = i;
        while (depth > 0 && varend < s.length) {
          if (s[varend] == '{' && varend > 0 && s[varend - 1] == r'$') {
            depth += 1;
          } else if (s[varend] == '}') {
            depth -= 1;
          }
          varend += 1;
        }
        if (depth != 0) {
          throw FormatException('Bad substitution: ${s.substring(i)}');
        }
        varend -= 1;
        varname = s.substring(i, varend);
        i = varend;
      } else if (char.isNotEmpty && r'*@#?$!-'.contains(char)) {
        varname = char;
      } else {
        final sliced = s.substring(i);
        final varend = RegExp(r'[^\w\d_]').firstMatch(sliced);
        if (varend == null) {
          varname = sliced;
          i = s.length;
        } else {
          varname = sliced.substring(0, varend.start);
          i += varend.start - 1;
        }
      }
      return '\$$varname';
    }

    for (i = 0; i < s.length; i++) {
      var c = s[i];
      isGlob = isGlob || (quote == null && (c == '*' || c == '?'));
      if (esc) {
        out += c;
        esc = false;
      } else if (quote != null) {
        if (c == quote) {
          quote = null;
        } else if (quote == "'") {
          out += c;
        } else if (c == r'\') {
          i += 1;
          c = i < s.length ? s[i] : '';
          out += c == '"' || c == r'\' || c == r'$' ? c : '\\$c';
        } else if (c == r'$') {
          out += parseEnvVar();
        } else {
          out += c;
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (_controlRe.hasMatch(c)) {
        entry = const _Syntax();
        break;
      } else if (c == '#') {
        commented = true;
        entry = out.isNotEmpty ? [out, const _Syntax()] : const _Syntax();
        break;
      } else if (c == r'\') {
        esc = true;
      } else if (c == r'$' &&
          i + 1 < s.length &&
          s[i + 1] == "'" &&
          _ansiCAt.matchAsPrefix(s, i)?[1] != null) {
        final end = _ansiCAt.matchAsPrefix(s, i)!.end;
        out += _expandAnsiC(s.substring(i + 2, end - 1));
        i = end - 1;
      } else if (c == r'$') {
        out += parseEnvVar();
      } else {
        out += c;
      }
    }

    entry ??= isGlob ? const _Syntax() : out;
    if (entry is List<Object>) {
      entries.addAll(entry);
    } else {
      entries.add(entry);
    }
  }
  return entries;
}

/// How long each step of a stop waits for the agent's exit before the next,
/// harder one: stdin ended, then SIGTERM to its group, then SIGKILL.
class StopBounds {
  /// chord's own bounds, two seconds each, unless given others.
  const StopBounds({
    this.exit = const Duration(seconds: 2),
    this.term = const Duration(seconds: 2),
    this.kill = const Duration(seconds: 2),
  });

  /// After stdin ends, which is how ACP tells an agent over stdio to go.
  final Duration exit;

  /// After SIGTERM.
  final Duration term;

  /// After SIGKILL, for the exit to be seen at all.
  final Duration kill;
}

/// Thrown when an agent's exit was not seen even after it was killed.
class AgentExitError implements Exception {
  /// The [pids] whose exit was not seen.
  const AgentExitError(this.pids);

  final List<int> pids;

  @override
  String toString() =>
      'Agent process ${pids.join(', ')} did not exit after SIGKILL.';
}

/// What chord writes to an agent, with the one way it is ended: [add] and
/// [flush] belong to the connection's single writer, [end] to anyone, any
/// time.
abstract interface class AgentInput {
  /// Queues [bytes]; never called while a [flush] is pending.
  void add(List<int> bytes);

  /// Settles once what was added is taken, or fails as the pipe does.
  Future<void> flush();

  /// Ends stdin once the writer is idle: at the first turn of the event
  /// loop with no flush pending. A writer with something queued adds it and
  /// starts its flush in the microtasks after it was queued, or after the
  /// last flush completed, so what it queued before [end] goes out ahead of
  /// the end. Never throws, never awaited, idempotent.
  void end();

  /// Settles once stdin is closed; fails when the pipe does.
  Future<void> get done;
}

/// One agent process, its stdio and the one way it is stopped.
abstract interface class AgentProcess {
  /// Its process id, which is also its group's.
  int get pid;

  /// What chord writes to it; the connection's writer is its only user.
  AgentInput get stdin;

  /// What it writes.
  Stream<List<int>> get stdout;

  /// Settles once its exit is seen, however it came.
  Future<Exit> get status;

  /// The end of what it wrote to stderr, for a start that failed.
  String stderrTail();

  /// The last of its stderr's non-empty lines, and how many came before.
  Tail stderrEnd();

  /// [stderrTail] once stderr has ended, or once [stderrSettle] passes
  /// without its end: what an agent that goes says last.
  Future<String> lastWords();

  /// Stops it within [bounds] whatever it answers, and returns once its exit
  /// is seen; throws [AgentExitError] if that exit is not seen even after
  /// SIGKILL. Idempotent: a second call joins the first.
  Future<void> stop([StopBounds bounds = const StopBounds()]);
}

/// A future's outcome, as [settledWithin] gives it.
sealed class Settled<T> {
  const Settled();
}

/// It completed with [value].
class Fulfilled<T> extends Settled<T> {
  /// The [value] it completed with.
  const Fulfilled(this.value);

  final T value;
}

/// It failed with [error].
class Rejected<T> extends Settled<T> {
  /// The [error] it failed with.
  const Rejected(this.error);

  final Object error;
}

/// [future]'s outcome, or null once [within] passes without one, so a wait
/// on an agent that stopped answering is bounded.
Future<Settled<T>?> settledWithin<T>(Future<T> future, Duration within) {
  final done = Completer<Settled<T>?>();
  final timer = Timer(within, () {
    if (!done.isCompleted) done.complete(null);
  });
  future.then<void>(
    (value) {
      timer.cancel();
      if (!done.isCompleted) done.complete(Fulfilled(value));
    },
    onError: (Object error) {
      timer.cancel();
      if (!done.isCompleted) done.complete(Rejected(error));
    },
  );
  return done.future;
}

/// The stop as `process.ts` runs it: [end] stdin; [StopBounds.exit];
/// SIGTERM to the group; [StopBounds.term]; SIGKILL; [StopBounds.kill];
/// [AgentExitError]. Once the exit is seen, SIGKILL to the group anyway.
Future<void> stopLadder({
  required int pid,
  required Future<Exit> status,
  required void Function() end,
  required bool Function(ProcessSignal signal) signal,
  bool Function()? exited,
  StopBounds bounds = const StopBounds(),
}) async {
  Future<bool> seen(Duration within) async =>
      (exited?.call() ?? false) || await settledWithin(status, within) != null;

  end();
  if (!await seen(bounds.exit)) {
    signal(ProcessSignal.sigterm);
    if (!await seen(bounds.term)) {
      signal(ProcessSignal.sigkill);
      if (!await seen(bounds.kill)) throw AgentExitError([pid]);
    }
  }
  // The agent can go and leave what it started behind in its group, still
  // holding an account or the pipes; nothing there outlives the session.
  signal(ProcessSignal.sigkill);
}

/// Starts an agent in a process group of its own, so a stop reaches what it
/// started too, and returns once the group exists. Throws [FormatException]
/// for a command [commandArgv] refuses, [CannotStart] when it does not
/// start, and [cancellationToken]'s exception when that is cancelled first,
/// with whatever had started stopped within [stop].
Future<AgentProcess> spawnAgent({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  void Function(String text)? onStderr,
  CancellationToken? cancellationToken,
  StopBounds stop = const StopBounds(),
  Launcher launcher = defaultLauncher,
  ProcessGroups? groups,
  Kill? kill,
}) async {
  final [program, ...args] = commandArgv(command);
  cancellationToken?.throwIfCancelled();
  final group = await spawnGroup(
    program,
    args,
    cwd: cwd,
    env: env,
    launcher: launcher,
    groups: groups,
    kill: kill,
  );
  final agent = _GroupAgent(group, onStderr);

  final cancelled = Completer<Exception>();
  final listener = _OnCancel(cancelled.complete);
  if (cancellationToken != null) listener.listen(cancellationToken);
  try {
    final first = await Future.any<Object?>([
      group.started.then((_) => null),
      cancelled.future,
    ]);
    if (first is Exception) throw first;
  } catch (_) {
    await agent.stop(stop);
    rethrow;
  } finally {
    listener.forget();
  }
  return agent;
}

/// Calls back once a token is cancelled, or at once for one already
/// cancelled.
class _OnCancel with Cancellable {
  _OnCancel(this._callback);

  final void Function(Exception exception) _callback;

  void listen(CancellationToken token) {
    if (token.isCancelled) {
      _callback(token.exception!);
    } else {
      maybeAttach(token);
    }
  }

  void forget() => detach();

  @override
  void onCancel(Exception cancelException) {
    super.onCancel(cancelException);
    _callback(cancelException);
  }
}

/// A [GroupProcess] as an [AgentProcess].
class _GroupAgent implements AgentProcess {
  _GroupAgent(this._group, void Function(String text)? onStderr)
    : stdin = _ProcessInput(_group.stdin) {
    status = _group.exit.whenComplete(() => _exited = true)..ignore();
    _group.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (text) {
            _tail.add(text);
            onStderr?.call(text);
          },
          onError: (_) {},
          onDone: _stderrEnded.complete,
        );
  }

  final GroupProcess _group;
  final _tail = StderrTail();
  final _stderrEnded = Completer<void>();
  var _exited = false;
  Future<void>? _stopping;

  @override
  int get pid => _group.pid;

  @override
  final AgentInput stdin;

  @override
  Stream<List<int>> get stdout => _group.stdout;

  @override
  late final Future<Exit> status;

  @override
  String stderrTail() => _tail.tail;

  @override
  Tail stderrEnd() => _tail.end();

  @override
  Future<String> lastWords() async {
    await settledWithin(_stderrEnded.future, stderrSettle);
    return _tail.tail;
  }

  @override
  Future<void> stop([StopBounds bounds = const StopBounds()]) =>
      _stopping ??= stopLadder(
        pid: pid,
        status: status,
        end: stdin.end,
        signal: _group.signal,
        exited: () => _exited,
        bounds: bounds,
      );
}

/// A process's stdin, ended only once no flush is pending, since an
/// [IOSink] being flushed throws on `close`.
class _ProcessInput implements AgentInput {
  _ProcessInput(this._sink);

  final IOSink _sink;
  Future<void>? _flushing;
  var _ending = false;
  var _closed = false;

  @override
  void add(List<int> bytes) => _sink.add(bytes);

  @override
  Future<void> flush() async {
    final flushing = _flushing = _sink.flush();
    try {
      await flushing;
    } finally {
      _flushing = null;
      if (_ending) _closeWhenIdle();
    }
  }

  @override
  void end() {
    _ending = true;
    _closeWhenIdle();
  }

  // A timer, not a microtask: the writer's next add and flush come in the
  // microtasks after this flush, and must find stdin still open.
  void _closeWhenIdle() => Timer.run(() {
    if (_closed || _flushing != null) return;
    _closed = true;
    _sink.close().ignore();
  });

  @override
  Future<void> get done => _sink.done;
}

/// An agent process in memory, for tests and benchmarks: the test writes
/// its stdout and stderr, decides when it exits, and reads what chord wrote.
class MemoryAgentProcess implements AgentProcess {
  /// A process with [pid]; [onSignal] hears every signal the stop sends.
  MemoryAgentProcess({this.pid = 4242, this.onSignal});

  @override
  final int pid;

  /// Called with each signal the ladder sends, as a real process would get
  /// it.
  final void Function(ProcessSignal signal)? onSignal;

  /// Every signal sent, in order.
  final signals = <ProcessSignal>[];

  @override
  final MemoryInput stdin = MemoryInput();

  final _stdout = StreamController<List<int>>();
  final _exit = Completer<Exit>();
  final _tail = StderrTail();
  final _stderrEnded = Completer<void>();
  Future<void>? _stopping;

  /// Hears each piece of stderr as it is written.
  void Function(String text)? onStderr;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  /// Writes [bytes] to its stdout.
  void writeStdout(List<int> bytes) => _stdout.add(bytes);

  /// Writes [message] as one line of JSON to its stdout.
  void send(Map<String, Object?> message) =>
      writeStdout(utf8.encode('${jsonEncode(message)}\n'));

  /// Ends its stdout.
  void closeStdout() {
    if (!_stdout.isClosed) _stdout.close();
  }

  /// Fails its stdout with [error].
  void failStdout(Object error) => _stdout.addError(error);

  /// Writes [text] to its stderr.
  void writeStderr(String text) {
    _tail.add(text);
    onStderr?.call(text);
  }

  /// Ends its stderr.
  void closeStderr() {
    if (!_stderrEnded.isCompleted) _stderrEnded.complete();
  }

  /// Exits it with [exit].
  void exit([Exit exit = const Exit(0)]) {
    if (!_exit.isCompleted) _exit.complete(exit);
  }

  /// Whether its exit has come.
  bool get exited => _exit.isCompleted;

  @override
  Future<Exit> get status => _exit.future;

  @override
  String stderrTail() => _tail.tail;

  @override
  Tail stderrEnd() => _tail.end();

  @override
  Future<String> lastWords() async {
    await settledWithin(_stderrEnded.future, stderrSettle);
    return _tail.tail;
  }

  @override
  Future<void> stop([StopBounds bounds = const StopBounds()]) =>
      _stopping ??= stopLadder(
        pid: pid,
        status: status,
        end: stdin.end,
        signal: (signal) {
          signals.add(signal);
          onSignal?.call(signal);
          return true;
        },
        exited: () => exited,
        bounds: bounds,
      );
}

/// [MemoryAgentProcess]'s stdin: what was written, and a flush the test
/// holds when it says so.
class MemoryInput implements AgentInput {
  /// Every byte added, in order, flushed or not.
  final bytes = <int>[];

  /// Whether [end] was called.
  var ended = false;

  /// Whether stdin is closed: [end] was called and the writer went idle.
  var closed = false;

  /// How many bytes were added when stdin closed.
  int? closedAt;

  /// How many times something was added after stdin closed; a correct
  /// writer keeps this at zero.
  var addsAfterClose = 0;

  /// While true, a flush stays pending until [release].
  var hold = false;

  /// Whether a flush is pending.
  bool get flushing => _pending != null;

  /// How many times something was added while a flush was pending; a
  /// correct writer keeps this at zero.
  var addsWhileFlushing = 0;

  Completer<void>? _pending;
  final _done = Completer<void>();
  Object? _error;

  /// What was written, as text.
  String get text => utf8.decode(bytes);

  /// What was written, one decoded message per line.
  List<Map<String, Object?>> get messages => [
    for (final line in const LineSplitter().convert(text))
      if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];

  @override
  void add(List<int> bytes) {
    if (_pending != null) addsWhileFlushing++;
    if (closed) addsAfterClose++;
    this.bytes.addAll(bytes);
  }

  @override
  Future<void> flush() {
    if (_error != null) return Future.error(_error!);
    if (!hold) return Future.value();
    return (_pending = Completer<void>()).future;
  }

  /// Completes a held flush.
  void release() {
    hold = false;
    final pending = _pending;
    _pending = null;
    pending?.complete();
    if (ended) _closeWhenIdle();
  }

  /// Fails the pipe with [error], a held flush too.
  void fail(Object error) {
    _error = error;
    final pending = _pending;
    _pending = null;
    pending?.completeError(error);
    if (!_done.isCompleted) _done.completeError(error);
  }

  @override
  void end() {
    if (ended) return;
    ended = true;
    _closeWhenIdle();
  }

  // As a real stdin closes: at the first turn with no flush pending.
  void _closeWhenIdle() => Timer.run(() {
    if (closed || _pending != null || _error != null) return;
    closed = true;
    closedAt = bytes.length;
    if (!_done.isCompleted) _done.complete();
  });

  @override
  Future<void> get done => _done.future;
}
