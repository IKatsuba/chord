import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import 'palette.dart';
import 'scroll_page.dart' show pageScrollBindings;
import 'site.dart' show narrowWidth, panelOnly;

/// From this many columns chord_tui's pages show their index beside the
/// article; narrower, it folds into a `PAGES ▾ P` bar.
const articleIndexWidth = 110;

/// From this many columns the "on this page" margin shows.
const articleMarginWidth = 150;

/// The index column's width, and the article's measure.
const indexColumns = 26, articleMeasure = 72, marginColumns = 22;

/// One part of an article under a numbered head.
typedef ArticleSection = ({String head, List<Widget> children});

/// Where chord_tui's pages are: their caps names, Overview first.
typedef ArticlePages = ({List<String> names, void Function(int page) open});

/// Hands `c` to the topmost copyable block whose header is in view, and
/// tells each block whether it is that one.
class CopyOwner extends ChangeNotifier {
  CopyOwner(this._scroll) {
    _scroll.addListener(notifyListeners);
  }

  final ScrollController _scroll;
  final _blocks = <_CopyBlockState>[];

  /// The block `c` copies now, if any header is in view.
  _CopyBlockState? get _active {
    _CopyBlockState? best;
    int? bestRow;
    for (final block in _blocks) {
      final row = Scrollable.rowOf(block.context);
      if (row == null) continue;
      if (row < _scroll.offset || row >= _scroll.offset + _scroll.viewRows) {
        continue;
      }
      if (bestRow == null || row < bestRow) {
        best = block;
        bestRow = row;
      }
    }
    return best;
  }

  /// Copies the active block's text through the app's terminal.
  void copy(BuildContext context) => _active?._copy(context);

  @override
  void dispose() {
    _scroll.removeListener(notifyListeners);
    super.dispose();
  }
}

class _CopyOwnerScope extends InheritedWidget {
  const _CopyOwnerScope({required this.owner, required super.child});

  final CopyOwner owner;

  @override
  bool updateShouldNotify(_CopyOwnerScope oldWidget) =>
      owner != oldWidget.owner;
}

/// A header with `COPY c` when it is the block `c` copies, `COPY` in muted
/// when another is, and `COPIED` for two seconds after a copy.
class CopyHint extends StatefulWidget {
  /// The hint for [text], after [label] on the left of the row.
  const CopyHint({super.key, required this.text, required this.label});

  /// What `c` copies.
  final String text;

  /// What the row says on the left.
  final Widget label;

  @override
  State<CopyHint> createState() => _CopyBlockState();
}

class _CopyBlockState extends State<CopyHint> {
  CopyOwner? _owner;
  var _copied = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context
        .getInheritedWidgetOfExactType<_CopyOwnerScope>()
        ?.owner;
    if (owner != _owner) {
      _owner?._blocks.remove(this);
      _owner = owner?.._blocks.add(this);
    }
  }

  @override
  void dispose() {
    _owner?._blocks.remove(this);
    _timer?.cancel();
    super.dispose();
  }

  void _copy(BuildContext context) {
    TerminalScope.maybeOf(context)?.copyToClipboard(widget.text);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = _owner;
    Widget hint() {
      if (_copied) {
        return Text(
          'COPIED',
          style: theme.accent.merge(Style.bold),
          softWrap: false,
        );
      }
      if (owner?._active != this) {
        return Text('COPY', style: theme.dim, softWrap: false);
      }
      return Text.rich(
        TextSpan(
          '',
          children: [
            TextSpan('COPY ', style: theme.dim),
            TextSpan('c', style: theme.text.merge(Style.bold)),
          ],
        ),
        softWrap: false,
      );
    }

    return Row(
      children: [
        Expanded(child: widget.label),
        if (owner == null)
          hint()
        else
          ListenableBuilder(listenable: owner, builder: (_) => hint()),
      ],
    );
  }
}

/// Code on raised: its file's name and the copy hint, then the code.
class CodeBlock extends StatelessWidget {
  /// [source] under [label].
  const CodeBlock({super.key, required this.label, required this.source});

  /// The file it is, as its header names it.
  final String label;

  /// The code, copied whole by `c`.
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<SitePalette>() ?? const SitePalette();
    return Box(
      background: palette.raised,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CopyHint(
            text: source,
            label: Text(label, style: theme.dim, softWrap: false),
          ),
          Text(''),
          Code(source.trimRight(), language: 'dart'),
        ],
      ),
    );
  }
}

/// One of chord_tui's pages, in C: the index column (or its folded bar),
/// the article in a 72-column measure under its [heading], numbered
/// sections, the pager, and the "on this page" margin. `[` `]` move through
/// the pages, `{` `}` through the sections, and `p` opens the index where
/// it is folded.
class ArticlePage extends StatefulWidget {
  /// Page [page] of [pages].
  const ArticlePage({
    super.key,
    required this.pages,
    required this.page,
    required this.heading,
    required this.sections,
    this.bindings = const [],
  });

  /// chord_tui's pages and how to open one.
  final ArticlePages pages;

  /// This page's place among them.
  final int page;

  /// What comes before the first section: the breadcrumb, the title and
  /// the lede.
  final List<Widget> heading;

  /// The numbered sections.
  final List<ArticleSection> sections;

  /// The page's own keys.
  final List<Binding> bindings;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

final _quitKeys = {KeyCombo.parse('ctrl+q'), KeyCombo.parse('ctrl+c')};

class _ArticlePageState extends State<ArticlePage> {
  final _scroll = ScrollController();
  late final _copies = CopyOwner(_scroll);
  final _heads = <int, BuildContext>{};
  var _indexOpen = false;
  var _indexSelected = 0;

  @override
  void dispose() {
    _copies.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _pageCount => widget.pages.names.length;

  void _go(int page) {
    if (page < 0 || page >= _pageCount || page == widget.page) return;
    widget.pages.open(page);
  }

  // The section the view is in: the last head at or above its top row.
  int get _current {
    var current = 0;
    for (final MapEntry(key: i, value: context) in _heads.entries) {
      final row = Scrollable.rowOf(context);
      if (row != null && row <= _scroll.offset) current = i;
    }
    return current;
  }

  void _section(int step) {
    final target = (_current + step).clamp(0, widget.sections.length - 1);
    // Up from the middle of a section goes to its own head first.
    final head = _heads[target];
    final here = _heads[_current];
    final at = here == null ? null : Scrollable.rowOf(here);
    final to = step < 0 && at != null && at < _scroll.offset ? here : head;
    if (to != null) Scrollable.ensureVisible(to, alignment: 0);
  }

  // Where the focus was when the list opened, to go back to.
  FocusNode? _beforeIndex;

  void _closeIndex() {
    if (!_indexOpen) return;
    setState(() => _indexOpen = false);
    final before = _beforeIndex;
    _beforeIndex = null;
    if (before != null && before.attached) before.requestFocus();
  }

  void _openIndex() => setState(() {
    _beforeIndex = context.owner.focusManager.primaryFocus;
    _indexOpen = true;
    _indexSelected = widget.page;
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final theme = Theme.of(context);
      final wide = width >= articleIndexWidth;
      final margin = width < narrowWidth ? 2 : 4;
      if (wide && _indexOpen) _indexOpen = false;
      final bindings = [
        Binding('[', 'pages', () => _go(widget.page - 1), id: 'article:pages'),
        Binding(']', 'pages', () => _go(widget.page + 1), id: 'article:pages'),
        Binding(
          '{',
          'sections',
          () => _section(-1),
          id: '${panelOnly}article:sections',
        ),
        Binding(
          '}',
          'sections',
          () => _section(1),
          id: '${panelOnly}article:sections',
        ),
        Binding(
          'c',
          'copy',
          () => _copies.copy(context),
          id: '${panelOnly}article:copy',
        ),
        if (!wide) Binding('p', 'pages', _openIndex, id: 'article:index'),
      ];
      final article = _article(theme);
      final scrolled = SingleChildScrollView(
        controller: _scroll,
        child: _CopyOwnerScope(owner: _copies, child: article),
      );
      // One tree at every width, so the article and its live example keep
      // their state as the index folds and unfolds: the index, the article
      // and the margin are always the row's three cells, some of them empty.
      final rail = width >= articleMarginWidth;
      final left = wide ? margin + indexColumns + 4 : margin;
      final room = width - 1 - left - (wide ? 0 : margin);
      final articleWidth = room < articleMeasure ? room : articleMeasure;
      final page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                Text(''),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: margin),
                  child: _bar(theme),
                ),
                Text('─' * (width - 1), style: theme.border, softWrap: false),
              ],
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                Scrollbar(
                  controller: _scroll,
                  thumbStyle: theme.dim,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: left,
                        child: wide
                            ? Padding(
                                padding: EdgeInsets.only(left: margin),
                                child: SizedBox(
                                  width: indexColumns,
                                  child: _index(theme),
                                ),
                              )
                            : null,
                      ),
                      SizedBox(width: articleWidth, child: scrolled),
                      SizedBox(
                        width: wide && rail ? 6 + marginColumns : 0,
                        child: wide && rail
                            ? Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ListenableBuilder(
                                  listenable: _scroll,
                                  builder: (_) => _rail(theme),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_indexOpen)
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: _indexList(theme, margin),
                  ),
              ],
            ),
          ),
        ],
      );
      // The help row reads inner first: scrolling, the page's own keys,
      // then the pages.
      return Actions(
        bindings: bindings,
        child: Actions(
          bindings: widget.bindings,
          child: Actions(
            bindings: pageScrollBindings(_scroll),
            child: Focus(autofocus: true, child: page),
          ),
        ),
      );
    },
  );

  Widget _article(ThemeData theme) {
    final accent = theme.accent.merge(Style.bold);
    final names = widget.pages.names;
    final previous = widget.page - 1, next = widget.page + 1;
    String label(int i) => '${i.toString().padLeft(2, '0')} ${names[i]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(''),
        Text(''),
        ...widget.heading,
        for (final (i, section) in widget.sections.indexed) ...[
          Text(''),
          Text(''),
          Builder(
            builder: (context) {
              _heads[i] = context;
              return Text.rich(
                TextSpan(
                  '',
                  children: [
                    TextSpan(
                      '${(i + 1).toString().padLeft(2, '0')}  ',
                      style: accent,
                    ),
                    TextSpan(
                      section.head.toUpperCase(),
                      style: theme.text.merge(Style.bold),
                    ),
                  ],
                ),
                softWrap: false,
              );
            },
          ),
          LayoutBuilder(
            builder: (context, c) =>
                Text('─' * c.maxWidth, style: theme.border, softWrap: false),
          ),
          Text(''),
          ...section.children,
        ],
        Text(''),
        Text(''),
        LayoutBuilder(
          builder: (context, c) =>
              Text('─' * c.maxWidth, style: theme.border, softWrap: false),
        ),
        Row(
          children: [
            if (previous >= 0)
              _tap(
                () => _go(previous),
                Text('[  ← ${label(previous)}', style: accent, softWrap: false),
              ),
            const Spacer(),
            if (next < names.length)
              _tap(
                () => _go(next),
                Text('${label(next)} →  ]', style: accent, softWrap: false),
              ),
          ],
        ),
        Text(''),
      ],
    );
  }

  Widget _tap(void Function() onTap, Widget child) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (event.button == MouseButton.primary) onTap();
    },
    child: child,
  );

  Widget _indexRow(ThemeData theme, int i, {bool marked = false}) {
    final current = i == widget.page;
    return _tap(
      () => _go(i),
      Text.rich(
        // A child without a colour keeps its parent's: each part its own.
        TextSpan(
          '',
          children: [
            if (marked) TextSpan('❯ ', style: theme.accent.merge(Style.bold)),
            TextSpan(
              '${i.toString().padLeft(2, '0')}  ',
              style: current ? theme.accent.merge(Style.bold) : theme.dim,
            ),
            TextSpan(
              widget.pages.names[i],
              style: current
                  ? theme.text.merge(const Style(bold: true, inverse: true))
                  : theme.text,
            ),
          ],
        ),
        softWrap: false,
      ),
    );
  }

  /// The index column: the section, the pages, and their keys.
  Widget _index(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(''),
      Text(''),
      Text('02 / FRAMEWORK', style: theme.accent.merge(Style.bold)),
      Text(''),
      for (var i = 0; i < _pageCount; i++) _indexRow(theme, i),
      Text(''),
      Text('[ ] PREVIOUS, NEXT', style: theme.dim, softWrap: false),
    ],
  );

  /// The folded index: this page's name, and the key that lists them all.
  Widget _bar(ThemeData theme) => _tap(
    _openIndex,
    Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              '',
              children: [
                TextSpan('02 / ', style: theme.accent.merge(Style.bold)),
                TextSpan(
                  widget.pages.names[widget.page],
                  style: theme.text.merge(Style.bold),
                ),
              ],
            ),
            softWrap: false,
          ),
        ),
        Text.rich(
          TextSpan(
            'PAGES ▾ ',
            style: theme.text,
            children: [TextSpan('p', style: theme.accent.merge(Style.bold))],
          ),
          softWrap: false,
        ),
      ],
    ),
  );

  /// The folded index opened: every page, the marked one opened by Enter.
  Widget _indexList(ThemeData theme, int margin) {
    void close() => _closeIndex();
    void move(int step) => setState(
      () => _indexSelected = (_indexSelected + step).clamp(0, _pageCount - 1),
    );
    // The list holds the keys while open: what it leaves reaches nothing of
    // the article under it, save the shell's quits.
    return Focus(
      canRequestFocus: false,
      onKey: (event) => !_quitKeys.contains(event.combo),
      child: Actions(
        bindings: [
          Binding('up', 'move', () => move(-1), id: 'article:index-move'),
          Binding('down', 'move', () => move(1), id: 'article:index-move'),
          Binding('enter', 'open', () {
            close();
            _go(_indexSelected);
          }),
          Binding('esc', 'close', close, id: 'article:index-close'),
          Binding('p', 'close', close, id: 'article:index-close'),
        ],
        child: Focus(
          autofocus: true,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            absorbPointerSignal: true,
            onPointerSignal: (_) {},
            child: Box(
              background: Style(bg: SiteColors.ink),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: margin - 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(''),
                    for (var i = 0; i < _pageCount; i++)
                      i == _indexSelected
                          ? _indexRow(theme, i, marked: true)
                          : Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: _indexRow(theme, i),
                            ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The margin: the numbered heads, the current one in cream.
  Widget _rail(ThemeData theme) {
    final current = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(''),
        Text(''),
        Text('ON THIS PAGE', style: theme.dim.merge(Style.bold)),
        Text(''),
        for (final (i, section) in widget.sections.indexed)
          _tap(
            () {
              final head = _heads[i];
              if (head != null) Scrollable.ensureVisible(head, alignment: 0);
            },
            Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan(
                    '${(i + 1).toString().padLeft(2, '0')} ',
                    style: theme.accent.merge(Style.bold),
                  ),
                  TextSpan(
                    section.head.toUpperCase(),
                    style: i == current
                        ? theme.text.merge(Style.bold)
                        : theme.dim,
                  ),
                ],
              ),
              softWrap: false,
            ),
          ),
        Text(''),
        Text('{ } SECTIONS', style: theme.dim, softWrap: false),
      ],
    );
  }
}
