import 'dart:async';
import 'dart:io';

import '../input/keys.dart';
import '../input/parser.dart';
import '../terminal/background.dart';
import '../terminal/buffer.dart';
import '../terminal/renderer.dart';
import '../terminal/terminal.dart';
import 'framework.dart';
import 'focus_manager.dart';
import 'host.dart';
import 'theme.dart';
import 'theme_data.dart';

const _frameInterval = Duration(milliseconds: 16);
const _escapeTimeout = Duration(milliseconds: 30);

/// How long a half-read OSC reply may wait for its rest: a slow link splits
/// replies further apart than a lone escape's pause.
const _oscTimeout = Duration(milliseconds: 100);

/// How long runApp waits for the terminal to say its background.
const _askTimeout = Duration(milliseconds: 100);

/// OSC 11 with `?`: asks the terminal for its background colour.
const _askBackground = '\x1b]11;?\x07';
const _askKeyboard = '\x1b[?u';
// Disambiguate escape codes and report alternate keys (1 | 4), as
// OpenTUI pushes: a press names its key on the US layout too.
const _pushKeyboard = '\x1b[>5u';
const _popKeyboard = '\x1b[<u';

/// Runs [app] in the terminal until it quits, then restores the terminal.
///
/// A supplied terminal is caller-owned: its per-run listeners are removed,
/// leaving reusable input paused. The caller closes a [StdioTerminal] after
/// its last app. A terminal created here is closed before returning or exiting.
///
/// Supported termination signals (HUP, INT and TERM) restore the terminal,
/// await [beforeExit], remove per-run signal listeners, then re-raise the
/// original signal even with [exitProcess] false. Set [handleSignals] false
/// when an embedding application owns signal cleanup and re-raising.
/// When the [StdioTerminal] hangs up under the app (its tty input ends and
/// its output cannot be flushed), the process ends by SIGHUP: re-raised
/// here when handling signals, else left for at most two seconds to the
/// embedder's handler before the usual exit.
///
/// Changes are drawn at most once per frame, so a stream that updates
/// state a thousand times a second still draws about sixty frames.
///
/// Before the first frame it asks for the background (OSC 11) and kitty
/// keyboard support concurrently, waiting at most 100 ms. A supported keyboard
/// uses disambiguated keys until suspend/leave. Background falls back to
/// `COLORFGBG`, then dark; [app] gets a
/// [Theme] of [theme] if given, else the dark or light one for that
/// background, and under `NO_COLOR` always [ThemeData.plain]. What was found
/// is [Theme.backgroundOf] and [Theme.noColorOf]. [environment] is where
/// those variables are read, the process's own by default.
///
/// [beforeExit] is awaited once the app is unmounted and the terminal
/// restored, before the process exits, after a failure too: where an app
/// that owns child processes stops them. If it throws, that is printed and
/// the exit is 1.
Future<void> runApp(
  Widget app, {
  Terminal? terminal,
  bool exitProcess = true,
  bool handleSignals = true,
  ThemeData? theme,
  Map<String, String>? environment,
  Future<void> Function()? beforeExit,

  /// The wait for the next key of a pending chord, three seconds by default.
  Duration chordTimeout = defaultChordTimeout,

  /// The US keys a single typed character would have been, for presses
  /// that do nothing as typed; none by default.
  KeyLayoutFallback? layoutFallback,
}) async {
  final term = terminal ?? StdioTerminal();
  final env = environment ?? Platform.environment;
  final noColor = (env['NO_COLOR'] ?? '').isNotEmpty;
  final answered = Completer<Brightness?>();
  final keyboardReady = Completer<void>();
  Timer? keyboardTimer;
  bool keyboardAwaiting = false;
  bool keyboardPushed = false;
  bool inputStarted = false;
  // Keys that come while runApp waits for the answer, delivered once the
  // app is mounted; null from then on.
  List<InputEvent>? held = [];
  final done = Completer<void>();
  var parser = InputParser();
  var suspended = false;
  Buffer? previous;
  Timer? frameTimer;
  Timer? escapeTimer;
  var lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  AppHost? maybeHost;
  final subs = <StreamSubscription<Object?>>[];
  final signalSubs = <StreamSubscription<ProcessSignal>>[];
  ProcessSignal? terminatingSignal;
  Object? failure;
  StackTrace? failureStack;

  void drawFrame() {
    frameTimer?.cancel();
    frameTimer = null;
    if (suspended || done.isCompleted || maybeHost == null) return;
    lastFrame = DateTime.now();
    final next = maybeHost!.drawFrame(term.size);
    term.write(diffBuffers(previous, next));
    previous = next;
  }

  void scheduleFrame() {
    if (suspended ||
        frameTimer != null ||
        done.isCompleted ||
        maybeHost == null) {
      return;
    }
    final since = DateTime.now().difference(lastFrame);
    final wait = since >= _frameInterval
        ? Duration.zero
        : _frameInterval - since;
    frameTimer = Timer(wait, drawFrame);
  }

  void quit() {
    if (!done.isCompleted) done.complete();
    maybeHost?.cancelPointerCapture();
    if (!answered.isCompleted) answered.complete(null);
    if (!keyboardReady.isCompleted) keyboardReady.complete();
  }

  void stopKeyboard() {
    keyboardTimer?.cancel();
    keyboardTimer = null;
    keyboardAwaiting = false;
    if (!keyboardReady.isCompleted) keyboardReady.complete();
    if (keyboardPushed) {
      keyboardPushed = false;
      term.write(_popKeyboard);
    }
  }

  void askKeyboard() {
    if (suspended || done.isCompleted) return;
    keyboardAwaiting = true;
    keyboardTimer?.cancel();
    keyboardTimer = Timer(_askTimeout, () {
      keyboardAwaiting = false;
      if (!keyboardReady.isCompleted) keyboardReady.complete();
    });
    term.write(_askKeyboard);
  }

  void handle(List<InputEvent> events) {
    for (final e in events) {
      if (suspended || done.isCompleted) break;
      if (e is KeyboardProtocolEvent) {
        if (keyboardAwaiting) {
          keyboardAwaiting = false;
          keyboardTimer?.cancel();
          keyboardTimer = null;
          keyboardPushed = true;
          term.write(_pushKeyboard);
          if (!keyboardReady.isCompleted) keyboardReady.complete();
        }
        continue;
      }
      if (e is OscEvent) {
        // The answer to runApp's question; any other reply, or one too
        // late, is dropped: an app has no use for it, and it must never
        // become keys.
        if (e.code == 11 && !answered.isCompleted) {
          answered.complete(brightnessFromOsc11(e.data));
        }
        continue;
      }
      if (held case final h?) {
        h.add(e);
        continue;
      }
      switch (e) {
        case KeyEvent():
          maybeHost!.handleKey(e);
        case PasteEvent(:final text):
          maybeHost!.handlePaste(text);
        case MouseEvent():
          maybeHost!.handleMouse(e);
        case OscEvent():
        case KeyboardProtocolEvent():
          break;
      }
    }
    scheduleFrame();
  }

  // The body's own future is made in the guarded zone and awaited from the
  // caller's: an error does not cross error zones, so a body that threw (a
  // terminal that cannot enter, a first build that fails) would never resume
  // this await, the terminal left raw and beforeExit never run. Its failures
  // are caught inside, so that future never fails.
  await runZonedGuarded(
    () async {
      try {
        if (handleSignals && !Platform.isWindows) {
          for (final signal in [
            ProcessSignal.sighup,
            ProcessSignal.sigint,
            ProcessSignal.sigterm,
          ]) {
            signalSubs.add(
              signal.watch().listen(
                (signal) {
                  terminatingSignal ??= signal;
                  quit();
                },
                onError: (Object error, StackTrace stack) {
                  failure = error;
                  failureStack = stack;
                  quit();
                },
              ),
            );
          }
        }
        subs.add(
          term.states.listen(
            (state) {
              if (state != TerminalState.active) {
                suspended = true;
                maybeHost?.cancelPointerCapture();
              }
              if (state == TerminalState.suspended) {
                suspended = true;
                stopKeyboard();
                frameTimer?.cancel();
                frameTimer = null;
                escapeTimer?.cancel();
                escapeTimer = null;
                parser.reset();
                maybeHost?.focusManager.cancelPendingChord();
                held?.clear();
              } else if (state == TerminalState.active) {
                parser = InputParser()
                  ..linefeedIsEnter =
                      term is StdioTerminal && term.linefeedIsEnter;
                suspended = false;
                previous = null;
                if (inputStarted) askKeyboard();
                scheduleFrame();
              } else {
                stopKeyboard();
                quit();
              }
            },
            onError: (Object error, StackTrace stack) {
              failure = error;
              failureStack = stack;
              quit();
            },
          ),
        );
        term.enter();
        parser.linefeedIsEnter = term is StdioTerminal && term.linefeedIsEnter;
        subs.add(
          term.input.listen((data) {
            if (suspended || done.isCompleted) return;
            escapeTimer?.cancel();
            handle(parser.feed(data));
            if (!suspended && parser.hasPending) {
              escapeTimer = Timer(
                parser.hasPendingOsc || parser.hasPendingCsi
                    ? _oscTimeout
                    : _escapeTimeout,
                () => handle(parser.flush()),
              );
            }
          }, onDone: quit),
        );
        inputStarted = true;
        term.write(_askBackground);
        askKeyboard();
        final asking = Timer(_askTimeout, () {
          if (!answered.isCompleted) answered.complete(null);
        });
        final fromTerminal = await answered.future;
        await keyboardReady.future;
        asking.cancel();
        if (done.isCompleted) return;
        final background = resolveBackground(fromTerminal, env['COLORFGBG']);
        final data = noColor
            ? ThemeData.plain(brightness: background.brightness)
            : theme ??
                  (background.brightness == Brightness.light
                      ? ThemeData.light()
                      : ThemeData.dark());
        maybeHost = AppHost(
          TerminalEnvironment(
            background: background,
            noColor: noColor,
            child: Theme(data: data, child: app),
          ),
          onNeedsFrame: scheduleFrame,
          onExit: quit,
          chordTimeout: chordTimeout,
          layoutFallback: layoutFallback,
        );
        final early = held!;
        held = null;
        subs.add(
          term.resizes.listen((_) {
            maybeHost?.updateSize(term.size);
            previous = null;
            scheduleFrame();
          }),
        );
        // Layout mounts focus nodes that a constraint-built picker may own.
        // Replay early input only once those targets can receive it.
        drawFrame();
        if (early.isNotEmpty) handle(early);
        await done.future;
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        quit();
      }
    },
    (error, stack) {
      failure = error;
      failureStack = stack;
      quit();
    },
  );

  frameTimer?.cancel();
  escapeTimer?.cancel();
  keyboardTimer?.cancel();
  if (suspended) {
    try {
      await term.leave();
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
  }
  // Each step is tried whatever the one before did, so a failure to
  // unmount or to restore the terminal still reaches beforeExit; what
  // failed is said once the terminal is restored, where it stays readable.
  final failures = [?failure, ?failureStack];
  for (final step in <FutureOr<void> Function()>[
    for (final subscription in subs) subscription.cancel,
    () => maybeHost?.dispose(),
    stopKeyboard,
    term.leave,
    if (terminal == null && term is StdioTerminal) term.close,
  ]) {
    try {
      await step();
    } catch (error, stack) {
      failures.addAll([error, stack]);
    }
  }
  // A hung-up terminal is followed by its SIGHUP, which must decide how the
  // process ends, not this exit racing it (CTUI-73): handling signals, the
  // app dies by it; otherwise the signal's owner is given a moment first.
  final hungUp = terminalHungUp(term);
  if (hungUp && signalSubs.isNotEmpty) {
    terminatingSignal ??= ProcessSignal.sighup;
  }
  // A terminal that has gone away fails these writes, later and on stderr's
  // done future: that failure has nowhere to be said, and must not take the
  // place of the signal or the exit code the app leaves by.
  stderr.done.ignore();
  void say(Object? line) {
    try {
      stderr.writeln(line);
    } catch (_) {
      // stderr closed by an earlier failure.
    }
  }

  failures.forEach(say);
  var failed = failures.isNotEmpty;
  if (beforeExit != null) {
    try {
      await beforeExit();
    } catch (error, stack) {
      say(error);
      say(stack);
      failed = true;
    }
  }
  // Keep repeated termination signals held until caller-owned cleanup ends.
  for (final subscription in signalSubs) {
    try {
      await subscription.cancel();
    } catch (error, stack) {
      say(error);
      say(stack);
      failed = true;
    }
  }
  final signal = terminatingSignal;
  if (signal != null) {
    Process.killPid(pid, signal);
    // Delivery is asynchronous: exiting at once often wins over the signal
    // (CTUI-127), so it is given a grace first, as the port's raiseSignal
    // does. An ignored signal or another owner's handler that does not end
    // the process must still not become success.
    await Future<void>.delayed(_signalGrace);
    exit(128 + signal.signalNumber);
  }
  if (exitProcess) {
    if (hungUp) await Future<void>.delayed(_hangUpGrace);
    exit(failed ? 1 : 0);
  }
}

// How long runApp, leaving signals to its embedder, waits before exiting
// after its terminal hung up, for the embedder's SIGHUP handler to finish
// and end the process by the signal.
const _hangUpGrace = Duration(seconds: 2);

// How long runApp waits for a re-raised signal to end the process before
// it exits with the signal's status instead.
const _signalGrace = Duration(milliseconds: 500);
