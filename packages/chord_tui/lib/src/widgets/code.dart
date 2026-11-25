import '../foundation/selection_source.dart';
import 'basic.dart';
import 'framework.dart';
import 'selection_content.dart';
import 'theme.dart';

/// Read-only highlighted code with optional numbering and marked soft wraps.
class Code extends StatefulWidget {
  /// Colors [source] as [language], a grammar name or alias.
  const Code(
    this.source, {
    super.key,
    this.language,
    this.lineNumbers = false,
    this.softWrap = true,
    this.growing = false,
  }) : _selectionSource = null;

  Code._bound(
    this._selectionSource, {
    super.key,
    this.language,
    this.growing = false,
  }) : source = selectionSourceText(_selectionSource!),
       lineNumbers = selectionSourceGeometry(_selectionSource).lineNumbers,
       softWrap = selectionSourceGeometry(_selectionSource).softWrap;

  /// Binds exactly the immutable code and geometry used by a selection provider.
  factory Code.fromSelectionSource(
    SelectionSource source, {
    Key? key,
    String? language,
    bool? lineNumbers,
    bool? softWrap,
    bool growing = false,
  }) {
    checkSelectionSourceKind(source, SelectionSourceKind.code);
    final geometry = selectionSourceGeometry(source);
    checkSelectionGeometry(lineNumbers, geometry.lineNumbers, 'lineNumbers');
    checkSelectionGeometry(softWrap, geometry.softWrap, 'softWrap');
    return Code._bound(source, key: key, language: language, growing: growing);
  }

  final SelectionSource? _selectionSource;

  /// Code characters, with source newlines and tabs retained.
  final String source;

  /// The syntax grammar; null or unknown draws plain code.
  final String? language;

  /// Whether the first visual row of each source line carries its number.
  final bool lineNumbers;

  /// Whether long source lines wrap under a continuation mark.
  final bool softWrap;

  /// Whether highlighting may resume through a still-growing source.
  final bool growing;

  @override
  State<Code> createState() => _CodeState();
}

class _CodeState extends State<Code> {
  final _id = Object();
  var _revision = 0;
  (String, bool, bool)? _inputs;
  SelectionSource? _source;
  @override
  Widget build(BuildContext context) {
    var source = widget._selectionSource;
    if (source == null) {
      final inputs = (widget.source, widget.lineNumbers, widget.softWrap);
      if (_inputs != inputs) {
        _source = SelectionSource.code(
          id: _id,
          revision: _revision++,
          text: widget.source,
          lineNumbers: widget.lineNumbers,
          softWrap: widget.softWrap,
          previous: _source,
        );
        _inputs = inputs;
      }
      source = _source!;
    }
    final theme = Theme.of(context);
    return SelectionContent(
      source: source,
      theme: theme,
      base: DefaultTextStyle.of(context).merge(theme.text),
      language: widget.language,
      growing: widget.growing,
    );
  }
}
