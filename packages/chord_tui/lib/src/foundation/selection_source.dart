import 'package:meta/meta.dart';

import '../text/diff.dart';
import '../text/layout.dart';
import '../text/markdown.dart';
import '../text/span.dart';

/// An immutable revision of selectable content and its presentation geometry.
abstract class SelectionSource {
  SelectionSource._();

  /// Text with frozen effective wrapping, alignment and truncation.
  factory SelectionSource.text({
    required Object id,
    required Object revision,
    required TextSpan text,
    TextAlign align = TextAlign.left,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
    SelectionSource? previous,
  }) {
    if (maxLines != null) RangeError.checkNotNegative(maxLines, 'maxLines');
    return _Snapshot(
      id,
      revision,
      SelectionSourceKind.text,
      previous,
      span: _freezeSpan(text),
      geometry: SelectionSourceGeometry(
        align: align,
        softWrap: softWrap,
        overflow: overflow,
        maxLines: maxLines,
      ),
    );
  }

  /// Markdown parsed lazily, retaining compatible fragment identity on edits.
  factory SelectionSource.markdown({
    required Object id,
    required Object revision,
    required String text,
    bool growing = false,
    bool copyCodeBlocks = false,
    Set<String> runCodeBlockLanguages = const {},
    bool quoteBars = true,
    SelectionSource? previous,
  }) => _Snapshot(
    id,
    revision,
    SelectionSourceKind.markdown,
    previous,
    text: text,
    growing: growing,
    geometry: SelectionSourceGeometry(
      copyCodeBlocks: copyCodeBlocks,
      runCodeBlockLanguages: Set.unmodifiable(runCodeBlockLanguages),
      quoteBars: quoteBars,
    ),
  );

  /// Code whose source characters and tabs survive visual wrapping.
  factory SelectionSource.code({
    required Object id,
    required Object revision,
    required String text,
    bool lineNumbers = false,
    bool softWrap = true,
    SelectionSource? previous,
  }) => _Snapshot(
    id,
    revision,
    SelectionSourceKind.code,
    previous,
    text: text,
    geometry: SelectionSourceGeometry(
      lineNumbers: lineNumbers,
      softWrap: softWrap,
    ),
  );

  /// Only the selected diff rows, with a frozen decorative title policy.
  factory SelectionSource.diff({
    required Object id,
    required Object revision,
    required DiffView view,
    String? title,
    bool showTitle = true,
    DiffWrap wrap = DiffWrap.keepSpaces,
    int codeInsetRight = 0,
    SelectionSource? previous,
  }) {
    if (codeInsetRight < 0) {
      throw ArgumentError.value(codeInsetRight, 'codeInsetRight');
    }
    return _Snapshot(
      id,
      revision,
      SelectionSourceKind.diff,
      previous,
      view: freezeDiffView(view),
      geometry: SelectionSourceGeometry(
        title: title ?? view.model.path,
        showTitle: showTitle,
        diffWrap: wrap,
        diffCodeInsetRight: codeInsetRight,
      ),
    );
  }

  /// Ordered child sources with explicit copy separators and shaping insets.
  factory SelectionSource.group({
    required Object id,
    required Object revision,
    required List<SelectionSourceChild> children,
    SelectionSource? previous,
  }) {
    final ids = <Object>{id};
    void validate(SelectionSource source) {
      if (!ids.add(source.id)) {
        throw ArgumentError('Source IDs must be unique within a group.');
      }
      for (final child in source.children) {
        validate(child);
      }
    }

    for (final child in children) {
      if (child.insetLeft < 0 || child.insetRight < 0) {
        throw ArgumentError('Source insets must not be negative.');
      }
      validate(child.source);
    }
    return _Snapshot(
      id,
      revision,
      SelectionSourceKind.group,
      previous,
      slots: List.unmodifiable(children),
    );
  }

  /// The caller's stable logical root identity, independent of virtual mounting.
  Object get id;

  /// The caller's immutable content and geometry revision.
  Object get revision;

  /// Current logical children in document order, in an unmodifiable list.
  List<SelectionSource> get children;

  /// Finds exactly one descendant by logical ID; absence is an error.
  SelectionSource child(Object id);

  /// Code descriptors in Markdown traversal order, without mounting widgets.
  List<MarkdownCodeBlock> get codeBlocks;

  /// Frozen exact language names whose closed Markdown frames reserve run controls.
  Set<String> get runCodeBlockLanguages;
}

/// One group child and the geometry and copy boundary before it.
@immutable
class SelectionSourceChild {
  /// Places [source] inside nonnegative horizontal insets.
  const SelectionSourceChild({
    required this.source,
    this.insetLeft = 0,
    this.insetRight = 0,
    this.separatorBefore = '\n',
    this.selectable = true,
  });

  /// The immutable current child snapshot.
  final SelectionSource source;

  /// Cells before the child within the offered width.
  final int insetLeft;

  /// Cells after the child within the offered width.
  final int insetRight;

  /// Text between this child and its predecessor; ignored for the first child.
  final String separatorBefore;

  /// Whether this child contributes selection while retaining its geometry.
  /// False excludes its whole subtree in this parent, not the standalone source.
  final bool selectable;
}

/// A framework-issued code identity scoped to its surviving source fragment.
@immutable
class CodeBlockId {
  CodeBlockId._(this.sourceId, this._fragment);

  /// The logical source containing this block.
  final Object sourceId;
  final Object _fragment;

  @override
  bool operator ==(Object other) =>
      other is CodeBlockId &&
      other.sourceId == sourceId &&
      other._fragment == _fragment;
  @override
  int get hashCode => Object.hash(sourceId, _fragment);
}

/// A code block's immutable source and parser metadata.
@immutable
class MarkdownCodeBlock {
  /// A descriptor supplied by a current Markdown source.
  const MarkdownCodeBlock({
    required this.id,
    required this.revision,
    required this.text,
    required this.language,
    required this.complete,
  });

  /// Opaque identity retained only through compatible source edits.
  final CodeBlockId id;

  /// The revision that supplied this text and metadata.
  final Object revision;

  /// The whole code, excluding the parser's structural final newline.
  final String text;

  /// The fence language label, when present.
  final String? language;

  /// Whether the parser consumed a closer or the code was indented.
  final bool complete;
}

/// The renderer family a source can bind to.
@internal
enum SelectionSourceKind {
  /// Plain styled text.
  text,

  /// Parsed Markdown blocks.
  markdown,

  /// Code with optional numbering.
  code,

  /// Selected diff rows.
  diff,

  /// Ordered child sources.
  group,
}

/// Effective presentation geometry, shared by mounted and offscreen shaping.
@internal
@immutable
class SelectionSourceGeometry {
  /// Stores only options that can change cells or extents.
  const SelectionSourceGeometry({
    this.align = TextAlign.left,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.maxLines,
    this.lineNumbers = false,
    this.title,
    this.showTitle = true,
    this.diffWrap = DiffWrap.keepSpaces,
    this.diffCodeInsetRight = 0,
    this.copyCodeBlocks = false,
    this.runCodeBlockLanguages = const {},
    this.quoteBars = true,
  });

  /// Text alignment within its actual constrained box.
  final TextAlign align;

  /// Whether source lines wrap.
  final bool softWrap;

  /// How text outside its allowed lines and width ends.
  final TextOverflow overflow;

  /// The effective text line limit, or no limit.
  final int? maxLines;

  /// Whether code has a line-number gutter.
  final bool lineNumbers;

  /// The resolved decorative diff title.
  final String? title;

  /// Whether a present diff title takes a row.
  final bool showTitle;

  /// How a diff's long code rows wrap.
  final DiffWrap diffWrap;

  /// Cells a diff's code wrap room keeps free at the right.
  final int diffCodeInsetRight;

  /// Whether eligible Markdown code frames reserve copy-control geometry.
  final bool copyCodeBlocks;

  /// Exact application-supplied language eligibility, without aliases or parsing.
  final Set<String> runCodeBlockLanguages;

  /// Whether a Markdown quote is drawn behind a bar, dim and italic; else
  /// it reads as the text around it.
  final bool quoteBars;
}

/// An immutable parsed fragment or container with an opaque stable token.
@internal
@immutable
class SelectionSourceNode {
  SelectionSourceNode._(
    this.id,
    this.kind,
    this.fingerprint,
    this.block,
    List<SelectionSourceNode> children, {
    this.item,
  }) : children = List.unmodifiable(children);

  /// Fragment identity, never a parser ordinal.
  final Object id;

  /// Parent-compatible serialization class.
  final String kind;

  /// A diagnostic fingerprint, always confirmed against typed semantic data.
  final String fingerprint;

  /// The parser-owned immutable block, or null for a list item/source leaf.
  final MdBlock? block;

  /// Actual list-item metadata, independent of its diagnostic description.
  final MdItem? item;

  /// Nested fragments in document order.
  final List<SelectionSourceNode> children;
}

class _ParsedSource {
  _ParsedSource(this.parser, this.nodes);
  final MarkdownParser? parser;
  final List<SelectionSourceNode> nodes;
}

class _Snapshot extends SelectionSource {
  _Snapshot(
    this.id,
    this.revision,
    this.kind,
    SelectionSource? previous, {
    this.span,
    this.text = '',
    this.view,
    this.growing = false,
    this.geometry = const SelectionSourceGeometry(),
    this.slots = const [],
  }) : super._() {
    if (previous != null) {
      final old = previous as _Snapshot;
      if (old.id != id || old.kind != kind) {
        throw ArgumentError(
          'A previous source needs the same root ID and kind.',
        );
      }
      if (old.revision == revision) {
        throw ArgumentError('A revised source needs a changed revision.');
      }
      _identity = old._identity;
      // Unobserved revisions retain one parsed base, never previous snapshots.
      _base = old._parsed ?? old._base;
    }
    _children = List.unmodifiable(slots.map((slot) => slot.source));
  }
  @override
  final Object id;
  @override
  final Object revision;
  final SelectionSourceKind kind;
  final TextSpan? span;
  final String text;
  final DiffView? view;
  final bool growing;
  final SelectionSourceGeometry geometry;
  final List<SelectionSourceChild> slots;
  Object _identity = Object();
  late final List<SelectionSource> _children;
  _ParsedSource? _base;
  _ParsedSource? _parsed;
  List<MarkdownCodeBlock>? _codeBlocks;

  @override
  List<SelectionSource> get children => _children;

  @override
  Set<String> get runCodeBlockLanguages => geometry.runCodeBlockLanguages;

  @override
  SelectionSource child(Object id) {
    SelectionSource? found;
    void visit(SelectionSource source) {
      if (source.id == id) {
        if (found != null) throw StateError('The source ID is ambiguous.');
        found = source;
      }
      for (final child in source.children) {
        visit(child);
      }
    }

    for (final source in children) {
      visit(source);
    }
    return found ?? (throw StateError('The source ID is absent.'));
  }

  List<SelectionSourceNode> get nodes {
    final parsed = _parsed;
    if (parsed != null) return parsed.nodes;
    final base = _base;
    if (kind == SelectionSourceKind.markdown) {
      final parser = base?.parser == null
          ? MarkdownParser()
          : MarkdownParser.fork(base!.parser!);
      final blocks = parser.update(text);
      final known = Map<MdBlock, SelectionSourceNode>.identity();
      for (final node in base?.nodes ?? const <SelectionSourceNode>[]) {
        if (node.block case final block?) known[block] = node;
      }
      final fresh = [for (final block in blocks) known[block] ?? _node(block)];
      _parsed = _ParsedSource(
        parser,
        _reconcile(base?.nodes ?? const [], fresh),
      );
    } else {
      _parsed = _ParsedSource(
        null,
        List.unmodifiable([
          SelectionSourceNode._(
            _identity,
            kind.name,
            kind.name,
            null,
            const [],
          ),
        ]),
      );
    }
    _base = null;
    return _parsed!.nodes;
  }

  @override
  List<MarkdownCodeBlock> get codeBlocks => _codeBlocks ??= List.unmodifiable(
    kind == SelectionSourceKind.group
        ? [
            for (final slot in slots)
              if (slot.selectable) ...slot.source.codeBlocks,
          ]
        : kind != SelectionSourceKind.markdown
        ? const <MarkdownCodeBlock>[]
        : [
            for (final node in _walk(nodes))
              if (node.block case MdCode(
                :final code,
                :final language,
                :final complete,
              ))
                MarkdownCodeBlock(
                  id: CodeBlockId._(id, node.id),
                  revision: revision,
                  text: code,
                  language: language,
                  complete: complete,
                ),
          ],
  );
}

TextSpan _freezeSpan(TextSpan span) => TextSpan(
  span.text,
  style: span.style,
  children: List.unmodifiable(span.children.map(_freezeSpan)),
);

Iterable<SelectionSourceNode> _walk(List<SelectionSourceNode> nodes) sync* {
  for (final node in nodes) {
    yield node;
    yield* _walk(node.children);
  }
}

SelectionSourceNode _node(MdBlock block, {bool quoted = false}) {
  final kind = switch (block) {
    MdCode() => quoted ? 'quoted-code' : 'code',
    MdList() => quoted ? 'quoted-list' : 'list',
    _ => block.runtimeType.toString(),
  };
  final children = switch (block) {
    MdQuote(:final blocks) => [
      for (final child in blocks) _node(child, quoted: true),
    ],
    MdList(:final items) => [
      for (final item in items)
        SelectionSourceNode._(Object(), 'list-item', item.describe(), null, [
          for (final child in item.blocks) _node(child, quoted: quoted),
        ], item: item),
    ],
    _ => const <SelectionSourceNode>[],
  };
  return SelectionSourceNode._(
    Object(),
    kind,
    block.describe(),
    block,
    children,
  );
}

class _NodeSemanticKey {
  const _NodeSemanticKey(this.node);
  final SelectionSourceNode node;
  @override
  int get hashCode => Object.hash(node.kind, node.fingerprint);
  @override
  bool operator ==(Object other) =>
      other is _NodeSemanticKey &&
      node.kind == other.node.kind &&
      _sameNodeData(node, other.node);
}

bool _sameNodeData(SelectionSourceNode a, SelectionSourceNode b) {
  if (identical(a, b)) return true;
  if (a.item case final item?) {
    return b.item != null && _sameItem(item, b.item!);
  }
  final block = a.block, other = b.block;
  return block != null && other != null && _sameBlock(block, other);
}

bool _sameList<T>(List<T> a, List<T> b, bool Function(T, T) same) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!same(a[i], b[i])) return false;
  }
  return true;
}

bool _sameItem(MdItem a, MdItem b) =>
    a.checked == b.checked && _sameList(a.blocks, b.blocks, _sameBlock);

bool _sameBlock(MdBlock a, MdBlock b) {
  if (identical(a, b)) return true;
  return switch ((a, b)) {
    (MdParagraph(inlines: final left), MdParagraph(inlines: final right)) =>
      _sameList(left, right, _sameInline),
    (
      MdHeading(level: final x, inlines: final left),
      MdHeading(level: final y, inlines: final right),
    ) =>
      x == y && _sameList(left, right, _sameInline),
    // Closure changes eligibility, not the identity of the source characters.
    (
      MdCode(language: final x, code: final left),
      MdCode(language: final y, code: final right),
    ) =>
      x == y && left == right,
    (
      MdList(
        ordered: final x,
        start: final xs,
        loose: final xl,
        items: final left,
      ),
      MdList(
        ordered: final y,
        start: final ys,
        loose: final yl,
        items: final right,
      ),
    ) =>
      x == y && xs == ys && xl == yl && _sameList(left, right, _sameItem),
    (MdQuote(blocks: final left), MdQuote(blocks: final right)) => _sameList(
      left,
      right,
      _sameBlock,
    ),
    (MdRule(), MdRule()) => true,
    (
      MdDefinition(
        source: final xs,
        label: final xl,
        destination: final xd,
        title: final xt,
      ),
      MdDefinition(
        source: final ys,
        label: final yl,
        destination: final yd,
        title: final yt,
      ),
    ) =>
      xs == ys && xl == yl && xd == yd && xt == yt,
    (
      MdTable(aligns: final xa, header: final xh, rows: final xr),
      MdTable(aligns: final ya, header: final yh, rows: final yr),
    ) =>
      _sameList(xa, ya, (x, y) => x == y) &&
          _sameList(xh, yh, (x, y) => _sameList(x, y, _sameInline)) &&
          _sameList(
            xr,
            yr,
            (x, y) =>
                _sameList(x, y, (xs, ys) => _sameList(xs, ys, _sameInline)),
          ),
    _ => false,
  };
}

bool _sameInline(MdInline a, MdInline b) => switch ((a, b)) {
  (MdText(text: final x), MdText(text: final y)) => x == y,
  (
    MdStyled(kind: final x, children: final xs),
    MdStyled(kind: final y, children: final ys),
  ) =>
    x == y && _sameList(xs, ys, _sameInline),
  (MdCodeSpan(code: final x), MdCodeSpan(code: final y)) => x == y,
  (
    MdLink(url: final x, children: final xs),
    MdLink(url: final y, children: final ys),
  ) =>
    x == y && _sameList(xs, ys, _sameInline),
  (
    MdImage(url: final x, alt: final xa),
    MdImage(url: final y, alt: final ya),
  ) =>
    x == y && xa == ya,
  (MdBreak(), MdBreak()) => true,
  _ => false,
};

List<SelectionSourceNode> _reconcile(
  List<SelectionSourceNode> old,
  List<SelectionSourceNode> fresh,
) {
  final oldByKey = <_NodeSemanticKey, List<int>>{};
  final newByKey = <_NodeSemanticKey, List<int>>{};
  for (final (i, node) in old.indexed) {
    (oldByKey[_NodeSemanticKey(node)] ??= []).add(i);
  }
  for (final (i, node) in fresh.indexed) {
    (newByKey[_NodeSemanticKey(node)] ??= []).add(i);
  }
  final candidates = <(int, int)>[];
  for (final MapEntry(key: key, value: positions) in oldByKey.entries) {
    final next = newByKey[key];
    if (positions.length == 1 && next?.length == 1) {
      candidates.add((positions.single, next!.single));
    }
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final matches = <int, int>{};
  final suffixMinimum = List<int>.filled(candidates.length + 1, fresh.length);
  for (var i = candidates.length - 1; i >= 0; i--) {
    final position = candidates[i].$2;
    suffixMinimum[i] = position < suffixMinimum[i + 1]
        ? position
        : suffixMinimum[i + 1];
  }
  var prefixMaximum = -1;
  for (var i = 0; i < candidates.length; i++) {
    final pair = candidates[i];
    if (prefixMaximum < pair.$2 && pair.$2 < suffixMinimum[i + 1]) {
      matches[pair.$2] = pair.$1;
    }
    if (pair.$2 > prefixMaximum) prefixMaximum = pair.$2;
  }
  final anchors = [
    (-1, -1),
    for (final entry in matches.entries) (entry.value, entry.key),
    (old.length, fresh.length),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (var i = 1; i < anchors.length; i++) {
    final before = anchors[i - 1], after = anchors[i];
    if (after.$1 - before.$1 != 2 || after.$2 - before.$2 != 2) continue;
    final previous = before.$1 + 1, current = before.$2 + 1;
    if (old[previous].kind == fresh[current].kind) matches[current] = previous;
  }
  return List.unmodifiable([
    for (final (i, node) in fresh.indexed)
      if (matches[i] case final previous?)
        if (identical(old[previous], node))
          node
        else
          SelectionSourceNode._(
            old[previous].id,
            node.kind,
            node.fingerprint,
            node.block,
            _reconcile(old[previous].children, node.children),
            item: node.item,
          )
      else
        node,
  ]);
}

/// The source's renderer family, checked by bound constructors.
@internal
SelectionSourceKind selectionSourceKind(SelectionSource source) =>
    (source as _Snapshot).kind;

/// The source's immutable text span.
@internal
TextSpan selectionSourceSpan(SelectionSource source) =>
    (source as _Snapshot).span!;

/// The source's raw Markdown or code string.
@internal
String selectionSourceText(SelectionSource source) =>
    (source as _Snapshot).text;

/// The source's frozen selected diff view.
@internal
DiffView selectionSourceDiff(SelectionSource source) =>
    (source as _Snapshot).view!;

/// The source's effective presentation geometry.
@internal
SelectionSourceGeometry selectionSourceGeometry(SelectionSource source) =>
    (source as _Snapshot).geometry;

/// Whether a Markdown snapshot is growing.
@internal
bool selectionSourceGrowing(SelectionSource source) =>
    (source as _Snapshot).growing;

/// Resolves parsed nodes lazily, without building widgets.
@internal
List<SelectionSourceNode> selectionSourceNodes(SelectionSource source) =>
    (source as _Snapshot).nodes;

/// The group slots, retaining explicit separators and insets.
@internal
List<SelectionSourceChild> selectionSourceSlots(SelectionSource source) =>
    (source as _Snapshot).slots;

/// Counts parsed bases retained before lazy extraction, never revision chains.
@internal
int selectionSourceRetainedBases(SelectionSource source) =>
    (source as _Snapshot)._base == null ? 0 : 1;

/// Gets the opaque fragment addressed by a code ID.
@internal
Object selectionCodeFragment(CodeBlockId id) => id._fragment;

/// Rejects binding a content widget to another renderer family.
@internal
void checkSelectionSourceKind(
  SelectionSource source,
  SelectionSourceKind kind,
) {
  if (selectionSourceKind(source) != kind) {
    throw ArgumentError('The selection source has the wrong content kind.');
  }
}

/// A bound widget can only repeat the source's frozen effective geometry.
@internal
void checkSelectionGeometry(Object? override, Object? expected, String name) {
  if (override != null && override != expected) {
    throw ArgumentError.value(
      override,
      name,
      'must agree with the selection source',
    );
  }
}
