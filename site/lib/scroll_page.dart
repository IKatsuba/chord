import 'package:chord_tui/chord_tui.dart';

import 'site.dart' show narrowWidth, panelOnly;

/// A section of a [ScrollPage] that runs edge to edge, past the margins: a
/// band.
class FullBleed extends StatelessWidget {
  /// [child], edge to edge.
  const FullBleed(this.child, {super.key});

  /// The section.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A poster page over live widgets: its sections laid out once in a
/// [SingleChildScrollView], with the poster margins (4 columns, 2 on a
/// phone) save for [FullBleed] ones, a muted [Scrollbar], and the page's
/// scroll keys: ↑↓ in the help row, the page and end keys in the panel.
class ScrollPage extends StatefulWidget {
  /// A page of [sections].
  const ScrollPage({
    super.key,
    required this.sections,
    this.bindings = const [],
    this.controller,
  });

  /// The page's parts, top to bottom.
  final List<Widget> sections;

  /// The page's own keys, which win over its scroll keys.
  final List<Binding> bindings;

  /// The page's scroll; one of its own when null.
  final ScrollController? controller;

  @override
  State<ScrollPage> createState() => _ScrollPageState();
}

/// A page's scroll keys on [scroll]: ↑↓ scroll in the help row, and the
/// page and end keys, which the panel lists.
List<Binding> pageScrollBindings(ScrollController scroll) => [
  for (final b in scrollBindings(
    scroll,
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
];

class _ScrollPageState extends State<ScrollPage> {
  ScrollController? _own;
  ScrollController get _scroll =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final margin = constraints.maxWidth < narrowWidth ? 2 : 4;
      return Actions(
        bindings: pageScrollBindings(_scroll),
        child: Actions(
          bindings: widget.bindings,
          child: Focus(
            autofocus: true,
            child: Scrollbar(
              controller: _scroll,
              thumbStyle: Theme.of(context).dim,
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in widget.sections)
                      s is FullBleed
                          ? s
                          : Padding(
                              padding: EdgeInsets.symmetric(horizontal: margin),
                              child: s,
                            ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
