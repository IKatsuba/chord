import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/web.dart';

void main() => runApp(
  const Site(),
  terminal: WebTerminal(mouse: true), // reads globalThis.chordTerminal
  exitProcess: false,
  handleSignals: false,
);
