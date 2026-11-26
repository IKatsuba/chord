import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import 'gallery.dart';
import 'host.dart';
import 'key_row.dart';
import 'keys_panel.dart';
import 'nav.dart';
import 'palette.dart';
import 'pages/chord.dart';
import 'pages/chord_tui.dart';
import 'pages/gallery.dart';
import 'pages/home.dart';
import 'pages/install.dart';
import 'pages/not_found.dart';
import 'pages/recording.dart';
import 'router.dart';
import 'version.dart';

/// Below this many columns the site is laid out for a phone.
const narrowWidth = 60;

/// Below this many columns the header's link moves under the name.
const wideWidth = 100;

/// The id prefix of bindings the `?` panel lists and the help row leaves
/// out.
const panelOnly = 'panel:';

/// The id prefix of the site's own bindings: on a page that runs an
/// example, the help row lists these alone.
const siteKeys = 'site:';

const _homeKeysId = '${siteKeys}home';
const _repositoryId = '${panelOnly}repository';
const _menuId = '${siteKeys}menu';

/// The whole site: a header, the page the route names, and its keys.
///
/// Opening a page pushes its path through [host]; Back and Forward come
/// back as paths. Esc goes up a level, F1 (and `?` outside example pages,
/// where it is typed text) lists every key, and Ctrl+Q or Ctrl+C go home:
/// the site never ends. While the keys panel is open it takes every key
/// and pointer report: Esc and F1 close it, Ctrl+Q and Ctrl+C close it and
/// go home, and nothing else reaches the page.
class Site extends StatefulWidget {
  /// The site on [host], running [gallery]'s examples and showing
  /// [recordings] by name.
  const Site({
    super.key,
    required this.host,
    this.gallery,
    this.recordings = const [],
  });

  /// The page the site runs on.
  final SiteHost host;

  /// The framework's examples; none when null.
  final Gallery? gallery;

  /// The names of chord's recordings that have pages.
  final List<String> recordings;

  @override
  State<Site> createState() => _SiteState();
}

class _SiteState extends State<Site> {
  late final Gallery _gallery = widget.gallery ?? Gallery.none;
  late final _router = SiteRouter(
    recordings: widget.recordings,
    examples: [for (final entry in _gallery.entries) entry.name],
  );
  late SiteRoute _route;
  var _keysOpen = false;
  // The keys panel's scroll, and what clamps it: its entries, as it last
  // drew them, and the page's rows.
  var _panelOffset = 0;
  var _panelEntries = 0;
  var _pageRows = 0;
  StreamSubscription<String>? _pops;

  @override
  void initState() {
    super.initState();
    _route = _router.parse(widget.host.initialPath);
    widget.host.show(_route);
    _pops = widget.host.pops.listen((path) {
      final route = _router.parse(path);
      widget.host.show(route);
      setState(() {
        _route = route;
        _keysOpen = false;
      });
    });
  }

  @override
  void dispose() {
    _pops?.cancel();
    super.dispose();
  }

  void _open(SiteRoute route) {
    if (route == _route) return;
    widget.host.push(route);
    setState(() {
      _route = route;
      _keysOpen = false;
    });
  }

  bool get _embedding => _route is ExampleRoute || _route is ChordTuiRoute;

  // The phone's menu: the four sections and GitHub, over the page.
  var _menuOpen = false;
  var _menuSelected = 0;

  void _openMenu() => setState(() {
    _menuOpen = true;
    _menuSelected = 0;
  });

  void _menuChoose(int row) {
    setState(() => _menuOpen = false);
    if (row < sections.length) {
      _open(sections[row].route);
    } else {
      widget.host.openUrl(repositoryUrl);
    }
  }

  static final _menuKeys = {
    for (final key in ['esc', 'm', 'up', 'down', 'enter', 'g'])
      KeyCombo.parse(key): key,
    for (var n = 1; n <= 4; n++) KeyCombo.parse('$n'): '$n',
  };

  // While the menu is open it takes every key, as the keys panel does.
  bool _captureMenu(KeyCombo key) {
    final rows = sections.length + 1;
    switch (_menuKeys[key]) {
      case 'esc' || 'm':
        setState(() => _menuOpen = false);
      case 'up':
        setState(() => _menuSelected = (_menuSelected - 1).clamp(0, rows - 1));
      case 'down':
        setState(() => _menuSelected = (_menuSelected + 1).clamp(0, rows - 1));
      case 'enter':
        _menuChoose(_menuSelected);
      case 'g':
        _menuChoose(sections.length);
      case final String digit:
        _menuChoose(int.parse(digit) - 1);
      case null:
    }
    return true;
  }

  static final _f1 = KeyCombo.parse('f1');
  static final _esc = KeyCombo.parse('esc');
  static final _question = KeyCombo.parse('?');
  static final _quits = {KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')};
  static final _scrolls = {
    for (final key in ['up', 'down', 'pageup', 'pagedown', 'home', 'end'])
      KeyCombo.parse(key): key,
  };

  void _scrollPanel(String key) {
    final most = panelMaxOffset(entries: _panelEntries, rows: _pageRows);
    final page = (_pageRows - 3).clamp(1, _pageRows);
    final to = switch (key) {
      'up' => _panelOffset - 1,
      'down' => _panelOffset + 1,
      'pageup' => _panelOffset - page,
      'pagedown' => _panelOffset + page,
      'home' => 0,
      _ => most,
    };
    setState(() => _panelOffset = to.clamp(0, most));
  }

  // Above every page and before any example's own handlers: F1 opens the
  // panel anywhere, and the open panel decides every key.
  bool _capture(KeyEvent event) {
    final key = event.combo;
    if (_menuOpen) return _captureMenu(key);
    if (!_keysOpen) {
      if (key != _f1) return false;
      setState(() {
        _keysOpen = true;
        _panelOffset = 0;
      });
      return true;
    }
    if (_scrolls[key] case final scroll?) {
      _scrollPanel(scroll);
      return true;
    }
    if (key == _esc || key == _f1 || (!_embedding && key == _question)) {
      setState(() => _keysOpen = false);
    } else if (_quits.contains(key)) {
      setState(() => _keysOpen = false);
      _open(const HomeRoute());
    }
    return true;
  }

  void _escape() {
    if (_keysOpen) {
      setState(() => _keysOpen = false);
    } else {
      _open(_route.parent);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final narrow = width < narrowWidth;
      // A phone the window has grown out of has no menu.
      if (!narrow && _menuOpen) _menuOpen = false;
      // The page's rows: the window less the nav, the key row and the help
      // row.
      final pageRows =
          constraints.maxHeight -
          navRows(narrow: narrow) -
          (narrow ? 1 : 0) -
          1;
      _pageRows = pageRows;
      final home = _route is HomeRoute;
      return Actions(
        bindings: [
          Binding(
            'esc',
            _keysOpen ? 'close' : (_route is NotFoundRoute ? 'home' : 'up'),
            _escape,
            enabled: _keysOpen || !home,
            id: '${siteKeys}escape',
          ),
          // Quit means home; on home these do nothing, and never end the
          // program.
          for (final key in ['ctrl+q', 'ctrl+c'])
            Binding(
              key,
              'home',
              () => _open(const HomeRoute()),
              id: _homeKeysId,
            ),
          // On a page that runs an example, ? is text the example may take.
          for (final key in ['?', 'f1'])
            Binding(
              key,
              'keys',
              () => setState(() => _keysOpen = !_keysOpen),
              enabled: key == 'f1' || !_embedding,
              id: '${siteKeys}keys',
            ),
          Binding(
            'g',
            'open GitHub',
            () => widget.host.openUrl(repositoryUrl),
            id: _repositoryId,
          ),
          // Inside a running example digits and m are its typed text.
          for (final (i, s) in sections.indexed)
            Binding(
              '${i + 1}',
              'section',
              () => _open(s.route),
              enabled: !_embedding,
              // The nav shows the digits; the help row leaves them to the panel.
              id: '${panelOnly}sections',
            ),
          Binding(
            'm',
            'menu',
            _openMenu,
            enabled: narrow && !_embedding,
            id: _menuId,
          ),
        ],
        child: Focus(
          canRequestFocus: false,
          onKeyCapture: _capture,
          // A paste while the panel is open goes nowhere, like its keys.
          onPasteCapture: (_) => _keysOpen || _menuOpen,
          // The page comes before the nav in the tree: with nothing focused,
          // keys go to the first focusable place, which must be the page's,
          // not the nav's GitHub link.
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The nav's rows; it is drawn over them, after the page.
                  SizedBox(height: navRows(narrow: narrow)),
                  Expanded(
                    // The window's width, not the page's: the panel over it
                    // spans the window.
                    child: SizedBox(
                      width: width,
                      child: Stack(
                        children: [
                          _page(width, pageRows),
                          // The open panel sits at the bottom of the page, and stops
                          // clicks and the wheel short of it.
                          if (_menuOpen)
                            Positioned(
                              left: 0,
                              top: 0,
                              right: 0,
                              bottom: 0,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                absorbPointerSignal: true,
                                onPointerDown: (_) {},
                                onPointerSignal: (_) {},
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    NavMenu(
                                      width: width,
                                      route: _route,
                                      selected: _menuSelected,
                                      choose: _menuChoose,
                                      githubAction: _repositoryId,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_keysOpen)
                            Positioned(
                              left: 0,
                              top: 0,
                              right: 0,
                              bottom: 0,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                absorbPointerSignal: true,
                                onPointerDown: (_) {},
                                onPointerSignal: (_) {},
                                child: Column(
                                  children: [
                                    const Spacer(),
                                    _KeysPanel(
                                      width: width,
                                      rows: pageRows,
                                      offset: _panelOffset,
                                      drawn: (entries) =>
                                          _panelEntries = entries,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (narrow)
                    KeyRow(
                      panArrows:
                          _route is RecordingRoute &&
                          recordingClipped(width, pageRows),
                    ),
                  // On the surface colour on a desktop; a phone's sits under its
                  // key row.
                  Box(
                    background: narrow
                        ? null
                        : (Theme.of(context).extension<SitePalette>() ??
                                  const SitePalette())
                              .surface,
                    width: width,
                    child: _HelpRow(
                      narrow: narrow,
                      embedding: _embedding,
                      panelOpen: _keysOpen,
                      menuOpen: _menuOpen,
                      pageRows: pageRows,
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                child: SiteNav(
                  route: _route,
                  width: width,
                  narrow: narrow,
                  wide: width >= wideWidth,
                  // Only a real version number reads with a v in front.
                  version: chordVersion == 'dev' ? 'dev' : 'v$chordVersion',
                  open: _open,
                  menu: _openMenu,
                  githubAction: _repositoryId,
                  menuAction: _menuId,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _page(int width, int rows) => switch (_route) {
    HomeRoute() => HomePage(_open),
    ChordRoute() => ChordPage(widget.recordings, _open),
    RecordingRoute(:final name) => RecordingPage(
      key: ValueKey(name),
      host: widget.host,
      name: name,
      cols: width,
      rows: rows,
    ),
    ChordTuiRoute() => ChordTuiPage(_gallery.readme, _open),
    GalleryRoute() => GalleryPage(_gallery, _open),
    ExampleRoute(:final name) => ExamplePage(
      _gallery[name]!,
      () => _open(const HomeRoute()),
    ),
    InstallRoute() => const InstallPage(),
    NotFoundRoute(:final path) => NotFoundPage(
      path,
      () => _open(const HomeRoute()),
    ),
  };
}

/// The keys in scope on one row, `…` where they overflow: on a phone only
/// Esc and `?`; never the [panelOnly] ones. On a page [embedding] an
/// example, only the site's own, Ctrl+Q home among them: the example's are
/// in its frame. Elsewhere home is left to the `?` panel.
class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.narrow,
    required this.embedding,
    required this.panelOpen,
    required this.menuOpen,
    required this.pageRows,
  });

  final bool narrow;
  final bool embedding;
  final bool panelOpen;
  final bool menuOpen;
  final int pageRows;

  // What the open panel lets through, which its capture decides; a phone
  // has no F1 or Ctrl to show.
  static const _whileOpen = [
    ('escape', 'close'),
    ('f1', 'close'),
    ('ctrl+q', 'home'),
  ];

  @override
  Widget build(BuildContext context) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final theme = Theme.of(context);
      final spans = <TextSpan>[TextSpan(' ')];
      void entry(String keys, String description) {
        if (spans.length > 1) spans.add(TextSpan('  '));
        spans
          ..add(TextSpan(keys, style: theme.text.merge(Style.bold)))
          ..add(TextSpan(' $description', style: theme.dim));
      }

      if (menuOpen) {
        entry('esc', 'close');
        return Text.rich(TextSpan('', children: spans), softWrap: false);
      }
      if (panelOpen) {
        for (final (keys, description)
            in narrow ? _whileOpen.take(1) : _whileOpen) {
          entry(keys, description);
        }
        final entries = panelEntries(bindings, [siteKeys, panelOnly]).length;
        if (panelWindow(
          entries: entries,
          rows: pageRows,
          offset: 0,
        ).overflows) {
          entry('up/down', 'scroll');
        }
        return Text.rich(
          TextSpan('', children: spans),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );
      }
      for (final group in groupBindings(bindings)) {
        final id = group.id ?? '';
        if (id.startsWith(panelOnly)) continue;
        if (embedding ? !id.startsWith(siteKeys) : id == _homeKeysId) {
          continue;
        }
        if (narrow &&
            !(group.chords.first.toString() == 'escape' ||
                group.chords.first.toString() == '?')) {
          continue;
        }
        // Ctrl+C is home too, and F1 keys where ? is: the row names the one
        // key to learn.
        final chords = id == _homeKeysId || id == '${siteKeys}keys'
            ? [group.chords.first.toString()]
            : [for (final chord in group.chords) chord.toString()];
        entry(keysLabel(chords), group.description);
      }
      return Text.rich(
        TextSpan('', children: spans),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    },
  );
}

/// Every key in scope, one action a row, the site's first, in [rows] rows
/// from [offset]: filled, so nothing of the page under it shows through.
class _KeysPanel extends StatelessWidget {
  const _KeysPanel({
    required this.width,
    required this.rows,
    required this.offset,
    required this.drawn,
  });

  final int width;
  final int rows;
  final int offset;

  /// Told how many entries there are, for the scroll keys to clamp to.
  final void Function(int entries) drawn;

  @override
  Widget build(BuildContext context) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final theme = Theme.of(context);
      final all = panelEntries(bindings, [siteKeys, panelOnly]);
      drawn(all.length);
      final window = panelWindow(
        entries: all.length,
        rows: rows,
        offset: offset,
      );
      final shown = all.sublist(window.first, window.first + window.count);
      String keys(BindingGroup g) =>
          keysLabel([for (final chord in g.chords) chord.toString()]);
      // Sized to every entry, so the descriptions stay put as it scrolls.
      final keyWidth = all.fold(
        0,
        (w, g) => keys(g).length > w ? keys(g).length : w,
      );
      return Box(
        background: Style.plain,
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (window.rule)
              Text('─' * width, style: theme.dim, softWrap: false),
            Text(' Keys', style: theme.text.merge(Style.bold)),
            if (window.above > 0)
              Text('   ↑ +${window.above} more', style: theme.dim),
            for (final group in shown)
              Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan(
                      '   ${keys(group).padRight(keyWidth)}  ',
                      style: theme.text.merge(Style.bold),
                    ),
                    TextSpan(group.description, style: theme.dim),
                  ],
                ),
                softWrap: false,
              ),
            if (window.below > 0)
              Text('   ↓ +${window.below} more', style: theme.dim),
          ],
        ),
      );
    },
  );
}

/// How a help row writes [chords]: a run of three or more digits in order
/// as a range, `1–9`; anything else joined by `/`.
String keysLabel(List<String> chords) {
  final digits = [for (final c in chords) int.tryParse(c)];
  final run =
      chords.length >= 3 &&
      chords.every((c) => c.length == 1) &&
      digits.every((d) => d != null) &&
      [for (var i = 1; i < digits.length; i++) digits[i]! == digits[i - 1]! + 1]
          .every((ok) => ok);
  return run ? '${chords.first}–${chords.last}' : chords.join('/');
}
