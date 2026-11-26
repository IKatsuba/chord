import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/box.dart';
import '../terminal/buffer.dart';
import 'framework.dart';

/// Where a pressable widget last painted, so a release is checked against
/// the cells it covers.
@internal
class PressBounds {
  /// The painted area, in screen cells.

  Rect rect = const Rect(0, 0, 0, 0);

  /// Whether [p] is inside the painted area.
  bool contains(Offset p) => rect.contains(p.x, p.y);
}

/// Records where [child] paints into [bounds].
@internal
class PressBoundsBox extends SingleChildRenderObjectWidget {
  /// [child], recorded into [bounds].
  const PressBoundsBox({super.key, required this.bounds, required super.child});

  /// Where the last paint went.
  final PressBounds bounds;

  @override
  RenderPressBounds createRenderObject(BuildContext context) =>
      RenderPressBounds(bounds);

  @override
  void updateRenderObject(BuildContext context, RenderPressBounds r) =>
      r.bounds = bounds;
}

/// The render box of [PressBoundsBox].
@internal
class RenderPressBounds extends RenderProxyBox {
  /// A box recording into [bounds].
  RenderPressBounds(this.bounds);

  /// Where the last paint went.
  PressBounds bounds;

  @override
  PaintCoverage describePaintCoverage(Rect localClip) =>
      const PaintCoverage.empty(RenderPressBounds);

  @override
  void paint(Canvas canvas, Offset origin) {
    bounds.rect = Rect.fromOffsetSize(origin, size);
    super.paint(canvas, origin);
  }
}
