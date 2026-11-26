import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import 'host.dart';
import 'key_row.dart';
import 'pages/home.dart';
import 'pages/not_found.dart';
import 'pages/stub.dart';
import 'router.dart';
import 'version.dart';

/// Below this many columns the site is laid out for a phone.
const narrowWidth = 60;

/// Below this many columns the header's link moves under the name.
const wideWidth = 100;

const _homeKeysId = 'site:home-keys';
const _repositoryId = 'site:repository';

/// The whole site: a header, the page the route names, and its keys.
///
/// Opening a page pushes its path through [host]; Back and Forward come
/// back as paths. Esc goes up a level, `?` lists every key, and Ctrl+Q or
/// Ctrl+C go home: the site never ends.
class Site extends StatefulWidget {
  /// The site on [host], with the pages [router] knows.
  const Site({super.key, required this.host, this.router = siteRouter});

  /// The page the site runs on.
  final SiteHost host;

  /// The routes.
  final SiteRouter router;

  @override
  State<Site> createState() => _SiteState();
}

class _SiteState extends State<Site> {
  late SiteRoute _route;
  var _keysOpen = false;
  StreamSubscription<String>? _pops;

  @override
  void initState() {
    super.initState();
    _route = widget.router.parse(widget.host.initialPath);
    widget.host.show(_route);
    _pops = widget.host.pops.listen((path) {
      final route = widget.router.parse(path);
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
      final home = _route is HomeRoute;
      return Actions(
        bindings: [
          Binding(
            'esc',
            _keysOpen ? 'close' : (_route is NotFoundRoute ? 'home' : 'up'),
            _escape,
            enabled: _keysOpen || !home,
          ),
          Binding('?', 'keys', () => setState(() => _keysOpen = !_keysOpen)),
          Binding(
            'g',
            'open GitHub',
            () => widget.host.openUrl(repositoryUrl),
            id: _repositoryId,
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
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._header(context, width),
            Expanded(child: _page()),
            if (_keysOpen) _KeysPanel(width: width),
            if (narrow) const KeyRow(),
            _HelpRow(narrow: narrow),
          ],
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
    final version = Text('v$chordVersion ', style: theme.dim);
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
    ChordTuiRoute() => const StubPage(
      'chord_tui',
      "What chord_tui is, and README's example.",
    ),
    GalleryRoute() => const StubPage(
      'Gallery',
      "The framework's examples, running here.",
    ),
    ExampleRoute(:final name) => StubPage(name, 'One example, running.'),
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

/// The keys in scope on one row: on a phone only Esc and `?`; never the
/// keys that only repeat home or the header's link.
class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final theme = Theme.of(context);
      final spans = <TextSpan>[TextSpan(' ')];
      for (final group in groupBindings(bindings)) {
        if (group.id == _homeKeysId || group.id == _repositoryId) continue;
        if (narrow &&
            !(group.chords.first.toString() == 'escape' ||
                group.chords.first.toString() == '?')) {
          continue;
        }
        if (spans.length > 1) spans.add(TextSpan('  '));
        spans
          ..add(
            TextSpan(
              group.chords.join('/'),
              style: theme.text.merge(Style.bold),
            ),
          )
          ..add(TextSpan(' ${group.description}', style: theme.dim));
      }
      return Text.rich(TextSpan('', children: spans), softWrap: false);
    },
  );
}

/// Every key in scope, one action a row, under the page.
class _KeysPanel extends StatelessWidget {
  const _KeysPanel({required this.width});

  final int width;

  @override
  Widget build(BuildContext context) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final theme = Theme.of(context);
      final groups = groupBindings(bindings);
      final keyWidth = groups.fold(
        0,
        (w, g) => g.chords.join('/').length > w ? g.chords.join('/').length : w,
      );
      return Column(
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
        ],
      );
    },
  );
}
