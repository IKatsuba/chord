import 'package:chord_tui/chord_tui.dart';

import 'palette.dart';
import 'router.dart';

/// The four sections the nav names, by digit: their label, the route a
/// digit opens, and whether a route is inside the section.
final sections =
    <({String label, SiteRoute route, bool Function(SiteRoute) holds})>[
      (
        label: 'chord',
        route: const ChordRoute(),
        holds: (r) => r is ChordRoute || r is RecordingRoute,
      ),
      (
        label: 'chord_tui',
        route: const ChordTuiRoute(),
        holds: (r) => r is ChordTuiRoute || r is ExampleRoute,
      ),
      (
        label: 'Gallery',
        route: const GalleryRoute(),
        holds: (r) => r is GalleryRoute,
      ),
      (
        label: 'Install',
        route: const InstallRoute(),
        holds: (r) => r is InstallRoute,
      ),
    ];

/// Rows the nav takes, its rule included: three and a rule on a desktop,
/// one and a rule on a phone.
int navRows({required bool narrow}) => narrow ? 2 : 4;

/// The site's nav: the mark, the four sections with the current one marked,
/// and on the right the GitHub link (from [wideWidth] columns) and the
/// version; on a phone, the mark and the menu. Tapping a part opens it.
class SiteNav extends StatelessWidget {
  /// The nav for [route], [width] columns wide.
  const SiteNav({
    super.key,
    required this.route,
    required this.width,
    required this.narrow,
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

  /// Whether it is laid out for a phone.
  final bool narrow;

  /// Whether the GitHub link fits.
  final bool wide;

  /// The version, as the nav writes it.
  final String version;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  /// Opens the phone's menu.
  final void Function() menu;

  /// The binding id that opens GitHub, which the link shows the key of.
  final String githubAction;

  /// The binding id that opens the phone's menu.
  final String menuAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface =
        (theme.extension<SitePalette>() ?? const SitePalette()).surface;
    final mark = _tap(
      () => open(const HomeRoute()),
      Text.rich(
        TextSpan(
          '',
          children: [
            TextSpan('◆ ', style: theme.accent),
            TextSpan('chord', style: theme.text.merge(Style.bold)),
          ],
        ),
        softWrap: false,
      ),
    );
    final Widget row;
    if (narrow) {
      final key = Actions.maybeBindingOf(context, menuAction)?.chord;
      row = Row(
        children: [
          Text('  '),
          mark,
          const Spacer(),
          _tap(
            menu,
            Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan('☰ menu', style: theme.text),
                  if (key != null) TextSpan(' $key', style: theme.dim),
                ],
              ),
              softWrap: false,
            ),
          ),
          Text('  '),
        ],
      );
    } else {
      row = Row(
        children: [
          Text('  '),
          mark,
          Text('    '),
          for (final (i, s) in sections.indexed) ...[
            if (i > 0) Text('   '),
            _tap(
              () => open(s.route),
              Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan('${i + 1} ', style: theme.dim),
                    TextSpan(
                      s.label,
                      style: s.holds(route)
                          ? theme.accent.merge(
                              const Style(bold: true, underline: true),
                            )
                          : theme.text,
                    ),
                  ],
                ),
                softWrap: false,
              ),
            ),
          ],
          const Spacer(),
          if (wide) ...[
            Link('GitHub', action: githubAction, external: true),
            Text('   '),
          ],
          Text(version, style: theme.dim, softWrap: false),
          Text('  '),
        ],
      );
    }
    final blank = Text('');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Box(
          background: surface,
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: narrow ? [row] : [blank, row, blank],
          ),
        ),
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

/// The phone's menu, open under the nav: the four sections, numbered, and
/// GitHub; [selected] is marked, the current section is mint, and a tap
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
    final palette = (theme.extension<SitePalette>() ?? const SitePalette());
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
          background: palette.surface,
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(''),
              for (final (i, s) in sections.indexed)
                row(i, [
                  TextSpan('${i + 1} ', style: theme.dim),
                  TextSpan(
                    s.label,
                    style: s.holds(route)
                        ? theme.accent.merge(Style.bold)
                        : i == selected
                        ? theme.text.merge(Style.bold)
                        : theme.text,
                  ),
                ]),
              row(sections.length, [
                TextSpan('  '),
                TextSpan('GitHub ↗', style: theme.link.merge(Style.underline)),
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
