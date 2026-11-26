import 'package:chord_tui/chord_tui.dart';

import 'site.dart' show narrowWidth, panelOnly;

/// The measure of home and install, in columns.
const narrowMeasure = 124;

/// The measure of chord and the gallery, in columns.
const wideMeasure = 136;

/// The columns a [SitePage] in a window [width] columns wide gives its
/// sections: the window less the scrollbar and a gutter each side (4, or 2
/// on a phone), at most [measure].
int pageContentWidth(int width, {int measure = narrowMeasure}) =>
    (width - 1 - 2 * (width < narrowWidth ? 2 : 4)).clamp(1, measure);

/// A page of sections in one scrolling list beside a [Scrollbar], centred
/// in at most [measure] columns with a gutter each side (4, or 2 on a
/// phone); below the measure it runs edge to edge. ↑↓, PgUp/PgDn,
/// Home/End and the wheel scroll it.
class SitePage extends StatefulWidget {
  /// A page of [sections].
  const SitePage({
    super.key,
    required this.sections,
    this.measure = narrowMeasure,
    this.controller,
    this.bindings = const [],
  });

  /// The page's parts, top to bottom, each as wide as the measure.
  final List<Widget> sections;

  /// The widest the content gets.
  final int measure;

  /// The page's scroll, for a page that moves it itself; one of its own
  /// when null.
  final ScrollController? controller;

  /// The page's own keys, which win over its scroll keys: a grid's arrows.
  final List<Binding> bindings;

  @override
  State<SitePage> createState() => _SitePageState();
}

class _SitePageState extends State<SitePage> {
  ScrollController? _own;
  ScrollController get _scroll =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - 1; // the scrollbar's column
      final content = pageContentWidth(
        constraints.maxWidth,
        measure: widget.measure,
      );
      final left = (width - content) ~/ 2;
      final sections = widget.sections;
      return Actions(
        bindings: [
          // ↑↓ are the help row's; the page and end keys the panel's.
          for (final b in scrollBindings(
            _scroll,
            keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
          ))
            b.id == 'scroll:lineUp' || b.id == 'scroll:lineDown'
                ? Binding('${b.chord}', 'scroll', b.onInvoke, id: 'page:scroll')
                : Binding(
                    '${b.chord}',
                    b.description,
                    b.onInvoke,
                    id: '$panelOnly${b.id}',
                  ),
        ],
        child: Actions(
          bindings: widget.bindings,
          child: Focus(
            autofocus: true,
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                itemCount: sections.length,
                itemBuilder: (context, i) => Padding(
                  // Padding both sides: a list's items are as wide as the
                  // list, so a SizedBox alone would not hold the measure.
                  padding: EdgeInsets.only(
                    left: left,
                    right: width - left - content,
                  ),
                  child: sections[i],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
