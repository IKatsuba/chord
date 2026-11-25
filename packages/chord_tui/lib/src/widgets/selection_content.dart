import 'package:meta/meta.dart';

import '../foundation/selection_source.dart';
import '../rendering/selection_content.dart';
import '../terminal/style.dart';
import 'framework.dart';
import 'theme_data.dart';

/// The shared leaf binding used by rich content widgets.
@internal
class SelectionContent extends LeafRenderObjectWidget {
  /// Carries immutable source geometry and current syntax presentation.
  const SelectionContent({
    required this.source,
    required this.theme,
    required this.base,
    this.language,
    this.growing,
    this.selectedCodeBlock,
  });

  /// Current immutable content snapshot.
  final SelectionSource source;

  /// The current palette.
  final ThemeData theme;

  /// The inherited starting style.
  final Style base;

  /// Optional code highlighting language.
  final String? language;

  /// Optional highlighting state override.
  final bool? growing;

  /// The code frame emphasized by the enclosing Markdown application.
  final CodeBlockId? selectedCodeBlock;

  @override
  RenderSelectionContent createRenderObject(BuildContext context) =>
      RenderSelectionContent(
        source: source,
        theme: theme,
        base: base,
        language: language,
        growing: growing,
        selectedCodeBlock: selectedCodeBlock,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    RenderSelectionContent renderObject,
  ) {
    renderObject
      ..source = source
      ..theme = theme
      ..base = base
      ..language = language
      ..growing = growing
      ..selectedCodeBlock = selectedCodeBlock;
  }
}
