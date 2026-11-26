import 'dart:math' as math;
import 'package:chord_tui/chord_tui.dart';
import 'commands.dart';
import 'state.dart';

/// The original passive, floating command list, with no selection gutter.
class CommandList extends StatefulWidget {
  const CommandList({
    super.key,
    required this.menu,
    required this.windowRows,
    required this.onRoom,
    this.isClosing,
  });
  final CommandMenuState menu;
  final int windowRows;
  final void Function(int) onRoom;
  final bool Function()? isClosing;
  @override
  State<CommandList> createState() => _CommandListState();
}

class _CommandListState extends State<CommandList> {
  final _scroll = ScrollController();
  int? _reported;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CommandList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menu.picker.selected != widget.menu.picker.selected ||
        oldWidget.menu.draft != widget.menu.draft) {
      _scroll.toTop();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final items = widget.menu.matches;
      final room = math.max(0, constraints.maxHeight - 1);
      final limit = math.min(menuRowLimit(widget.windowRows), room);
      final rows = math.min(items.length, limit);
      if (_reported != rows) {
        _reported = rows;
        context.owner.afterLayout(() {
          if (mounted && _reported == rows) widget.onRoom(rows);
        });
      }
      if (rows <= 0 || constraints.maxWidth <= 0) return const SizedBox();
      final range = visibleRange(
        items.length,
        widget.menu.picker.highlighted,
        limit,
        widget.menu.top,
      );
      final shown = items.sublist(range.start, range.end);
      final nameWidth = math.max(
        0,
        math.min(
          items.fold(
            0,
            (n, item) => math.max(n, cellWidth(itemLabel(item)) + 2),
          ),
          (constraints.maxWidth - 4) ~/ 3,
        ),
      );
      final overflowing = _scroll.contentRows > _scroll.viewRows;
      return Box(
        background: Style.plain,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                '─' * math.max(0, constraints.maxWidth - 2),
                style: theme.dim,
                softWrap: false,
              ),
            ),
            SizedBox(
              height: rows,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                absorbPointerSignal: overflowing,
                onPointerSignal: (event) {
                  if (widget.isClosing?.call() == true ||
                      _scroll.contentRows <= _scroll.viewRows) {
                    return;
                  }
                  for (var i = 0; i < event.scrollDelta.y.abs(); i++) {
                    event.scrollDelta.y < 0
                        ? _scroll.lineUp()
                        : _scroll.lineDown();
                  }
                },
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: shown.length,
                  itemBuilder: (_, index) {
                    final item = shown[index];
                    final lit =
                        range.start + index == widget.menu.picker.highlighted;
                    final style = lit ? theme.focus : theme.dim;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: nameWidth,
                            child: Text.ansi(
                              itemLabel(item),
                              style: style,
                              softWrap: false,
                              maxLines: 1,
                              overflow: TextOverflow.middle,
                            ),
                          ),
                          Expanded(
                            child: Text.ansi(
                              item.description ?? '',
                              style: style,
                              softWrap: false,
                              maxLines: 1,
                              overflow: TextOverflow.middle,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
