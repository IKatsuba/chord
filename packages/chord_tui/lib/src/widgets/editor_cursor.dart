import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/basic.dart';
import '../rendering/box.dart';
import '../terminal/buffer.dart';
import '../terminal/cursor.dart';
import 'framework.dart';

/// Internal editor paint bridge; cursor claims follow the editor's paint.
class EditorCursor extends SingleChildRenderObjectWidget {
  /// Claims either a settled area position or a laid-out source glyph.
  const EditorCursor({
    required this.enabled,
    required this.style,
    this.position,
    this.sourceOffset,
    required super.child,
  });

  /// Whether the editor has primary focus.
  final bool enabled;

  /// The terminal's cursor shape and blink policy.
  final CursorStyle style;

  /// The insertion position in a text area's viewport.
  final Offset? position;

  /// The insertion glyph in a text input's paragraph.
  final int? sourceOffset;

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderEditorCursor(enabled, style, position, sourceOffset);

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    final r = renderObject as _RenderEditorCursor;
    r
      ..enabled = enabled
      ..style = style
      ..position = position
      ..sourceOffset = sourceOffset;
  }
}

/// Where the editor cursor [box] draws is, inside it; null when [box] draws
/// none.
@internal
Offset? editorCursorIn(RenderBox box) =>
    box is _RenderEditorCursor && box.enabled ? box.cursorAt : null;

class _RenderEditorCursor extends RenderProxyBox {
  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(_RenderEditorCursor);

  _RenderEditorCursor(
    this.enabled,
    this.style,
    this.position,
    this.sourceOffset,
  );

  bool enabled;
  CursorStyle style;
  Offset? position;
  int? sourceOffset;

  /// Where the cursor is drawn inside this box; null with none.
  Offset? get cursorAt {
    var at = position;
    final paragraph = child;
    if (sourceOffset != null && paragraph is RenderParagraph) {
      final lines = paragraph.textLayout.lines;
      for (var y = 0; y < lines.length && at == null; y++) {
        var x = 0;
        for (final glyph in lines[y]) {
          if (glyph.sourceOffset == sourceOffset) {
            at = Offset(x, y);
            break;
          }
          x += glyph.width;
        }
      }
    }
    return at;
  }

  @override
  void paint(Canvas canvas, Offset origin) {
    super.paint(canvas, origin);
    if (!enabled || size.width == 0 || size.height == 0) return;
    final at = cursorAt;
    if (at == null) return;
    canvas
        .clipped(Rect.fromOffsetSize(origin, size))
        .setCursor(origin + at, style: style);
  }
}
