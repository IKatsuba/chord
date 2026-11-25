import '../foundation/selection_source.dart';
import '../text/diff.dart';
import '../text/selection_layout.dart' show measureDiffView;

import 'basic.dart';
import 'framework.dart';
import 'theme.dart';
import 'selection_content.dart';

/// A line diff drawn as chord draws an edit: one gutter of line numbers,
/// `+` and `-` signs, changed rows tinted, code highlighted by the file's
/// language, and long lines wrapped under their code.
class Diff extends StatefulWidget {
  /// The diff from [oldText] to [newText], with [context] unchanged lines
  /// around each change; [title], a path, names the language too.
  const Diff(
    this.oldText,
    this.newText, {
    super.key,
    this.title,
    this.context = 3,
    this.wrap = DiffWrap.keepSpaces,
    this.codeInsetRight = 0,
  }) : assert(codeInsetRight >= 0),
       _patch = null,
       _view = null,
       showTitle = true,
       _selectionSource = null;

  const Diff._unified(
    this._patch, {
    super.key,
    this.title,
    this.wrap = DiffWrap.keepSpaces,
    this.codeInsetRight = 0,
  }) : assert(codeInsetRight >= 0),
       oldText = '',
       newText = '',
       context = 0,
       _view = null,
       showTitle = true,
       _selectionSource = null;

  /// Draws selected source rows, highlighting from their complete model.
  const Diff.fromView(
    DiffView view, {
    super.key,
    this.title,
    this.showTitle = true,
    this.wrap = DiffWrap.keepSpaces,
    this.codeInsetRight = 0,
  }) : assert(codeInsetRight >= 0),
       _view = view,
       _patch = null,
       oldText = '',
       newText = '',
       context = 0,
       _selectionSource = null;

  Diff._bound(this._selectionSource, {super.key})
    : _view = selectionSourceDiff(_selectionSource!),
      _patch = null,
      oldText = '',
      newText = '',
      context = 0,
      title = selectionSourceGeometry(_selectionSource).title,
      showTitle = selectionSourceGeometry(_selectionSource).showTitle,
      wrap = selectionSourceGeometry(_selectionSource).diffWrap,
      codeInsetRight = selectionSourceGeometry(
        _selectionSource,
      ).diffCodeInsetRight;

  /// Draws the immutable selected rows and geometry used by a source provider.
  factory Diff.fromSelectionSource(
    SelectionSource source, {
    Key? key,
    String? title,
    bool? showTitle,
    DiffWrap? wrap,
    int? codeInsetRight,
  }) {
    checkSelectionSourceKind(source, SelectionSourceKind.diff);
    final geometry = selectionSourceGeometry(source);
    checkSelectionGeometry(title, geometry.title, 'title');
    checkSelectionGeometry(showTitle, geometry.showTitle, 'showTitle');
    checkSelectionGeometry(wrap, geometry.diffWrap, 'wrap');
    checkSelectionGeometry(
      codeInsetRight,
      geometry.diffCodeInsetRight,
      'codeInsetRight',
    );
    return Diff._bound(source, key: key);
  }

  final SelectionSource? _selectionSource;

  /// Whether the selected view's path is drawn above its rows.
  final bool showTitle;

  final DiffView? _view;

  /// One file's unified diff, its hunks as given; [title] wins over the
  /// path its headers name.
  ///
  /// Throws a [FormatException] for a malformed patch or one of several
  /// files.
  factory Diff.fromUnified(
    String patch, {
    Key? key,
    String? title,
    DiffWrap wrap = DiffWrap.keepSpaces,
    int codeInsetRight = 0,
  }) => Diff._unified(
    parseUnifiedDiffRemembered(patch),
    key: key,
    title: title,
    wrap: wrap,
    codeInsetRight: codeInsetRight,
  );

  /// The rows `Diff.fromView(view, showTitle: false, wrap: wrap,
  /// codeInsetRight: codeInsetRight)` draws at [width], a gap one row each:
  /// the same wrap the drawing runs.
  static int measure(
    DiffView view,
    int width, {
    DiffWrap wrap = DiffWrap.keepSpaces,
    int codeInsetRight = 0,
  }) {
    assert(codeInsetRight >= 0);
    return measureDiffView(view, width, wrap, codeInsetRight);
  }

  /// How a code row longer than its room wraps.
  final DiffWrap wrap;

  /// Cells the code's wrap room keeps free at the right; the row and its
  /// tint still fill the width.
  final int codeInsetRight;

  /// The text before.
  final String oldText;

  /// The text after.
  final String newText;

  /// The file's path, drawn dim above the rows and naming its language.
  final String? title;

  /// Unchanged lines kept around each change.
  final int context;

  final DiffModel? _patch;

  @override
  State<Diff> createState() => _DiffState();
}

class _DiffState extends State<Diff> {
  final _id = Object();
  var _revision = 0;
  (String, String, int)? _inputs;
  DiffModel? _model, _fullModel;
  DiffView? _fullView;
  (DiffView, String?, bool, DiffWrap, int)? _sourceInputs;
  SelectionSource? _source;

  DiffModel get _diff {
    if (widget._view != null) return widget._view!.model;
    if (widget._patch != null) return widget._patch!;
    final inputs = (widget.oldText, widget.newText, widget.context);
    if (_inputs != inputs) {
      _inputs = inputs;
      _model = diffTexts(
        widget.oldText,
        widget.newText,
        context: widget.context,
      );
    }
    return _model!;
  }

  @override
  Widget build(BuildContext context) {
    var source = widget._selectionSource;
    if (source == null) {
      final model = _diff;
      if (!identical(model, _fullModel)) {
        _fullModel = model;
        _fullView = model.view();
      }
      final view = widget._view ?? _fullView!;
      final inputs = (
        view,
        widget.title ?? model.path,
        widget.showTitle,
        widget.wrap,
        widget.codeInsetRight,
      );
      if (_sourceInputs != inputs) {
        _source = SelectionSource.diff(
          id: _id,
          revision: _revision++,
          view: view,
          title: widget.title,
          showTitle: widget.showTitle,
          wrap: widget.wrap,
          codeInsetRight: widget.codeInsetRight,
          previous: _source,
        );
        _sourceInputs = inputs;
      }
      source = _source!;
    }
    final theme = Theme.of(context);
    return SelectionContent(
      source: source,
      theme: theme,
      base: DefaultTextStyle.of(context).merge(theme.text),
    );
  }
}
