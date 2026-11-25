import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../dialogs/permission.dart';
import '../dialogs/permission_scroll.dart';
import '../app/context.dart';
import 'keys.dart';

/// The original editorial catalog, in a passive layer above the prompt.
class ShortcutsPanel extends StatefulWidget {
  const ShortcutsPanel({
    super.key,
    required this.scroll,
    required this.onOverflow,
    this.isClosing,
    this.rule = true,
  });

  /// Whether its dim rule tops it: not under a framed picker, whose frame
  /// is the layer's edge.
  final bool rule;

  /// Reads the live window barrier even before a queued frame is drawn.
  final bool Function()? isClosing;

  final PermissionScroll scroll;
  final void Function(bool) onOverflow;

  @override
  State<ShortcutsPanel> createState() => _ShortcutsPanelState();
}

class _ShortcutsPanelState extends State<ShortcutsPanel> {
  bool? _reported;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.scroll,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final room = math.max(0, constraints.maxHeight - (widget.rule ? 1 : 0));
        final lines = shortcutsFor(Keys.of(context)).map(shortcutLine).toList();
        final rows = panelRows(lines, columnCount(lines, width));
        widget.scroll.configure(rows.length, room);
        final overflows = rows.length > room;
        if (_reported != overflows) {
          _reported = overflows;
          context.owner.afterLayout(() {
            if (mounted && _reported == overflows) widget.onOverflow(overflows);
          });
        }
        if (constraints.maxHeight <= 0 || width <= 0) return const SizedBox();
        final view = requestView(rows.length, room, widget.scroll.top);
        final hidden = hiddenRows(rows.length, view.top, view.shown);
        final dim = Theme.of(context).dim;
        Widget row(String text) =>
            Text(text, style: dim, softWrap: false, maxLines: 1);
        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.rule)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: row('─' * math.max(0, width - 2)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: panelPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (view.above)
                      row(
                        requestRule(
                          '↑',
                          hidden.above,
                          'pageup',
                          width - panelPadding,
                        ),
                      ),
                    if (view.shown > 0)
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        absorbPointerSignal: overflows,
                        onPointerSignal: (event) {
                          if ((widget.isClosing?.call() ?? false) ||
                              !overflows) {
                            return;
                          }
                          if (event.scrollDelta.y < 0) {
                            widget.scroll.step(ScrollStep.lineUp);
                          }
                          if (event.scrollDelta.y > 0) {
                            widget.scroll.step(ScrollStep.lineDown);
                          }
                        },
                        child: SizedBox(
                          width: math.max(0, width - panelPadding),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final text
                                  in rows.skip(view.top).take(view.shown))
                                row(text),
                            ],
                          ),
                        ),
                      ),
                    if (view.below)
                      row(
                        requestRule(
                          '↓',
                          hidden.below,
                          'pagedown',
                          width - panelPadding,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
