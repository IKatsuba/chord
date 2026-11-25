import 'package:meta/meta.dart';

import 'package:markdown/markdown.dart' as md;

/// A top-level or nested block of a Markdown text.
sealed class MdBlock {
  const MdBlock();

  /// A canonical description, for comparing parses in tests.
  String describe();
}

/// A paragraph: inline content whose soft breaks are spaces.
final class MdParagraph extends MdBlock {
  /// A paragraph of [inlines].
  const MdParagraph(this.inlines);

  /// Its content.
  final List<MdInline> inlines;

  @override
  String describe() => 'p(${_all(inlines)})';
}

/// A heading of [level] 1 to 6.
final class MdHeading extends MdBlock {
  /// A heading of [level] holding [inlines].
  const MdHeading(this.level, this.inlines);

  /// 1 for `#`, up to 6.
  final int level;

  /// Its content.
  final List<MdInline> inlines;

  @override
  String describe() => 'h$level(${_all(inlines)})';
}

/// A code block: fenced, with the fence's first word, or indented.
final class MdCode extends MdBlock {
  /// [code] under the fence label [language].
  const MdCode(this.language, this.code, {this.complete = true});

  /// The fence label's first word; null for none or an indented block.
  final String? language;

  /// The code, without the fence's own final line break.
  final String code;

  /// Whether this is indented code or the parser consumed a closing fence.
  final bool complete;

  @override
  String describe() => 'code[$language](${_quote(code)})';
}

/// A bulleted or numbered list.
final class MdList extends MdBlock {
  /// A list of [items].
  const MdList({
    required this.ordered,
    required this.start,
    required this.loose,
    required this.items,
  });

  /// Whether items are numbered.
  final bool ordered;

  /// The first item's number, for a numbered list.
  final int start;

  /// Whether a blank row separates items and the blocks within them.
  final bool loose;

  /// Its items, in order.
  final List<MdItem> items;

  @override
  String describe() =>
      '${ordered ? 'ol$start' : 'ul'}${loose ? ' loose' : ''}'
      '(${items.map((i) => i.describe()).join(', ')})';
}

/// One list item: its task state, and its blocks.
final class MdItem {
  /// An item of [blocks]; [checked] is null when it is no task.
  const MdItem(this.checked, this.blocks);

  /// A task's state: `[x]` true, `[ ]` false; null for a plain item.
  final bool? checked;

  /// Its content.
  final List<MdBlock> blocks;

  /// A canonical description, for comparing parses in tests.
  String describe() =>
      'li${switch (checked) {
        null => '',
        true => '[x]',
        false => '[ ]',
      }}(${blocks.map((b) => b.describe()).join(', ')})';
}

/// A block quote.
final class MdQuote extends MdBlock {
  /// A quote of [blocks].
  const MdQuote(this.blocks);

  /// Its content.
  final List<MdBlock> blocks;

  @override
  String describe() => 'quote(${blocks.map((b) => b.describe()).join(', ')})';
}

/// A thematic break.
final class MdRule extends MdBlock {
  /// A rule.
  const MdRule();

  @override
  String describe() => 'hr';
}

/// A reference definition, shown as written, where it stands.
final class MdDefinition extends MdBlock {
  /// A definition written as [source].
  const MdDefinition(
    this.source, {
    this.label,
    this.destination = '',
    this.title,
  });

  /// Its lines, as written.
  final String source;

  /// The label it defines, normalized; null when an earlier definition of
  /// the same label wins.
  final String? label;

  /// Where its label's links go.
  final String destination;

  /// Its title, if it has one.
  final String? title;

  @override
  String describe() => 'def[${label ?? ''}](${_quote(source)})';
}

/// How a table column aligns its cells.
enum MdAlign {
  /// No alignment given.
  none,

  /// Against the left edge.
  left,

  /// Centred.
  center,

  /// Against the right edge.
  right,
}

/// A table: its heading row and its body rows, cells of inline content.
final class MdTable extends MdBlock {
  /// A table of [header] and [rows] aligned by [aligns].
  const MdTable(this.aligns, this.header, this.rows);

  /// Each column's alignment, as the delimiter row says.
  final List<MdAlign> aligns;

  /// The heading row's cells.
  final List<List<MdInline>> header;

  /// The body rows; a row being typed may have fewer cells.
  final List<List<List<MdInline>>> rows;

  @override
  String describe() =>
      'table(${aligns.map((a) => a.name).join(' ')}; '
      '${[header, ...rows].map((r) => r.map(_all).join(' | ')).join('; ')})';
}

/// A piece of inline content.
sealed class MdInline {
  const MdInline();

  /// A canonical description, for comparing parses in tests.
  String describe();
}

/// Plain text.
final class MdText extends MdInline {
  /// [text] as it is.
  const MdText(this.text);

  /// The text.
  final String text;

  @override
  String describe() => _quote(text);
}

/// Bold, italic or struck-through content.
final class MdStyled extends MdInline {
  /// [children] drawn as [kind].
  const MdStyled(this.kind, this.children);

  /// Which emphasis.
  final MdEmphasis kind;

  /// What it holds.
  final List<MdInline> children;

  @override
  String describe() => '${kind.name}(${_all(children)})';
}

/// The kinds of inline emphasis.
enum MdEmphasis {
  /// Strong emphasis, `**text**`.
  strong,

  /// Emphasis, `*text*`.
  emphasis,

  /// Struck through, `~~text~~`.
  strikethrough,
}

/// Inline code.
final class MdCodeSpan extends MdInline {
  /// [code] as it is.
  const MdCodeSpan(this.code);

  /// The code.
  final String code;

  @override
  String describe() => 'code(${_quote(code)})';
}

/// A link: its text and where it goes.
final class MdLink extends MdInline {
  /// A link to [url] shown as [children].
  const MdLink(this.url, this.children);

  /// Where it goes.
  final String url;

  /// Its text.
  final List<MdInline> children;

  @override
  String describe() => 'link[$url](${_all(children)})';
}

/// An image, which a terminal shows by its description.
final class MdImage extends MdInline {
  /// An image at [url] described as [alt].
  const MdImage(this.url, this.alt);

  /// Where it is.
  final String url;

  /// Its description.
  final String alt;

  @override
  String describe() => 'image[$url](${_quote(alt)})';
}

/// A hard line break.
final class MdBreak extends MdInline {
  /// A break.
  const MdBreak();

  @override
  String describe() => 'br';
}

String _all(List<MdInline> inlines) =>
    inlines.map((i) => i.describe()).join(' ');

String _quote(String text) => '"${text.replaceAll('\n', r'\n')}"';

/// A Markdown text parsed into blocks, kept between updates so that text
/// appended to it is parsed from its last block on, not from the start.
///
/// A text that grows chunk by chunk, as an agent's reply does, re-parses
/// only its active tail: every top-level block but the last is frozen, as
/// nothing appended can change it, but for a reference definition, which
/// can change links above it: when an append changes the text's
/// definitions, or is no append at all, the whole text is parsed again.
class MarkdownParser {
  /// Starts an independent parser with no retained source.
  MarkdownParser();

  /// Copies immutable parsed blocks and independent continuation bookkeeping.
  MarkdownParser.fork(MarkdownParser previous) {
    _text = previous._text;
    _frozen = previous._frozen;
    _blocks = previous._blocks;
    _cut = previous._cut;
    _frozenReferences = Map.of(previous._frozenReferences);
    _references = Map.of(previous._references);
  }

  String _text = '';
  List<MdBlock> _frozen = const [];
  List<MdBlock> _blocks = const [];

  /// Where the active tail starts in the text: a line's first character.
  int _cut = 0;

  /// The definitions in the frozen blocks, which every tail parse starts
  /// from, so links in the tail resolve against them.
  _References _frozenReferences = {};

  /// Every definition of the text, as the last parse found them.
  _References _references = {};

  /// The blocks of the text given last.
  List<MdBlock> get blocks => _blocks;

  /// How many leading blocks are frozen; for tests and benchmarks.
  int get frozenCount => _frozen.length;

  /// Parses [text], reusing what the last update parsed when [text] only
  /// appends to it.
  List<MdBlock> update(String text) {
    _markdownUpdateCalls++;
    if (identical(text, _text) || text == _text) return _blocks;
    _markdownChangedUpdates++;
    final appended = text.length > _text.length && text.startsWith(_text);
    _text = text;
    if (!appended) _reset();
    final before = _references;
    _parseTail();
    // A definition that arrived, or changed, as the tail grew can change a
    // link in a frozen block: the definition is only known once the package
    // has read it whole, which may be lines after its label began.
    if (appended && _frozen.isNotEmpty && !_same(before, _references)) {
      _reset();
      _parseTail();
    }
    return _blocks;
  }

  void _reset() {
    _frozen = const [];
    _frozenReferences = {};
    _cut = 0;
  }

  void _parseTail() {
    _markdownTailParses++;
    final tail = _text.substring(_cut);
    final lines = [
      for (final line in tail.split('\n'))
        md.Line(
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
        ),
    ];
    final document = _newDocument()
      ..linkReferences.addAll({
        for (final MapEntry(:key, value: (destination, title))
            in _frozenReferences.entries)
          key: md.LinkReference(key, destination, title),
      });
    final ends = _Recording(lines);
    _recording = ends;
    final List<md.Node> nodes;
    try {
      nodes = document.parseLineList(lines);
    } finally {
      _recording = null;
    }
    _references = {
      for (final MapEntry(:key, :value) in document.linkReferences.entries)
        key: (value.destination, value.title),
    };
    final converted = [for (final node in nodes) _block(node)];
    _blocks = List.unmodifiable([..._frozen, ...converted.nonNulls]);
    if (nodes.length < 2) return;

    // Freeze every block but the last: the tail starts again at the line
    // after the one before the last ends.
    final end = ends.ends[nodes[nodes.length - 2]];
    if (end == null) return;
    final kept = converted.sublist(0, converted.length - 1).nonNulls.toList();
    var offset = _cut;
    for (var i = 0; i < end; i++) {
      offset = _text.indexOf('\n', offset) + 1;
    }
    _frozen = List.unmodifiable([..._frozen, ...kept]);
    _frozenReferences = {..._frozenReferences};
    for (final block in kept) {
      _collect(block, _frozenReferences);
    }
    _cut = offset;
  }
}

/// Definitions by their normalized label: destination and title.
typedef _References = Map<String, (String, String?)>;

bool _same(_References a, _References b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// The definitions [block] registered, into [into], in order.
void _collect(MdBlock block, _References into) {
  switch (block) {
    case MdDefinition(:final label?, :final destination, :final title):
      into.putIfAbsent(label, () => (destination, title));
    case MdQuote(:final blocks):
      for (final b in blocks) {
        _collect(b, into);
      }
    case MdList(:final items):
      for (final item in items) {
        for (final b in item.blocks) {
          _collect(b, into);
        }
      }
    default:
  }
}

/// chord's markdown: GitHub's, as marked reads it, without footnotes,
/// emoji codes or HTML: raw HTML stays text.
md.Document _newDocument() => md.Document(
  encodeHtml: false,
  withDefaultBlockSyntaxes: false,
  withDefaultInlineSyntaxes: true,
  blockSyntaxes: const [
    _FencedCode(),
    _Table(),
    _UnorderedChecklist(),
    _OrderedChecklist(),
    md.EmptyBlockSyntax(),
    _HtmlBlock(),
    _Setext(),
    _Header(),
    _IndentedCode(),
    _Blockquote(),
    _Rule(),
    _Unordered(),
    _Ordered(),
    _Definition(),
    _Paragraph(),
  ],
  inlineSyntaxes: [md.StrikethroughSyntax(), md.AutolinkExtensionSyntax()],
);

/// Where each top-level block of one parse ends: the index of the line
/// after it. The package keeps its position private and its nodes carry
/// none, so each syntax notes it through its public `parse`.
class _Recording {
  _Recording(this.lines)
    : _index = Map.identity()
        ..addAll({for (final (i, l) in lines.indexed) l: i});

  final List<md.Line> lines;
  final Map<md.Line, int> _index;
  final ends = Map<md.Node, int>.identity();
  final fenceClosures = Map<md.BlockParser, bool>.identity();

  /// Where [parser] is in its own lines.
  int position(md.BlockParser parser) {
    if (parser.isDone) return parser.lines.length;
    return identical(parser.lines, lines)
        ? _index[parser.current]!
        : parser.lines.indexOf(parser.current);
  }

  void note(md.BlockParser parser, md.Node? node) {
    // Nested parsers (a quote's, a list item's) read lines of their own.
    if (node == null || !identical(parser.lines, lines)) return;
    ends[node] = parser.isDone ? lines.length : _index[parser.current]!;
  }
}

_Recording? _recording;

/// The package's syntaxes, each noting where its blocks end. Subclasses,
/// so the package's own `is` checks between syntaxes still hold.
mixin _Noted on md.BlockSyntax {
  @override
  md.Node? parse(md.BlockParser parser) {
    final node = super.parse(parser);
    _recording?.note(parser, node);
    return node;
  }
}

/// [_Noted] for the syntaxes whose `parse` always gives a node.
mixin _NotedNode on md.BlockSyntax {
  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser)!;
    _recording?.note(parser, node);
    return node;
  }
}

class _FencedCode extends md.FencedCodeBlockSyntax with _NotedNode {
  const _FencedCode();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser) as md.Element;
    node.attributes['ctui-code-complete'] =
        '${_recording!.fenceClosures.remove(parser) ?? false}';
    return node;
  }

  @override
  List<md.Line> parseChildLines(
    md.BlockParser parser, [
    String openingMarker = '',
    int indent = 0,
  ]) {
    final recording = _recording!;
    final from = recording.position(parser);
    final children = super.parseChildLines(parser, openingMarker, indent);
    final to = recording.position(parser);
    // Read only the final line consumed by the package, through its own
    // public pattern and the opening marker it supplied to this extension.
    final match = to > from + 1
        ? pattern.firstMatch(parser.lines[to - 1].content)
        : null;
    final marker = match?.namedGroup('backtick') ?? match?.namedGroup('tilde');
    final info =
        match?.namedGroup('backtickInfo') ?? match?.namedGroup('tildeInfo');
    recording.fenceClosures[parser] =
        marker != null &&
        marker.startsWith(openingMarker) &&
        info?.trim().isEmpty == true;
    return children;
  }
}

class _Table extends md.TableSyntax with _Noted {
  const _Table();
}

class _UnorderedChecklist extends md.UnorderedListWithCheckboxSyntax
    with _NotedNode {
  const _UnorderedChecklist();
}

class _OrderedChecklist extends md.OrderedListWithCheckboxSyntax
    with _NotedNode {
  const _OrderedChecklist();
}

class _HtmlBlock extends md.HtmlBlockSyntax with _NotedNode {
  const _HtmlBlock();
}

class _Setext extends md.SetextHeaderSyntax with _Noted {
  const _Setext();
}

class _Header extends md.HeaderSyntax with _NotedNode {
  const _Header();
}

class _IndentedCode extends md.CodeBlockSyntax with _NotedNode {
  const _IndentedCode();
}

class _Blockquote extends md.BlockquoteSyntax with _NotedNode {
  const _Blockquote();
}

class _Rule extends md.HorizontalRuleSyntax with _NotedNode {
  const _Rule();
}

class _Unordered extends md.UnorderedListSyntax with _NotedNode {
  const _Unordered();
}

class _Ordered extends md.OrderedListSyntax with _NotedNode {
  const _Ordered();
}

class _Paragraph extends md.ParagraphSyntax with _Noted {
  const _Paragraph();

  @override
  md.Node? parse(md.BlockParser parser) {
    final node = super.parse(parser);
    // CommonMark strips each paragraph line's leading whitespace before
    // inline parsing; markdown 7.3.1 trims only the right end, so a reply
    // starting ' text' kept its space, and so did a line after a hard break.
    if (node case md.Element(
      children: final children? && [md.UnparsedContent(:final textContent)],
    )) {
      children[0] = md.UnparsedContent(textContent.replaceAll(_lineIndent, ''));
    }
    return node;
  }
}

final _lineIndent = RegExp(r'^[ \t]+', multiLine: true);

/// A reference definition kept as a block, as chord shows it, with the
/// label it registered: the package's own syntax reads and registers it,
/// and gives nothing back.
class _Definition extends md.LinkReferenceDefinitionSyntax {
  const _Definition();

  @override
  md.Node? parse(md.BlockParser parser) {
    final recording = _recording!;
    final from = recording.position(parser);
    final references = parser.document.linkReferences;
    final known = references.keys.toSet();
    try {
      super.parse(parser);
    } on RangeError {
      // markdown 7.3.1 reads past the end of a definition whose text ends
      // on the `<` opening its destination (`[a]: <`). Such a destination
      // is unclosed, so no definition: its lines go to the next syntax, as
      // the package gives back any text that is not one.
      parser.retreatBy(recording.position(parser) - from);
      return null;
    }
    final to = recording.position(parser);
    // Not a definition: the package gave its lines back to the next syntax.
    if (to == from) return null;
    final label = references.keys
        .where((key) => !known.contains(key))
        .firstOrNull;
    final reference = label == null ? null : references[label];
    final node = md.Element('definition', [
      md.Text(
        parser.lines.sublist(from, to).map((line) => line.content).join('\n'),
      ),
    ]);
    if (reference != null) {
      node.attributes['label'] = label!;
      node.attributes['destination'] = reference.destination;
      if (reference.title != null) node.attributes['title'] = reference.title!;
    }
    recording.note(parser, node);
    return node;
  }
}

/// The package's node as a block; null for what draws nothing.
MdBlock? _block(md.Node node) {
  if (node is md.Text) {
    // An HTML block: its source, line for line, as text. The package pads
    // it with line breaks for HTML output, after another block or inside
    // one; they are no part of the source.
    final lines = node.text.replaceAll(RegExp(r'^\n+|\n+$'), '').split('\n');
    return MdParagraph([
      for (final (i, line) in lines.indexed) ...[
        if (i > 0) const MdBreak(),
        MdText(line),
      ],
    ]);
  }
  if (node is! md.Element) return null;
  final children = node.children ?? const <md.Node>[];
  switch (node.tag) {
    case 'p':
      return MdParagraph(_inlines(children));
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      return MdHeading(int.parse(node.tag.substring(1)), _inlines(children));
    case 'pre':
      final code = children.whereType<md.Element>().firstOrNull;
      final language = code?.attributes['class'];
      final text = code?.textContent ?? node.textContent;
      return MdCode(
        language != null && language.startsWith('language-')
            ? language.substring('language-'.length)
            : null,
        text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
        complete: node.attributes['ctui-code-complete'] != 'false',
      );
    case 'ul' || 'ol':
      final items = children.whereType<md.Element>().toList();
      return MdList(
        ordered: node.tag == 'ol',
        start: int.tryParse(node.attributes['start'] ?? '') ?? 1,
        loose: items.any(
          (li) => (li.children ?? const []).any(
            (c) => c is md.Element && c.tag == 'p',
          ),
        ),
        items: [for (final li in items) _item(li)],
      );
    case 'blockquote':
      return MdQuote(_blocks(children));
    case 'hr':
      return const MdRule();
    case 'table':
      return _table(node);
    case 'definition':
      return MdDefinition(
        node.textContent,
        label: node.attributes['label'],
        destination: node.attributes['destination'] ?? '',
        title: node.attributes['title'],
      );
  }
  return MdParagraph(_inlines([node]));
}

/// Blocks, with a run of loose inline content (a tight item's text) taken
/// as a paragraph.
List<MdBlock> _blocks(List<md.Node> nodes) {
  final out = <MdBlock>[];
  final run = <md.Node>[];
  void flush() {
    if (run.isEmpty) return;
    out.add(MdParagraph(_inlines(run)));
    run.clear();
  }

  for (final node in nodes) {
    if (node is md.Element && _blockTags.contains(node.tag)) {
      flush();
      final block = _block(node);
      if (block != null) out.add(block);
    } else {
      run.add(node);
    }
  }
  flush();
  return out;
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'ul', 'ol', //
  'blockquote', 'hr', 'table', 'definition',
};

/// A list item, its task box taken out: the package puts it first in the
/// item, or first in its first paragraph when the list is loose.
MdItem _item(md.Element li) {
  var children = li.children ?? const <md.Node>[];
  bool? checked;
  bool isBox(md.Node? node) =>
      node is md.Element &&
      node.tag == 'input' &&
      node.attributes['type'] == 'checkbox';
  final first = children.firstOrNull;
  if (isBox(first)) {
    checked = (first! as md.Element).attributes['checked'] == 'true';
    children = children.sublist(1);
  } else if (first is md.Element &&
      first.tag == 'p' &&
      isBox(first.children?.firstOrNull)) {
    final box = first.children!.first as md.Element;
    checked = box.attributes['checked'] == 'true';
    children = [
      md.Element('p', first.children!.sublist(1)),
      ...children.skip(1),
    ];
  }
  return MdItem(checked, _blocks(children));
}

MdTable _table(md.Element table) {
  List<md.Element> rowsOf(String tag) => [
    for (final section
        in (table.children ?? const <md.Node>[]).whereType<md.Element>().where(
          (e) => e.tag == tag,
        ))
      ...(section.children ?? const <md.Node>[]).whereType<md.Element>(),
  ];
  List<List<MdInline>> cells(md.Element row) => [
    for (final cell
        in (row.children ?? const <md.Node>[]).whereType<md.Element>())
      _inlines(cell.children ?? const []),
  ];
  final head = rowsOf('thead').firstOrNull;
  final headCells = (head?.children ?? const <md.Node>[])
      .whereType<md.Element>();
  return MdTable(
    [
      for (final cell in headCells)
        switch (cell.attributes['align']) {
          'left' => MdAlign.left,
          'center' => MdAlign.center,
          'right' => MdAlign.right,
          _ => MdAlign.none,
        },
    ],
    head == null ? const [] : cells(head),
    [for (final row in rowsOf('tbody')) cells(row)],
  );
}

/// The nodes' inline content, neighbouring texts joined: the package
/// splits text where a syntax was tried and did not match.
List<MdInline> _inlines(List<md.Node> nodes) {
  final out = <MdInline>[];
  for (final inline in [for (final node in nodes) ..._inline(node)]) {
    final last = out.lastOrNull;
    if (inline is MdText && last is MdText) {
      out.last = MdText(last.text + inline.text);
    } else {
      out.add(inline);
    }
  }
  return out;
}

/// One node's inline content: an element it does not know stands for
/// its children.
List<MdInline> _inline(md.Node node) {
  if (node is md.Text) return [MdText(node.text.replaceAll(_softBreak, ' '))];
  if (node is! md.Element) return const [];
  final children = _inlines(node.children ?? const []);
  final inline = switch (node.tag) {
    'strong' => MdStyled(MdEmphasis.strong, children),
    'em' => MdStyled(MdEmphasis.emphasis, children),
    'del' => MdStyled(MdEmphasis.strikethrough, children),
    'code' => MdCodeSpan(node.textContent),
    'a' => MdLink(node.attributes['href'] ?? '', children),
    'img' => MdImage(
      node.attributes['src'] ?? '',
      node.attributes['alt'] ?? '',
    ),
    'br' => const MdBreak(),
    _ => null,
  };
  return inline == null ? children : [inline];
}

/// A soft line break with the spaces around it, which join as one space,
/// as chord's renderer joins a paragraph's lines.
final _softBreak = RegExp(r'[ \t]*\n[ \t]*');

int _markdownUpdateCalls = 0,
    _markdownChangedUpdates = 0,
    _markdownTailParses = 0;

/// Actual parser work, distinguished from unchanged update requests.
@internal
({int updates, int changedUpdates, int tailParses})
get markdownParseDiagnostics => (
  updates: _markdownUpdateCalls,
  changedUpdates: _markdownChangedUpdates,
  tailParses: _markdownTailParses,
);

/// Resets integer counters without changing parser state or retaining parsers.
@internal
void resetMarkdownParseDiagnostics() {
  _markdownUpdateCalls = 0;
  _markdownChangedUpdates = 0;
  _markdownTailParses = 0;
}
