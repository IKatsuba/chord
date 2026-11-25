import 'dart:math' as math;
import 'package:chord_tui/chord_tui.dart';
import 'commands.dart';
import 'state.dart';

/// Passive current file/agent rows floating above the existing prompt.
class FileList extends StatefulWidget {
  const FileList({
    super.key,
    required this.finder,
    required this.windowRows,
    required this.onRoom,
    this.colors = const {},
    this.isActive,
  });
  final FileFinder finder;
  final int windowRows;
  final Map<String, Color?> colors;
  final void Function(int) onRoom;
  final bool Function()? isActive;
  @override
  State<FileList> createState() => _FileListState();
}

class _FileListState extends State<FileList> {
  final _scroll = ScrollController();
  int? _reported;
  Object? _synced;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final finder = widget.finder, theme = Theme.of(context);
      final room = constraints.maxWidth <= 0
          ? 0
          : math.min(
              menuRowLimit(widget.windowRows),
              math.max(0, constraints.maxHeight - 1),
            );
      if (_reported != room) {
        _reported = room;
        context.owner.afterLayout(() {
          if (mounted && _reported == room) widget.onRoom(room);
        });
      }
      if (room <= 0) return const SizedBox();
      final files = finder.files;
      final searching = finder.showsSearching(room);
      final choices = finder.choiceRows(room);
      final empty = finder.empty != null && files.isEmpty;
      final rows = math.min(
        room,
        choices + (searching ? 1 : 0) + (empty ? 1 : 0),
      );
      if (rows == 0) {
        // A pending search needs linked room, never a fabricated visible choice.
        return finder.pendingSurface
            ? SizedBox(width: constraints.maxWidth, height: 1)
            : const SizedBox();
      }
      if (choices > 0) {
        final top = visibleRange(
          files.length,
          finder.highlighted,
          choices,
          finder.top,
        ).start;
        final sync = (files, finder.highlighted, top, choices);
        if (_synced != sync) {
          _synced = sync;
          context.owner.afterLayout(() {
            if (mounted && _synced == sync) _scroll.jumpTo(top);
          });
        }
      }
      final overflowing = files.length > choices;
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
            if (choices > 0)
              SizedBox(
                height: choices,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  absorbPointerSignal: overflowing,
                  onPointerSignal: (event) {
                    if (widget.isActive?.call() == false || !overflowing) {
                      return;
                    }
                    if (event.scrollDelta.y < 0) _scroll.lineUp();
                    if (event.scrollDelta.y > 0) _scroll.lineDown();
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: files.length,
                    itemBuilder: (_, index) {
                      final path = files[index];
                      final style = index == finder.highlighted
                          ? theme.focus
                          : finder.agent && path != 'main'
                          ? Style(
                              fg: Theme.noColorOf(context)
                                  ? null
                                  : widget.colors[path],
                            )
                          : theme.dim;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          path,
                          style: style,
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  finder.empty!,
                  style: theme.dim,
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
            if (searching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'searching…',
                  style: theme.dim,
                  softWrap: false,
                  maxLines: 1,
                ),
              ),
          ],
        ),
      );
    },
  );
}
