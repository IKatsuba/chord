import 'package:chord_tui/chord_tui.dart';

import 'router.dart';

/// The four sections the nav names, by digit: their caps label, the route a
/// digit opens, and whether a route is inside the section.
final sections =
    <({String label, SiteRoute route, bool Function(SiteRoute) holds})>[
      (
        label: 'APP',
        route: const ChordRoute(),
        holds: (r) => r is ChordRoute || r is RecordingRoute,
      ),
      (
        label: 'FRAMEWORK',
        route: const ChordTuiRoute(),
        holds: (r) => r is ChordTuiRoute || r is ExampleRoute,
      ),
      (
        label: 'GALLERY',
        route: const GalleryRoute(),
        holds: (r) => r is GalleryRoute,
      ),
      (
        label: 'INSTALL',
        route: const InstallRoute(),
        holds: (r) => r is InstallRoute,
      ),
    ];

/// Rows the nav takes, at every width: a blank row, its line, a blank row
/// and a rule.
const navRows = 4;

const _mark = 'CHORD / CHORD_TUI';
const _margin = 2;
const _sectionGap = 4;

/// The columns the sections' line takes: `01 APP` and the rest, apart.
int get _sectionsWidth {
  var w = 0;
  for (final s in sections) {
    w += 3 + s.label.length;
  }
  return w + _sectionGap * (sections.length - 1);
}

/// Whether the nav at [width] columns shows `MENU m` in place of its
/// sections: on a phone, or wherever the mark, the sections and [version]
/// do not fit on one line.
bool navFolds(int width, String version, {required bool narrow}) =>
    narrow ||
    _margin +
            _mark.length +
            _sectionGap +
            _sectionsWidth +
            _sectionGap +
            version.length +
            _margin >
        width;

/// Whether `GITHUB ↗ g` fits beside the sections and [version] at [width]
/// columns: from [wide] columns, and only where it does.
bool navShowsGithub(int width, String version, {required int wide}) =>
    width >= wide &&
    _margin +
            _mark.length +
            _sectionGap +
            _sectionsWidth +
            _sectionGap +
            'GITHUB ↗ g'.length +
            _sectionGap +
            version.length +
            _margin <=
        width;

/// The site's nav, in caps: `CHORD / CHORD_TUI` on the left, and on the
/// right the numbered sections with the current one ink on cream, GitHub
/// (when [wide]) and the version; or `MENU m` when [folded]. Tapping a part
/// opens it.
class SiteNav extends StatelessWidget {
  /// The nav for [route], [width] columns wide.
  const SiteNav({
    super.key,
    required this.route,
    required this.width,
    required this.folded,
    required this.wide,
    required this.version,
    required this.open,
    required this.menu,
    required this.githubAction,
    required this.menuAction,
  });

  /// The page shown.
  final SiteRoute route;

  /// The window's columns.
  final int width;

  /// Whether the sections fold into `MENU m`.
  final bool folded;

  /// Whether the GitHub link fits.
  final bool wide;

  /// The version, as the nav writes it, in caps.
  final String version;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  /// Opens the menu.
  final void Function() menu;

  /// The binding id that opens GitHub, which the link shows the key of.
  final String githubAction;

  /// The binding id that opens the menu.
  final String menuAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bold = theme.text.merge(Style.bold);
    final accent = theme.accent.merge(Style.bold);
    final mark = _tap(
      () => open(const HomeRoute()),
      Text.rich(
        TextSpan(
          '',
          children: [
            TextSpan('CHORD', style: bold),
            TextSpan(' / ', style: accent),
            TextSpan('CHORD_TUI', style: bold),
          ],
        ),
        softWrap: false,
      ),
    );
    final List<Widget> right;
    if (folded) {
      final key = Actions.maybeBindingOf(context, menuAction)?.chord;
      right = [
        _tap(
          menu,
          Text.rich(
            TextSpan(
              '',
              children: [
                TextSpan('MENU', style: bold),
                if (key != null) TextSpan(' $key', style: accent),
              ],
            ),
            softWrap: false,
          ),
        ),
      ];
    } else {
      right = [
        for (final (i, s) in sections.indexed) ...[
          if (i > 0) Text(' ' * _sectionGap),
          _tap(
            () => open(s.route),
            Text.rich(
              TextSpan(
                '',
                // The current section is ink on cream.
                style: s.holds(route) ? const Style(inverse: true) : null,
                children: [
                  TextSpan('0${i + 1} ', style: accent),
                  TextSpan(s.label, style: bold),
                ],
              ),
              softWrap: false,
            ),
          ),
        ],
        if (wide) ...[
          Text(' ' * _sectionGap),
          Link('GITHUB', action: githubAction, external: true),
        ],
        Text(' ' * _sectionGap),
        Text(version, style: theme.dim, softWrap: false),
      ];
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(''),
        Row(
          children: [
            Text(' ' * _margin),
            mark,
            const Spacer(),
            ...right,
            Text(' ' * _margin),
          ],
        ),
        Text(''),
        Text('─' * width, style: theme.border, softWrap: false),
      ],
    );
  }

  static Widget _tap(void Function() onTap, Widget child) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (event.button == MouseButton.primary) onTap();
    },
    child: child,
  );
}

/// The menu, open under the nav: the four sections, numbered, and GitHub,
/// in caps; [selected] is marked, the current section is green, and a tap
/// on a row chooses it.
class NavMenu extends StatelessWidget {
  /// The menu for [route], [width] columns wide.
  const NavMenu({
    super.key,
    required this.width,
    required this.route,
    required this.selected,
    required this.choose,
    required this.githubAction,
  });

  /// The window's columns.
  final int width;

  /// The page shown.
  final SiteRoute route;

  /// The marked row: 0–3 the sections, 4 GitHub.
  final int selected;

  /// Chooses a row.
  final void Function(int row) choose;

  /// The binding id that opens GitHub, which its row shows the key of.
  final String githubAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.accent.merge(Style.bold);
    Widget row(int i, List<TextSpan> spans) => SiteNav._tap(
      () => choose(i),
      Text.rich(
        TextSpan(
          '',
          children: [
            TextSpan(i == selected ? ' ❯ ' : '   ', style: theme.accent),
            ...spans,
          ],
        ),
        softWrap: false,
      ),
    );
    final key = Actions.maybeBindingOf(context, githubAction)?.chord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Box(
          // The page under it never shows through.
          background: Style.plain,
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(''),
              for (final (i, s) in sections.indexed)
                row(i, [
                  TextSpan('0${i + 1} ', style: accent),
                  TextSpan(
                    s.label,
                    style: s.holds(route)
                        ? theme.accent.merge(Style.bold)
                        : theme.text.merge(Style.bold),
                  ),
                ]),
              row(sections.length, [
                TextSpan('   '),
                TextSpan('GITHUB ↗', style: theme.link.merge(Style.underline)),
                if (key != null) TextSpan(' $key', style: theme.dim),
              ]),
              Text(''),
            ],
          ),
        ),
        Text('─' * width, style: theme.border, softWrap: false),
      ],
    );
  }
}
