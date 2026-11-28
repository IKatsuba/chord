/// A chord_tui app in a browser: compiled to Wasm and drawn by a terminal
/// emulator on the page.
///
/// ```dart
/// import 'package:chord_tui/chord_tui.dart';
/// import 'package:chord_tui/web.dart';
///
/// void main() => runApp(
///   const App(),
///   terminal: WebTerminal(mouse: true),
///   exitProcess: false,
///   handleSignals: false,
/// );
/// ```
library;

export 'src/terminal/host_terminal.dart';
export 'src/web/web_terminal.dart';
