import 'dart:async';

import '../foundation/geometry.dart';
import '../foundation/scrollbar.dart';
import '../input/keys.dart';
import '../rendering/box.dart';
import '../terminal/buffer.dart';
import '../terminal/style.dart';
import 'basic.dart';
import 'framework.dart';
import 'listener.dart';
import 'scroll_controller.dart';
import 'theme.dart';

/// A one-column scrollbar on the right of a scrolling [child], following
/// [controller]: a `┃` thumb that pages on a press beside it and moves the
/// view when dragged. It has no keys of its own; the list's move it.
class Scrollbar extends StatefulWidget {
  /// A scrollbar beside [child], the list [controller] also drives.
  const Scrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.thumbStyle,
    this.trackStyle,
    this.thumbVisibility = true,
  });

  /// The scroll position the thumb shows and its presses and drags move.
  final ScrollController controller;

  /// The scrolling content, usually a list over [controller].
  final Widget child;

  /// The thumb's style; the theme's border when null.
  final Style? thumbStyle;

  /// The blank track's style; plain when null.
  final Style? trackStyle;

  /// Whether the thumb always shows; false shows it only while the view
  /// moves, and for 600 ms after, as Flutter's `timeToFade`.
  final bool thumbVisibility;

  @override
  State<Scrollbar> createState() => _ScrollbarState();
}

class _ScrollbarState extends State<Scrollbar> {
  static const _timeToFade = Duration(milliseconds: 600);

  final _capture = PointerCaptureController();
  final _track = _TrackGeometry();
  late int _offset = widget.controller.offset;
  Timer? _fade;
  bool _moving = false;
  int? _grab;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(Scrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _offset = widget.controller.offset;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _fade?.cancel();
    _capture.dispose();
    super.dispose();
  }

  void _changed() {
    final offset = widget.controller.offset;
    final moved = offset != _offset;
    _offset = offset;
    if (moved && !widget.thumbVisibility) {
      _fade?.cancel();
      _fade = Timer(_timeToFade, () {
        if (mounted) setState(() => _moving = false);
      });
      _moving = true;
    }
    setState(() {});
  }

  ScrollbarThumb? _thumb() {
    final c = widget.controller;
    return scrollbarThumb(
      track: _track.height,
      view: c.viewRows,
      content: c.contentRows,
      offset: c.offset,
    );
  }

  void _down(MouseEvent event) {
    if (event.button != MouseButton.primary) return;
    final thumb = _thumb();
    if (thumb == null) return;
    final row = event.position.y - _track.origin.y;
    if (row < thumb.top) {
      widget.controller.pageUp();
    } else if (row >= thumb.top + thumb.length) {
      widget.controller.pageDown();
    } else {
      _capture.capture();
      if (_capture.isCaptured) _grab = row - thumb.top;
    }
  }

  void _move(MouseEvent event) {
    final grab = _grab;
    if (grab == null) return;
    final c = widget.controller;
    c.jumpTo(
      scrollbarOffsetFor(
        top: event.position.y - _track.origin.y - grab,
        track: _track.height,
        view: c.viewRows,
        content: c.contentRows,
      ),
    );
  }

  void _end(MouseEvent _) => _grab = null;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Row(
      children: [
        Expanded(child: widget.child),
        Listener(
          captureController: _capture,
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _end,
          onPointerCancel: _end,
          child: _ScrollbarTrack(
            geometry: _track,
            view: c.viewRows,
            content: c.contentRows,
            offset: c.offset,
            showThumb: widget.thumbVisibility || _moving || _grab != null,
            thumbStyle: widget.thumbStyle ?? Theme.of(context).border,
            trackStyle: widget.trackStyle ?? Style.plain,
          ),
        ),
      ],
    );
  }
}

/// Where the track last painted, so a pointer's screen row maps onto it.
class _TrackGeometry {
  Offset origin = Offset.zero;
  int height = 0;
}

class _ScrollbarTrack extends LeafRenderObjectWidget {
  const _ScrollbarTrack({
    required this.geometry,
    required this.view,
    required this.content,
    required this.offset,
    required this.showThumb,
    required this.thumbStyle,
    required this.trackStyle,
  });

  final _TrackGeometry geometry;
  final int view;
  final int content;
  final int offset;
  final bool showThumb;
  final Style thumbStyle;
  final Style trackStyle;

  @override
  _RenderScrollbarTrack createRenderObject(BuildContext context) =>
      _RenderScrollbarTrack(geometry)..update(this);

  @override
  void updateRenderObject(BuildContext context, _RenderScrollbarTrack r) =>
      r.update(this);
}

class _RenderScrollbarTrack extends RenderBox {
  _RenderScrollbarTrack(this.geometry);

  final _TrackGeometry geometry;
  int _view = 0, _content = 0, _offset = 0;
  bool _showThumb = true;
  Style _thumbStyle = Style.plain, _trackStyle = Style.plain;

  void update(_ScrollbarTrack w) {
    _view = w.view;
    _content = w.content;
    _offset = w.offset;
    _showThumb = w.showThumb;
    _thumbStyle = w.thumbStyle;
    _trackStyle = w.trackStyle;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    final height = constraints.maxHeight;
    size = Size(1, height == unbounded ? 0 : height);
    geometry.height = size.height;
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    geometry.origin = origin;
    final thumb = _showThumb
        ? scrollbarThumb(
            track: size.height,
            view: _view,
            content: _content,
            offset: _offset,
          )
        : null;
    for (var row = 0; row < size.height; row++) {
      final onThumb =
          thumb != null && row >= thumb.top && row < thumb.top + thumb.length;
      canvas.put(
        origin.x,
        origin.y + row,
        onThumb ? '┃' : ' ',
        1,
        onThumb ? _thumbStyle : _trackStyle,
      );
    }
  }
}
