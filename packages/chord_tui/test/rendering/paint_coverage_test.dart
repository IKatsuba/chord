import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/rendering/paint_coverage.dart';
import 'package:chord_tui/src/rendering/selection_content.dart';
import 'package:test/test.dart';

Set<(int, int)> cells(Iterable<Rect> rectangles) => {
  for (final r in rectangles)
    for (var y = r.top; y < r.bottom; y++)
      for (var x = r.left; x < r.right; x++) (x, y),
};

class _RecordingCanvas extends Canvas {
  _RecordingCanvas(super.buffer, [super.clip]);
  final written = <(int, int)>{};

  @override
  void put(int x, int y, String g, int w, Style style) {
    final rect = glyphCoverage(x, y, w, clip);
    if (rect != null) written.addAll(cells([rect]));
    super.put(x, y, g, w, style);
  }

  @override
  void fill(Rect r, [Style style = Style.plain, String char = ' ']) {
    written.addAll(cells([r.intersect(clip)]));
    super.fill(r, style, char);
  }

  @override
  Canvas clipped(Rect r) => _SharedCanvas(buffer, clip.intersect(r), written);
}

class _SharedCanvas extends _RecordingCanvas {
  _SharedCanvas(super.buffer, super.clip, this.shared);
  final Set<(int, int)> shared;
  @override
  Set<(int, int)> get written => shared;
}

class _UndeclaredProxy extends RenderProxyBox {}

void main() {
  test('coverage defensively freezes phase rectangles', () {
    final before = [const Rect(0, 0, 1, 1)];
    final after = [const Rect(1, 0, 1, 1)];
    final value = PaintCoverage(
      declaredFor: RenderBox,
      beforeChildren: before,
      afterChildren: after,
    );
    before.clear();
    after.clear();
    expect(value.beforeChildren, hasLength(1));
    expect(value.afterChildren, hasLength(1));
    expect(() => value.beforeChildren.clear(), throwsUnsupportedError);
    expect(() => value.afterChildren.clear(), throwsUnsupportedError);
  });

  test('a custom subclass does not inherit an exact-type declaration', () {
    final custom = _UndeclaredProxy();
    expect(
      custom.describePaintCoverage(Rect.zero)!.declaredFor,
      isNot(custom.runtimeType),
    );
  });

  test('border coverage preserves its transparent interior', () {
    final box = RenderDecoratedBox(border: const Border());
    box.layout(const BoxConstraints.tightFor(width: 8, height: 4));
    final coverage = box.describePaintCoverage(const Rect(0, 0, 8, 4));
    final written = cells(coverage.beforeChildren);
    expect(written, hasLength(20));
    expect(written, contains((0, 2)));
    expect(written, isNot(contains((2, 2))));
  });

  test(
    'glyph coverage matches clipped-wide fallback and left-edge rejection',
    () {
      expect(
        glyphCoverage(3, 0, 2, const Rect(0, 0, 4, 1)),
        const Rect(3, 0, 1, 1),
      );
      expect(glyphCoverage(-1, 0, 2, const Rect(0, 0, 4, 1)), isNull);
    },
  );

  for (final width in [120, 80]) {
    test('built-in self coverage matches actual writes at width $width', () {
      final boxes = <RenderBox>[
        RenderParagraph(const TextSpan('a界👩‍💻\nend'), style: Style.plain),
        RenderDecoratedBox(border: const Border(), title: '界 frame'),
        RenderDecoratedBox(background: Style.inverse),
        RenderSelectionContent(
          source: SelectionSource.markdown(
            id: 'm',
            revision: 0,
            text: '```dart\n\t界\n\nend\n```',
          ),
          theme: ThemeData.plain(),
          base: Style.plain,
        ),
      ];
      for (final box in boxes) {
        box.layout(BoxConstraints(maxWidth: width, maxHeight: 12));
        for (final clip in [
          Rect(0, 0, width, 12),
          const Rect(1, 0, 2, 2),
          const Rect(0, 1, 4, 4),
        ]) {
          final canvas = _RecordingCanvas(Buffer(width, 12), clip);
          box.paint(canvas, Offset.zero);
          final coverage = box.describePaintCoverage(clip)!;
          expect(coverage.declaredFor, box.runtimeType);
          expect(
            cells([...coverage.beforeChildren, ...coverage.afterChildren]),
            canvas.written,
            reason: '${box.runtimeType} $clip',
          );
        }
      }
    });
  }
}
