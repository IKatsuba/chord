import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_site/web/browser_host.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/web.dart';

import 'gallery.dart';

Future<void> main() async {
  final terminal = WebTerminal(mouse: true); // reads globalThis.chordTerminal
  final host = BrowserHost(terminal);
  // The site never quits: a runApp that returns starts again at home. A
  // failure ends the loop, already said on the console.
  for (;;) {
    await runApp(
      Site(host: host, gallery: siteGallery, recordings: _recordings),
      terminal: terminal,
      exitProcess: false,
      handleSignals: false,
    );
    host.push(const HomeRoute());
  }
}

/// The recordings the build shipped under recordings/, by name, as it
/// passes them with -DCHORD_RECORDINGS.
final _recordings = [
  for (final name in const String.fromEnvironment(
    'CHORD_RECORDINGS',
  ).split(','))
    if (name.isNotEmpty) name,
];
