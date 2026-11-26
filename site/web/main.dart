import 'package:chord_site/palette.dart';
import 'package:chord_site/router.dart';
import 'package:chord_site/screens.dart';
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
      Site(
        host: host,
        gallery: siteGallery,
        recordings: [for (final (name, _) in _recordings) name],
        lengths: {for (final (name, length) in _recordings) name: ?length},
      ),
      terminal: terminal,
      theme: siteTheme(),
      exitProcess: false,
      handleSignals: false,
    );
    host.push(const HomeRoute());
  }
}

/// The recordings the build shipped under recordings/, by name with their
/// lengths, as it passes them with -DCHORD_RECORDINGS (`start:9,team:12`).
final _recordings = [
  for (final entry in const String.fromEnvironment(
    'CHORD_RECORDINGS',
  ).split(','))
    if (entry.isNotEmpty) parseShot(entry),
];
