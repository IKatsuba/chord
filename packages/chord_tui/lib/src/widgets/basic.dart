import '../foundation/geometry.dart';
import '../foundation/notifier.dart';
import '../foundation/selection_source.dart';
import '../rendering/basic.dart';
import '../rendering/box.dart';
import '../rendering/flex.dart';
import '../terminal/style.dart';
import '../text/ansi.dart';
import '../text/layout.dart';
import '../text/span.dart';
import 'framework.dart';
import 'theme.dart';

/// Text, wrapped to the width it is given.
class Text extends LeafRenderObjectWidget {
  /// Plain [data], drawn in [style].
  Text(
    String data, {
    super.key,
    this.style,
    this.align = TextAlign.left,
    this.softWrap,
    this.overflow,
    this.maxLines,
  }) : span = TextSpan(data),
       _selectionSource = null;

  /// Text of styled [span]s.
  const Text.rich(
    this.span, {
    super.key,
    this.style,
    this.align = TextAlign.left,
    this.softWrap,
    this.overflow,
    this.maxLines,
  }) : _selectionSource = null;

  /// Text that carries its own SGR escape sequences, such as tool output.
  Text.ansi(
    String data, {
    super.key,
    this.style,
    this.align = TextAlign.left,
    this.softWrap,
    this.overflow,
    this.maxLines,
  }) : span = parseAnsi(data),
       _selectionSource = null;

  Text._bound(this._selectionSource, {super.key, this.style})
    : span = selectionSourceSpan(_selectionSource!),
      align = selectionSourceGeometry(_selectionSource).align,
      softWrap = selectionSourceGeometry(_selectionSource).softWrap,
      overflow = selectionSourceGeometry(_selectionSource).overflow,
      maxLines = selectionSourceGeometry(_selectionSource).maxLines;

  /// Binds the provider's exact content and frozen effective geometry.
  factory Text.fromSelectionSource(
    SelectionSource source, {
    Key? key,
    Style? style,
    TextAlign? align,
    bool? softWrap,
    TextOverflow? overflow,
    int? maxLines,
  }) {
    checkSelectionSourceKind(source, SelectionSourceKind.text);
    final geometry = selectionSourceGeometry(source);
    checkSelectionGeometry(align, geometry.align, 'align');
    checkSelectionGeometry(softWrap, geometry.softWrap, 'softWrap');
    checkSelectionGeometry(overflow, geometry.overflow, 'overflow');
    checkSelectionGeometry(maxLines, geometry.maxLines, 'maxLines');
    return Text._bound(source, key: key, style: style);
  }

  final SelectionSource? _selectionSource;

  /// What is drawn, with its styles.
  final TextSpan span;

  /// The style laid over the [DefaultTextStyle]'s.
  final Style? style;

  /// Where each line sits across the width.
  final TextAlign align;

  /// Whether lines wrap; the [DefaultTextStyle]'s, else true, when null.
  /// A line wraps after a space or a break character (`/`, `-`, `.`, and
  /// the others OpenTUI's word wrap breaks after), between CJK graphemes,
  /// and cuts a word wider than the line.
  final bool? softWrap;

  /// How a cut line ends; the [DefaultTextStyle]'s, else clipped, when
  /// null.
  final TextOverflow? overflow;

  /// The most lines; the [DefaultTextStyle]'s, else no limit, when null.
  final int? maxLines;

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    final d = DefaultTextStyle.maybeOf(context);
    return RenderParagraph(
      span,
      selectionSource: _selectionSource,
      style: _resolve(context),
      align: align,
      softWrap: softWrap ?? d?.softWrap ?? true,
      overflow: overflow ?? d?.overflow ?? TextOverflow.clip,
      maxLines: _selectionSource == null ? maxLines ?? d?.maxLines : maxLines,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph r) {
    final d = DefaultTextStyle.maybeOf(context);
    r
      ..text = span
      ..selectionSource = _selectionSource
      ..style = _resolve(context)
      ..align = align
      ..softWrap = softWrap ?? d?.softWrap ?? true
      ..overflow = overflow ?? d?.overflow ?? TextOverflow.clip
      ..maxLines = _selectionSource == null
          ? maxLines ?? d?.maxLines
          : maxLines;
  }

  Style _resolve(BuildContext context) =>
      (DefaultTextStyle.of(context)).merge(style);
}

/// The style [Text] below it starts from, and, as Flutter's, the wrapping,
/// overflow and line limit a [Text] that sets none of its own takes.
class DefaultTextStyle extends InheritedWidget {
  /// Defaults for the [Text] under [child].
  const DefaultTextStyle({
    super.key,
    required this.style,
    this.softWrap,
    this.overflow,
    this.maxLines,
    required super.child,
  });

  /// The style text starts from.
  final Style style;

  /// Whether lines wrap, for text that does not say.
  final bool? softWrap;

  /// How a cut line ends, for text that does not say.
  final TextOverflow? overflow;

  /// The most lines, for text that does not say.
  final int? maxLines;

  /// The style text at [context] starts from.
  static Style of(BuildContext context) =>
      maybeOf(context)?.style ?? Style.plain;

  /// The nearest defaults above [context], if any.
  static DefaultTextStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DefaultTextStyle>();

  @override
  bool updateShouldNotify(DefaultTextStyle oldWidget) =>
      style != oldWidget.style ||
      softWrap != oldWidget.softWrap ||
      overflow != oldWidget.overflow ||
      maxLines != oldWidget.maxLines;
}

/// Empty space around its child.
class Padding extends SingleChildRenderObjectWidget {
  /// Its child, inset by [padding].
  const Padding({super.key, required this.padding, super.child});

  /// The cells left empty on each side.
  final EdgeInsets padding;

  @override
  RenderPadding createRenderObject(BuildContext context) =>
      RenderPadding(padding);

  @override
  void updateRenderObject(BuildContext context, RenderPadding r) =>
      r.padding = padding;
}

/// Adds constraints to those its child is given.
class ConstrainedBox extends SingleChildRenderObjectWidget {
  /// Its child, held within [constraints] as well.
  const ConstrainedBox({super.key, required this.constraints, super.child});

  /// The constraints laid over the parent's.
  final BoxConstraints constraints;

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      RenderConstrainedBox(constraints);

  @override
  void updateRenderObject(BuildContext context, RenderConstrainedBox r) =>
      r.additional = constraints;
}

/// A box of a given size, or of its child's size where none is given.
class SizedBox extends SingleChildRenderObjectWidget {
  /// A box [width] wide and [height] high; null takes the child's size.
  const SizedBox({super.key, this.width, this.height, super.child});

  /// A box as large as its parent allows.
  const SizedBox.expand({super.key, super.child})
    : width = unbounded,
      height = unbounded;

  /// The width in cells; the child's when null.
  final int? width;

  /// The height in rows; the child's when null.
  final int? height;

  BoxConstraints get _c => BoxConstraints(
    minWidth: width ?? 0,
    maxWidth: width ?? unbounded,
    minHeight: height ?? 0,
    maxHeight: height ?? unbounded,
  );

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      RenderConstrainedBox(_c);

  @override
  void updateRenderObject(BuildContext context, RenderConstrainedBox r) =>
      r.additional = _c;
}

/// Places its child within itself by [alignment].
class Align extends SingleChildRenderObjectWidget {
  /// Its child placed by [alignment], sized by the factors when given.
  const Align({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  });

  /// Where the child sits within the box.
  final Alignment alignment;

  /// Its width as a multiple of the child's; as wide as allowed when null.
  final double? widthFactor;

  /// Its height as a multiple of the child's; as high as allowed when null.
  final double? heightFactor;

  @override
  RenderAlign createRenderObject(BuildContext context) => RenderAlign(
    alignment,
    widthFactor: widthFactor,
    heightFactor: heightFactor,
  );

  @override
  void updateRenderObject(BuildContext context, RenderAlign r) {
    r
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor;
  }
}

/// Places its child in its middle.
class Center extends Align {
  /// Its child centred.
  const Center({super.key, super.widthFactor, super.heightFactor, super.child});
}

/// A background, border and title around an optional child.
class DecoratedBox extends SingleChildRenderObjectWidget {
  /// A [border] with an optional [title], over [background], around [child].
  const DecoratedBox({
    super.key,
    this.border,
    this.title,
    this.background,
    super.child,
  });

  /// The frame drawn around it; none when null.
  final Border? border;

  /// The text set into the top border.
  final String? title;

  /// The style that fills the box.
  final Style? background;

  /// The border with no style given takes the theme's.
  Border? _border(BuildContext context) {
    final b = border;
    if (b == null || b.style != null) return b;
    return b.withStyle(Theme.of(context).border);
  }

  @override
  RenderDecoratedBox createRenderObject(BuildContext context) =>
      RenderDecoratedBox(
        border: _border(context),
        title: title,
        background: background,
      );

  @override
  void updateRenderObject(BuildContext context, RenderDecoratedBox r) {
    r
      ..border = _border(context)
      ..title = title
      ..background = background;
  }
}

/// A box: size, border with a title, background and padding in one widget.
class Box extends StatelessWidget {
  /// A box with whichever of size, frame, background and padding are given.
  const Box({
    super.key,
    this.child,
    this.border,
    this.title,
    this.background,
    this.padding,
    this.width,
    this.height,
    this.style,
  });

  /// What the box holds.
  final Widget? child;

  /// Its frame; a single line when only a [title] is given.
  final Border? border;

  /// The text set into the top border.
  final String? title;

  /// The style that fills the box.
  final Style? background;

  /// The space between the frame and [child].
  final EdgeInsets? padding;

  /// The width in cells; the content's when null.
  final int? width;

  /// The height in rows; the content's when null.
  final int? height;

  /// The default text style inside the box.
  final Style? style;

  @override
  Widget build(BuildContext context) {
    Widget? current = child;
    if (padding != null) current = Padding(padding: padding!, child: current);
    if (style != null && current != null) {
      // A box changes the style only; the text policy around it stays.
      final outer = DefaultTextStyle.maybeOf(context);
      current = DefaultTextStyle(
        style: DefaultTextStyle.of(context).merge(style),
        softWrap: outer?.softWrap,
        overflow: outer?.overflow,
        maxLines: outer?.maxLines,
        child: current,
      );
    }
    if (border != null || background != null || title != null) {
      current = DecoratedBox(
        border: border ?? (title != null ? Border.single : null),
        title: title,
        background: background,
        child: current,
      );
    }
    if (width != null || height != null) {
      current = SizedBox(width: width, height: height, child: current);
    }
    return current ?? const SizedBox();
  }
}

/// Lays its children out one after another along [direction].
class Flex extends MultiChildRenderObjectWidget {
  /// Children along [direction], placed by the given alignments.
  const Flex({
    super.key,
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.spacing = 0,
    super.children,
  });

  /// The axis the children follow.
  final Axis direction;

  /// How the children are placed along the main axis.
  final MainAxisAlignment mainAxisAlignment;

  /// How each child is placed across the main axis.
  final CrossAxisAlignment crossAxisAlignment;

  /// Whether it takes all the main axis or only what its children need.
  final MainAxisSize mainAxisSize;

  /// The cells left between two children.
  final int spacing;

  @override
  RenderFlex createRenderObject(BuildContext context) => RenderFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: mainAxisSize,
    spacing: spacing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderFlex r) {
    r
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..spacing = spacing;
  }
}

/// Lays its children out left to right.
class Row extends Flex {
  /// Children in a row.
  const Row({
    super.key,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.spacing,
    super.children,
  }) : super(direction: Axis.horizontal);
}

/// Lays its children out top to bottom.
class Column extends Flex {
  /// Children in a column, stretched across by default.
  const Column({
    super.key,
    super.mainAxisAlignment,
    super.crossAxisAlignment = CrossAxisAlignment.stretch,
    super.mainAxisSize,
    super.spacing,
    super.children,
  }) : super(direction: Axis.vertical);
}

/// A child of a [Row] or [Column] that takes a share of the space left.
class Flexible extends SingleChildRenderObjectWidget {
  /// A child taking [flex] shares of what is left, fit by [fit].
  const Flexible({
    super.key,
    this.flex = 1,
    this.fit = FlexFit.loose,
    required Widget super.child,
  });

  /// Its share of the space left, against its siblings'.
  final int flex;

  /// Whether the child must fill its share or may take less.
  final FlexFit fit;

  @override
  RenderFlexible createRenderObject(BuildContext context) =>
      RenderFlexible(flex: flex, fit: fit);

  @override
  void updateRenderObject(BuildContext context, RenderFlexible r) {
    r
      ..flex = flex
      ..fit = fit;
  }
}

/// A [Flexible] whose child fills its share.
class Expanded extends Flexible {
  /// A child filling [flex] shares of what is left.
  const Expanded({super.key, super.flex, required super.child})
    : super(fit: FlexFit.tight);
}

/// Empty space that takes its share of a row or column.
class Spacer extends StatelessWidget {
  /// Space taking [flex] shares.
  const Spacer({super.key, this.flex = 1});

  /// Its share of the space left, against its siblings'.
  final int flex;

  @override
  Widget build(BuildContext context) =>
      Expanded(flex: flex, child: const SizedBox());
}

/// Lays its children over one another, later ones on top.
class Stack extends MultiChildRenderObjectWidget {
  /// Children stacked in order; [Positioned] ones placed by their edges.
  const Stack({super.key, super.children});

  @override
  RenderBox createRenderObject(BuildContext context) => RenderStack();
}

/// Places a child of a [Stack] by its edges' distances from the stack's
/// sides and by its size, in cells, as Flutter's.
///
/// At most two of [left], [right] and [width], and two of [top], [bottom]
/// and [height], may be given. It must be a direct child of the [Stack].
class Positioned extends SingleChildRenderObjectWidget {
  /// A child placed by the given edges and size.
  const Positioned({
    super.key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required Widget super.child,
  }) : assert(
         left == null || right == null || width == null,
         'At most two of left, right and width.',
       ),
       assert(
         top == null || bottom == null || height == null,
         'At most two of top, bottom and height.',
       ),
       assert(width == null || width >= 0, 'A negative width.'),
       assert(height == null || height >= 0, 'A negative height.');

  /// Cells from the stack's left side to the child's.
  final int? left;

  /// Cells from the stack's top to the child's.
  final int? top;

  /// Cells from the child's right side to the stack's.
  final int? right;

  /// Cells from the child's bottom to the stack's.
  final int? bottom;

  /// The child's width.
  final int? width;

  /// The child's height.
  final int? height;

  @override
  RenderPositioned createRenderObject(BuildContext context) {
    // The stack reads the edges from this render object: a box drawn in
    // between would leave them unread.
    RenderBox? parent;
    context.visitAncestorElements((e) {
      if (e is RenderObjectElement) parent = e.renderObject;
      return parent == null;
    });
    if (parent is! RenderStack) {
      throw StateError(
        'A Positioned must be a child of a Stack, with no widget that draws '
        'between them.',
      );
    }
    return RenderPositioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPositioned r) {
    r
      ..left = left
      ..top = top
      ..right = right
      ..bottom = bottom
      ..width = width
      ..height = height;
  }
}

/// Builds with a function, for when a widget class is too much.
class Builder extends StatelessWidget {
  /// A widget that [builder] builds.
  const Builder({super.key, required this.builder});

  /// Builds the widget.
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// Rebuilds whenever [listenable] notifies.
class ListenableBuilder extends StatefulWidget {
  /// Builds with [builder] now and each time [listenable] notifies.
  const ListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });

  /// What it listens to.
  final Listenable listenable;

  /// Builds the widget.
  final Widget Function(BuildContext context) builder;

  @override
  State<ListenableBuilder> createState() => _ListenableBuilderState();
}

class _ListenableBuilderState extends State<ListenableBuilder> {
  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
