import 'dart:async';
import 'dart:js_interop';

import '../foundation/geometry.dart';
import '../terminal/host_terminal.dart';

/// The page's terminal as [WebTerminal] reads it: a terminal emulator on the
/// page, wterm or xterm.js, behind these five members.
extension type _PageTerminal._(JSObject _) implements JSObject {
  external int get cols;
  external int get rows;
  external void write(String data);
  external void onData(JSFunction callback);
  external void onResize(JSFunction callback);
}

@JS('chordTerminal')
external JSObject? get _chordTerminal;

@JS('navigator.clipboard.writeText')
external JSPromise<JSAny?> _writeClipboard(String text);

@JS('window.open')
external JSObject? _openWindow(String url, String target, String features);

@JS('document.title')
external set _documentTitle(String title);

/// A [HostTerminal] over a terminal emulator on a web page, for a chord_tui
/// app compiled to Wasm or JavaScript.
///
/// The page object has `cols` and `rows`, `write(data)`, `onData(callback)`
/// calling back with what the visitor typed, and `onResize(callback)`
/// calling back with the new columns and rows. The clipboard, links and
/// the title go to the browser: `navigator.clipboard`, `window.open` and
/// `document.title`. The bell is silent.
class WebTerminal extends HostTerminal {
  WebTerminal._(
    _PageTerminal page,
    Stream<String> input,
    Size Function() size,
    Stream<Size> resizes, {
    required super.mouse,
  }) : super(
         write: (data) => page.write(data),
         input: input,
         size: size,
         resizes: resizes,
       );

  /// Binds [host], or the page's `globalThis.chordTerminal` when null.
  /// With [mouse] the app gets pointer reports, and the visitor's own
  /// selection waits for Shift. Throws a [StateError] when there is no
  /// page terminal.
  factory WebTerminal({bool mouse = false, JSObject? host}) {
    final found = host ?? _chordTerminal;
    if (found == null) {
      throw StateError('The page has no chordTerminal to draw in.');
    }
    final page = found as _PageTerminal;
    final input = StreamController<String>.broadcast();
    final resizes = StreamController<Size>.broadcast();
    var size = Size(page.cols, page.rows);
    page.onData(((String data) => input.add(data)).toJS);
    page.onResize(
      ((int cols, int rows) {
        size = Size(cols, rows);
        resizes.add(size);
      }).toJS,
    );
    return WebTerminal._(
      page,
      input.stream,
      () => size,
      resizes.stream,
      mouse: mouse,
    );
  }

  @override
  void copyToClipboard(String text) => _writeClipboard(text).toDart.ignore();

  @override
  Future<String?> openUrl(String url) async {
    // With noopener the browser returns no window, opened or blocked alike.
    _openWindow(url, '_blank', 'noopener');
    return null;
  }

  @override
  void setTitle(String title) => _documentTitle = title;

  @override
  void bell() {}
}
