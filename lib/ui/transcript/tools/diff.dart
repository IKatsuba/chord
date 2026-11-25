import 'package:chord_tui/chord_tui.dart';

/// Unchanged lines retained around each tool edit.
const diffContext = 3;

/// Default source-row cap of the original's diff helper, for later proposals.
const diffRows = 10;

/// A tool edit's file name and reusable framework view.
final class ToolDiffView {
  /// A file's selected diff rows.
  const ToolDiffView(this.path, this.view);

  /// The file's original path; shortening belongs to the window.
  final String path;

  /// Selected rows, full counts and complete sources for highlighting.
  final DiffView view;
}

/// Reads a tool edit through the framework's existing diff package.
ToolDiffView diffView(
  String path,
  String? oldText,
  String newText, {
  bool expanded = true,
}) => ToolDiffView(
  path,
  diffTexts(
    oldText ?? '',
    newText,
    context: diffContext,
  ).view(maxRows: expanded ? null : diffRows),
);

/// The original's edit headline, using the displayed path when supplied.
String diffHeadline(ToolDiffView diff, {String? path}) =>
    'Updated ${path ?? diff.path} with ${plural(diff.view.added, 'addition')} and ${plural(diff.view.removed, 'removal')}';

/// A count followed by its singular or plural noun.
String plural(int count, String word) => '$count $word${count == 1 ? '' : 's'}';
