import 'dart:math' as math;

import '../foundation/geometry.dart';
import '../input/keys.dart';
import '../rendering/listener.dart' show RenderPointerListener;
import '../rendering/selection_content.dart';
import '../foundation/selection_source.dart';
import '../terminal/style.dart';
import '../text/selection_layout.dart' show SelectionRow, shapeSelectionSource;
import '../text/span.dart';
import 'basic.dart';
import 'framework.dart';
import 'listener.dart';
import 'selection.dart' show SelectionArea, collectCodeButtonScene;
import 'selection_content.dart';
import 'theme.dart';
import 'theme_data.dart';

/// Markdown drawn in cells with shared semantic text, code and table maps.
class Markdown extends StatefulWidget {
  /// Parses [text] with the maintained Markdown package and draws it in cells.
  const Markdown(
    this.text, {
    super.key,
    this.growing = false,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.runCodeBlockLanguages = const {},
    this.onRunCodeBlock,
    this.quoteBars = true,
  }) : _selectionSource = null;

  Markdown._bound(
    this._selectionSource, {
    super.key,
    bool? growing,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
  }) : text = selectionSourceText(_selectionSource!),
       growing = growing ?? selectionSourceGrowing(_selectionSource),
       runCodeBlockLanguages = _selectionSource.runCodeBlockLanguages,
       quoteBars = selectionSourceGeometry(_selectionSource).quoteBars;

  /// Binds the exact snapshot supplied to a lazy selection provider.
  factory Markdown.fromSelectionSource(
    SelectionSource source, {
    Key? key,
    bool? growing,
    CodeBlockId? selectedCodeBlock,
    void Function(MarkdownCodeBlock)? onCopyCodeBlock,
    Set<String>? runCodeBlockLanguages,
    void Function(MarkdownCodeBlock)? onRunCodeBlock,
  }) {
    checkSelectionSourceKind(source, SelectionSourceKind.markdown);
    checkSelectionGeometry(
      onCopyCodeBlock != null,
      selectionSourceGeometry(source).copyCodeBlocks,
      'copyCodeBlocks',
    );
    if (runCodeBlockLanguages != null &&
        !_sameLanguages(runCodeBlockLanguages, source.runCodeBlockLanguages)) {
      throw ArgumentError.value(
        runCodeBlockLanguages,
        'runCodeBlockLanguages',
        'must agree with the selection source',
      );
    }
    _checkRunCallback(source.runCodeBlockLanguages, onRunCodeBlock);
    return Markdown._bound(
      source,
      key: key,
      growing: growing,
      selectedCodeBlock: selectedCodeBlock,
      onCopyCodeBlock: onCopyCodeBlock,
      onRunCodeBlock: onRunCodeBlock,
    );
  }

  final SelectionSource? _selectionSource;

  /// The rows a Markdown bound to [source] takes at [width] cells, so a
  /// caller can tell how much of it a fold of its own hides.
  static int heightOf(SelectionSource source, int width) {
    checkSelectionSourceKind(source, SelectionSourceKind.markdown);
    return shapeSelectionSource(source, width: width).rows.length;
  }

  /// The rows a [Markdown] of [text] draws at [width] cells with [theme],
  /// split at its top-level blocks: one list of rows per block, each row a
  /// span of the glyphs and styles the widget paints there. The blank row
  /// the widget puts between two blocks is not in either, so a caller that
  /// folds or counts Markdown of its own puts it back where it needs it.
  ///
  /// A row runs from column 0: a gap between glyphs is a plain space, a row
  /// tint carries over the row's cells to [width], and trailing unstyled
  /// spaces are dropped; a blank row inside a block is `TextSpan('')`.
  /// Empty or invisible blocks give no entry. The rows are cut from the one
  /// layout the widget draws, so the rows of all blocks and the blank rows
  /// between them are [heightOf]'s.
  static List<List<TextSpan>> blocksOf(
    String text,
    int width, {
    required ThemeData theme,
    bool quoteBars = true,
  }) {
    final source = SelectionSource.markdown(
      id: Object(),
      revision: 0,
      text: text,
      quoteBars: quoteBars,
    );
    final gaps = <int>[];
    final rows = shapeSelectionSource(
      source,
      width: width,
      theme: theme,
      gaps: gaps,
    ).rows;
    final blocks = <List<TextSpan>>[];
    var from = 0;
    for (final gap in [...gaps, rows.length]) {
      final block = [
        for (final row in rows.sublist(from, gap)) _rowSpan(row, width),
      ];
      // An empty document draws one empty row, which is no block.
      if (block.any((row) => row.children.isNotEmpty)) blocks.add(block);
      from = gap + 1;
    }
    return blocks;
  }

  /// [row] as one span of the cells it paints, from column 0: its glyphs
  /// put in painting order, a later one over an earlier, then read left to
  /// right, neighbours of one style as one run.
  ///
  /// A glyph of no width left alone in its cell takes that cell, as the
  /// canvas puts it there, and shows nothing in it: it is written as a
  /// space, so that the row drawn as text keeps every later cell in its
  /// column and no mark joins the glyph before it.
  static TextSpan _rowSpan(SelectionRow row, int width) {
    final tint = row.background;
    final cells = <int, (String, int, Style)>{};
    for (final cell in row.glyphs) {
      final glyph = cell.glyph;
      final style = tint?.bg != null && glyph.style.bg == null
          ? glyph.style.copyWith(bg: tint!.bg)
          : glyph.style;
      // A wide glyph under this one, or this one's second cell, goes.
      final before = cells[cell.x - 1];
      if (before != null && before.$2 == 2) cells.remove(cell.x - 1);
      if (glyph.width == 2) cells.remove(cell.x + 1);
      cells[cell.x] = (glyph.text, glyph.width, style);
    }
    final painted = cells.keys.fold(
      0,
      (end, x) => math.max(end, x + math.max(cells[x]!.$2, 1)),
    );
    final last = tint == null ? painted : math.max(painted, width);
    final runs = <(String, Style)>[];
    void add(String text, Style style) {
      if (runs.isNotEmpty && runs.last.$2 == style) {
        runs.last = (runs.last.$1 + text, style);
      } else {
        runs.add((text, style));
      }
    }

    for (var x = 0; x < last;) {
      final cell = cells[x];
      if (cell == null) {
        add(' ', tint ?? Style.plain);
        x++;
      } else if (cell.$2 == 0) {
        add(' ', cell.$3);
        x++;
      } else {
        add(cell.$1, cell.$3);
        x += cell.$2;
      }
    }
    // Trailing spaces with no style of their own are no cells drawn.
    while (runs.isNotEmpty &&
        runs.last.$2 == Style.plain &&
        runs.last.$1.trim().isEmpty) {
      runs.removeLast();
    }
    return TextSpan(
      '',
      children: [
        for (final (text, style) in runs) TextSpan(text, style: style),
      ],
    );
  }

  /// Current Markdown characters, before parsing.
  final String text;

  /// Whether a quote is drawn behind a bar, dim and italic; else it reads
  /// as the text around it. A bound source says it.
  final bool quoteBars;

  /// Whether the current final code block is still growing.
  final bool growing;

  /// The framework-issued block whose frame is picked by the application.
  final CodeBlockId? selectedCodeBlock;

  /// The application code-copy action for eligible closed code boxes.
  final void Function(MarkdownCodeBlock)? onCopyCodeBlock;

  /// Exact application language names for run controls; ordinary config is read-only.
  final Set<String> runCodeBlockLanguages;

  /// Receives the current complete block; the application owns its run policy.
  final void Function(MarkdownCodeBlock)? onRunCodeBlock;
  @override
  State<Markdown> createState() => _MarkdownState();
}

class _MarkdownState extends State<Markdown> {
  final _capture = PointerCaptureController();
  _CodeButton? _pressed;

  @override
  void initState() {
    super.initState();
    if (_hasButtons(widget)) {
      context.owner.inputGeometryObservers.add(_geometryChanged);
    }
  }

  @override
  void didUpdateWidget(Markdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasButtons(widget)) {
      context.owner.inputGeometryObservers.remove(_geometryChanged);
      _pressed = null;
    } else if (!_hasButtons(oldWidget)) {
      context.owner.inputGeometryObservers.add(_geometryChanged);
    }
  }

  @override
  void dispose() {
    context.owner.inputGeometryObservers.remove(_geometryChanged);
    _pressed = null;
    _capture.dispose();
    super.dispose();
  }

  _CodeButton? _buttonAt(Offset point, {bool synchronize = true}) {
    if (!mounted || !_hasButtons(widget)) return null;
    if (synchronize && !context.owner.ensureCurrentInputGeometry()) return null;
    if (!mounted) return null;
    final box = context.findRenderObject();
    final content = box is RenderPointerListener ? box.child : box;
    if (content is! RenderSelectionContent) return null;
    final scene = collectCodeButtonScene(context, content);
    if (scene == null || !scene.resolved) return null;
    final surface = scene.geometry.surfaces
        .where((s) => identical(s.owner, content))
        .firstOrNull;
    if (surface == null) return null;
    for (final block in content.source.codeBlocks) {
      if (!block.complete) continue;
      for (final action in _CodeAction.values) {
        if (action == _CodeAction.copy && widget.onCopyCodeBlock == null ||
            action == _CodeAction.run && widget.onRunCodeBlock == null) {
          continue;
        }
        final buttons = action == _CodeAction.copy
            ? surface.layout.codeButtons
            : surface.layout.codeRunButtons;
        final local = buttons[selectionCodeFragment(block.id)];
        if (local == null) continue;
        final rect = Rect(
          local.left + surface.origin.x,
          local.top + surface.origin.y,
          local.width,
          local.height,
        );
        if (!rect.contains(point.x, point.y)) continue;
        if (!scene.geometry.exposed(surface, rect.left, rect.top, rect.width)) {
          continue;
        }
        return _CodeButton(block, rect, point, action);
      }
    }
    return null;
  }

  void _geometryChanged(bool resolved) {
    final pressed = _pressed;
    if (pressed == null) return;
    final current = resolved
        ? _buttonAt(pressed.point, synchronize: false)
        : null;
    if (!pressed.matches(current)) _pressed = null;
  }

  void _down(MouseEvent event) {
    if (event.button != MouseButton.primary) return;
    final epoch = context.owner.pointerRouter.epoch;
    final hit = _buttonAt(event.position);
    if (hit == null || epoch != context.owner.pointerRouter.epoch) return;
    context.findAncestorWidgetOfExactType<SelectionArea>()?.controller.clear();
    if (!mounted || epoch != context.owner.pointerRouter.epoch) return;
    final current = _buttonAt(event.position);
    if (!hit.matches(current) || epoch != context.owner.pointerRouter.epoch) {
      return;
    }
    _capture.capture();
    if (_capture.isCaptured) _pressed = current;
  }

  void _up(MouseEvent event) {
    if (event.button != MouseButton.primary) return;
    final pressed = _pressed;
    _pressed = null;
    if (pressed == null) return;
    final epoch = context.owner.pointerRouter.epoch;
    final current = _buttonAt(event.position);
    if (!mounted ||
        epoch != context.owner.pointerRouter.epoch ||
        !pressed.matches(current) ||
        event.position != pressed.point) {
      return;
    }
    switch (current!.action) {
      case _CodeAction.copy:
        widget.onCopyCodeBlock?.call(current.block);
      case _CodeAction.run:
        widget.onRunCodeBlock?.call(current.block);
    }
  }

  final _id = Object();
  var _revision = 0;
  (String, bool, bool, bool)? _inputs;
  Set<String> _languages = const {};
  SelectionSource? _source;
  @override
  Widget build(BuildContext context) {
    _checkRunCallback(widget.runCodeBlockLanguages, widget.onRunCodeBlock);
    var source = widget._selectionSource;
    if (source == null) {
      final inputs = (
        widget.text,
        widget.growing,
        widget.onCopyCodeBlock != null,
        widget.quoteBars,
      );
      if (_inputs != inputs ||
          !_sameLanguages(_languages, widget.runCodeBlockLanguages)) {
        _source = SelectionSource.markdown(
          id: _id,
          revision: _revision++,
          text: widget.text,
          growing: widget.growing,
          copyCodeBlocks: widget.onCopyCodeBlock != null,
          runCodeBlockLanguages: widget.runCodeBlockLanguages,
          quoteBars: widget.quoteBars,
          previous: _source,
        );
        _inputs = inputs;
        _languages = _source!.runCodeBlockLanguages;
      }
      source = _source!;
    }
    final content = SelectionContent(
      source: source,
      theme: Theme.of(context),
      base: DefaultTextStyle.of(context),
      growing: widget.growing,
      selectedCodeBlock: widget.selectedCodeBlock,
    );
    if (!_hasButtons(widget)) return content;
    return Listener(
      captureController: _capture,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerMove: (_) => _pressed = null,
      onPointerCancel: (_) => _pressed = null,
      child: content,
    );
  }
}

enum _CodeAction { copy, run }

class _CodeButton {
  const _CodeButton(this.block, this.rect, this.point, this.action);
  final MarkdownCodeBlock block;
  final Rect rect;
  final Offset point;
  final _CodeAction action;
  bool matches(_CodeButton? other) =>
      other != null &&
      action == other.action &&
      block.id == other.block.id &&
      block.revision == other.block.revision &&
      rect == other.rect;
}

bool _sameLanguages(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
bool _hasButtons(Markdown widget) =>
    widget.onCopyCodeBlock != null || widget.onRunCodeBlock != null;
void _checkRunCallback(
  Set<String> languages,
  void Function(MarkdownCodeBlock)? callback,
) {
  if (languages.isNotEmpty != (callback != null)) {
    throw ArgumentError(
      'Run languages and callback must either both be present or both be absent.',
    );
  }
}
