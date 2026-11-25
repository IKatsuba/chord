import '../rendering/fold.dart';
import 'focus.dart';
import 'framework.dart';
import 'theme.dart';

/// A one-line `▸ title` header over a body shown only when [open]: the
/// app's own Actions flip [open], as Fold has no state or key of its own.
///
/// An open body gets the rows left under the header; where it needs more
/// it is cut and the last row says `… N more lines`. A closed body stays
/// mounted, keeping its state, but is not laid out or painted, and nothing
/// in it holds or takes focus.
class Fold extends StatelessWidget {
  /// A fold titled [title] over [child].
  const Fold({
    super.key,
    required this.title,
    required this.open,
    required this.child,
  });

  /// What the header says.
  final String title;

  /// Whether the body shows.
  final bool open;

  /// The body.
  final Widget child;

  @override
  Widget build(BuildContext context) => _FoldBox(
    title: title,
    open: open,
    child: ExcludeFocus(excluding: !open, child: child),
  );
}

class _FoldBox extends SingleChildRenderObjectWidget {
  const _FoldBox({
    required this.title,
    required this.open,
    required Widget super.child,
  });

  final String title;
  final bool open;

  @override
  RenderFold createRenderObject(BuildContext context) {
    final theme = Theme.of(context);
    return RenderFold(
      title: title,
      open: open,
      markerStyle: theme.dim,
      titleStyle: theme.text,
      countStyle: theme.dim,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFold r) {
    final theme = Theme.of(context);
    r
      ..title = title
      ..open = open
      ..markerStyle = theme.dim
      ..titleStyle = theme.text
      ..countStyle = theme.dim;
  }
}
