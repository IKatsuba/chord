/// Tests without a terminal: render a widget at a size, press keys, and
/// check what the screen shows.
library;

import 'dart:async';

import 'package:matcher/matcher.dart';
import 'package:meta/meta.dart';
import 'package:test_api/scaffolding.dart' as scaffolding;

import 'chord_tui.dart';

/// What the screen shows after a frame.
class Screen {
  /// The screen [buffer] shows.
  Screen(this.buffer);

  /// The cells of the frame.
  final Buffer buffer;

  /// The rows, with spaces at the end of each removed.
  List<String> get lines => [for (final l in buffer.lines) l.trimRight()];

  /// All rows joined by newlines, without the empty rows at the bottom.
  String get text {
    final l = lines;
    while (l.isNotEmpty && l.last.isEmpty) {
      l.removeLast();
    }
    return l.join('\n');
  }

  /// The style of the cell at column [x], row [y].
  Style styleAt(int x, int y) => buffer.styleAt(x, y);

  /// The character of the cell at column [x], row [y].
  String charAt(int x, int y) => buffer.charAt(x, y);

  @override
  String toString() => text;
}

/// The tester's terminal: draws nothing, and records the services the app
/// asks of it, for a test to check.
class TestTerminal extends Terminal {
  /// A terminal of [size] with no input.
  TestTerminal([this.size = const Size(80, 24)]);

  @override
  Size size;

  /// Every URL [openUrl] was asked to open, in order.
  final openedUrls = <String>[];

  /// Every text [copyToClipboard] was given, in order.
  final copied = <String>[];

  @override
  Stream<String> get input => const Stream.empty();

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void write(String data) {}

  @override
  void enter() {}

  @override
  Future<void> leave() async {}

  @override
  Future<String?> openUrl(String url) async {
    openedUrls.add(url);
    return null;
  }

  @override
  void copyToClipboard(String text) => copied.add(text);
}

/// Drives a widget tree with a fake terminal.
class WidgetTester {
  /// A tester with nothing pumped yet.
  WidgetTester();

  AppHost? _host;
  Buffer? _buffer;
  Size _size = const Size(80, 24);

  /// Whether the app asked to exit since the last [pumpWidget].
  bool exitRequested = false;

  /// The app's terminal, as [TerminalScope] gives it, recording what it is
  /// asked.
  final terminal = TestTerminal();

  /// The app being tested; throws before [pumpWidget].
  AppHost get host => _host ?? (throw StateError('Call pumpWidget first.'));

  /// The app's focus manager.
  FocusManager get focusManager => host.focusManager;

  /// Total layout passes performed while synchronizing input geometry.
  int get inputLayoutPasses => host.owner.inputLayoutPasses;

  /// The size frames are drawn at.
  Size get size => _size;

  /// Mounts [widget] as the whole app and draws the first frame.
  Future<void> pumpWidget(
    Widget widget, {
    Size size = const Size(80, 24),
    KeyLayoutFallback? layoutFallback,
  }) async {
    _host?.dispose();
    exitRequested = false;
    _size = size;
    terminal.size = size;
    _host = AppHost(
      widget,
      onExit: () => exitRequested = true,
      layoutFallback: layoutFallback,
      terminal: terminal,
    );
    await pump();
  }

  /// Draws a frame, after waiting [duration] of real time when given.
  Future<void> pump([Duration? duration]) async {
    if (duration != null) await Future<void>.delayed(duration);
    await Future<void>.delayed(Duration.zero);
    _buffer = host.drawFrame(_size);
  }

  /// Presses keys written as in a binding: `ctrl+o`, `ctrl+x a`, `enter`.
  Future<void> press(String keys) async {
    for (final combo in Chord.parse(keys).combos) {
      host.handleKey(combo.toEvent());
    }
    await pump();
  }

  /// Sends [event] as it is built, as a terminal would: a press with a
  /// base-layout key, which [press] cannot spell.
  Future<void> sendKey(KeyEvent event) async {
    host.handleKey(event);
    await pump();
  }

  /// Types [text] one grapheme at a time.
  Future<void> type(String text) async {
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      host.handleKey(switch (ch) {
        ' ' => const KeyEvent('space'),
        '\n' => const KeyEvent('enter'),
        _ => KeyEvent(ch),
      });
    }
    await pump();
  }

  /// Dispatches a mouse report through current layout independently of focus.
  Future<void> mouse(MouseEvent event) async {
    host.handleMouse(event);
    await pump();
  }

  /// Pastes [text] as a terminal's bracketed paste would.
  Future<void> paste(String text) async {
    host.handlePaste(text);
    await pump();
  }

  /// Draws the next frames at [size].
  Future<void> resize(Size size) async {
    _size = size;
    terminal.size = size;
    await pump();
  }

  /// What the last frame shows; throws before [pumpWidget].
  Screen get screen =>
      Screen(_buffer ?? (throw StateError('Call pumpWidget first.')));

  /// Unmounts the app.
  void dispose() {
    _host?.dispose();
    _host = null;
  }
}

/// Runs a test with a [WidgetTester].
@isTest
void testWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  Object? skip,
}) {
  scaffolding.test(description, () async {
    final tester = WidgetTester();
    try {
      await body(tester);
    } finally {
      tester.dispose();
    }
  }, skip: skip);
}

/// Matches a [Screen] (or a string) that contains [pattern] on some row.
Matcher shows(Pattern pattern) => _Shows(pattern);

class _Shows extends Matcher {
  const _Shows(this.pattern);

  final Pattern pattern;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final text = item is Screen ? item.text : '$item';
    return text.contains(pattern);
  }

  @override
  Description describe(Description description) => description
      .add('a screen showing ')
      .addDescriptionOf(
        pattern is RegExp ? (pattern as RegExp).pattern : pattern,
      );

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) => mismatchDescription.add('the screen was:\n$item');
}
