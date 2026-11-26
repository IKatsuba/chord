import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import 'gallery.dart';
import 'host.dart';
import 'key_row.dart';
import 'pages/chord_tui.dart';
import 'pages/gallery.dart';
import 'pages/home.dart';
import 'pages/not_found.dart';
import 'pages/stub.dart';
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

  static final _f1 = KeyCombo.parse('f1');
  static final _esc = KeyCombo.parse('esc');
  static final _question = KeyCombo.parse('?');
  static final _quits = {KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')};

  // Above every page and before any example's own handlers: F1 opens the
  // panel anywhere, and the open panel decides every key.
  bool _capture(KeyEvent event) {
    final key = event.combo;
    if (!_keysOpen) {
      if (key != _f1) return false;
      setState(() => _keysOpen = true);
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
      // The page's rows: the window less the header (two rows, three where
      // the link folds under the name), the key row and the help row.
      final headerRows = width >= narrowWidth && width < wideWidth ? 3 : 2;
      final pageRows =
          constraints.maxHeight - headerRows - (narrow ? 1 : 0) - 1;
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
        ],
        child: Focus(
          canRequestFocus: false,
          onKeyCapture: _capture,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One child whatever the width, so the page after it keeps its
              // place, and its state, across a resize.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _header(context, width),
              ),
              Expanded(
                child: Stack(
                  children: [
                    _page(),
                    // The open panel sits at the bottom of the page, and stops
                    // clicks and the wheel short of it.
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
                              _KeysPanel(width: width, rows: pageRows),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (narrow) const KeyRow(),
              _HelpRow(
                narrow: narrow,
                embedding: _embedding,
                panelOpen: _keysOpen,
              ),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _header(BuildContext context, int width) {
    final theme = Theme.of(context);
    final link = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.host.openUrl(repositoryUrl),
      child: Text(
        repositoryUrl.replaceFirst('https://', ''),
        style: theme.link,
      ),
    );
    // Only a real version number reads with a v in front.
    final version = Text(
      chordVersion == 'dev' ? 'dev ' : 'v$chordVersion ',
      style: theme.dim,
    );
    final name = Text(
      ' ${_crumbs(_route)}',
      style: theme.text.merge(Style.bold),
      softWrap: false,
    );
    return [
      Row(
        children: [
          Expanded(child: name),
          if (width >= wideWidth) ...[link, Text('   ')],
          version,
        ],
      ),
      if (width >= narrowWidth && width < wideWidth)
        Row(children: [Text(' '), link]),
      Text('─' * width, style: theme.dim),
    ];
  }

  Widget _page() => switch (_route) {
    HomeRoute() => HomePage(_open),
    ChordRoute() => const StubPage('chord', 'What chord is, and its screens.'),
    RecordingRoute(:final name) => StubPage(name, 'A recording of chord.'),
    ChordTuiRoute() => ChordTuiPage(_gallery.readme, _open),
    GalleryRoute() => GalleryPage(_gallery, _open),
    ExampleRoute(:final name) => ExamplePage(
      _gallery[name]!,
      () => _open(const HomeRoute()),
    ),
    InstallRoute() => const StubPage('Install', 'Homebrew, npm, from source.'),
    NotFoundRoute(:final path) => NotFoundPage(
      path,
      () => _open(const HomeRoute()),
    ),
  };
}

/// The header's name for [route]: chord, then the route's segments.
String _crumbs(SiteRoute route) {
  if (route is HomeRoute || route is NotFoundRoute) return 'chord';
  final segments = route.path.substring(1).split('/');
  return [if (segments.first != 'chord') 'chord', ...segments].join(' › ');
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
  });

  final bool narrow;
  final bool embedding;
  final bool panelOpen;

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

      if (panelOpen) {
        for (final (keys, description)
            in narrow ? _whileOpen.take(1) : _whileOpen) {
          entry(keys, description);
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

/// Every key in scope, one action a row, the site's first, in at most
/// [rows] rows: what does not fit is counted on the last.
class _KeysPanel extends StatelessWidget {
  const _KeysPanel({required this.width, required this.rows});

  final int width;
  final int rows;

  @override
  Widget build(BuildContext context) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final theme = Theme.of(context);
      // The site's own keys first, so a page with more keys than rows never
      // hides the way out of the panel.
      bool own(BindingGroup g) =>
          (g.id ?? '').startsWith(siteKeys) ||
          (g.id ?? '').startsWith(panelOnly);
      final grouped = groupBindings(bindings);
      final all = [...grouped.where(own), ...grouped.where((g) => !own(g))];
      // The rule and the title take two rows; a count of the rest one more.
      final room = rows - 2;
      final groups = all.length <= room
          ? all
          : all.take(room < 1 ? 0 : room - 1).toList();
      final keyWidth = groups.fold(
        0,
        (w, g) => g.chords.join('/').length > w ? g.chords.join('/').length : w,
      );
      // Filled, so nothing of the page under it shows through.
      return Box(
        background: Style.plain,
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('─' * width, style: theme.dim),
            Text(' Keys', style: theme.text.merge(Style.bold)),
            for (final group in groups)
              Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan(
                      '   ${group.chords.join('/').padRight(keyWidth)}  ',
                      style: theme.text.merge(Style.bold),
                    ),
                    TextSpan(group.description, style: theme.dim),
                  ],
                ),
                softWrap: false,
              ),
            if (groups.length < all.length && room >= 1)
              Text(
                '   … +${all.length - groups.length} more',
                style: theme.dim,
              ),
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
