// The site in this terminal instead of a browser, for looking at screens in
// tmux before the web build: `dart run tool/terminal.dart [path]`. History
// is kept in memory; F2 goes back, F3 forward, and links are not opened.
import 'dart:async';
import 'dart:io';

import 'package:chord_site/host.dart';
import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';

import '../web/gallery.dart';

class _MemoryHost extends SiteHost {
  _MemoryHost(this.initialPath) : _entries = [initialPath];

  @override
  final String initialPath;

  final List<String> _entries;
  var _at = 0;
  final _pops = StreamController<String>.broadcast();

  @override
  Stream<String> get pops => _pops.stream;

  @override
  void push(SiteRoute route) {
    _entries
      ..removeRange(_at + 1, _entries.length)
      ..add(route.path);
    _at++;
  }

  @override
  void show(SiteRoute route) {}

  @override
  void openUrl(String url) {}

  // The files the site build ships, read where tool/screenshots.dart wrote
  // them.
  @override
  Future<String?> recording(String file) async {
    final read = File('../docs/images/$file');
    return read.existsSync() ? read.readAsString() : null;
  }

  void move(int by) {
    final to = _at + by;
    if (to < 0 || to >= _entries.length) return;
    _at = to;
    _pops.add(_entries[_at]);
  }
}

Future<void> main(List<String> args) async {
  final host = _MemoryHost(args.isEmpty ? '/' : args.first);
  final terminal = StdioTerminal(mouse: true);
  await runApp(
    Builder(
      builder: (context) => Actions(
        bindings: [
          // Listed in the ? panel only, so the help row reads as in the
          // browser.
          Binding('f2', 'back', () => host.move(-1), id: '${panelOnly}back'),
          Binding(
            'f3',
            'forward',
            () => host.move(1),
            id: '${panelOnly}forward',
          ),
          // The site keeps Ctrl+Q and Ctrl+C for home; this ends the run.
          Binding(
            'ctrl+x',
            'leave',
            () => exitApp(context),
            id: '${panelOnly}leave',
          ),
        ],
        child: Site(
          host: host,
          gallery: siteGallery,
          recordings: _recordings(),
        ),
      ),
    ),
    terminal: terminal,
  );
}

/// The shots tool/screenshots.dart recorded, by name.
List<String> _recordings() {
  final images = Directory('../docs/images');
  if (!images.existsSync()) return const [];
  return [
    for (final file in images.listSync())
      if (file.path.endsWith('.120x36.rec.json'))
        file.uri.pathSegments.last.replaceFirst('.120x36.rec.json', ''),
  ]..sort();
}
