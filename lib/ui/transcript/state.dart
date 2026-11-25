/// The window's transcript details setting; scrolling belongs to the framework.
final class ViewWindow {
  /// A folded window unless [expanded] is requested.
  const ViewWindow({this.expanded = false});

  /// Whether thoughts and tool output are shown in full.
  final bool expanded;
}

/// The ctrl+o transition, independent of turn and prompt draft state.
ViewWindow toggled(ViewWindow state) => ViewWindow(expanded: !state.expanded);
