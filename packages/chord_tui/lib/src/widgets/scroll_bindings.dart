import 'focus_manager.dart';
import 'scroll_controller.dart';

/// Which keys press which scroll step; an empty list leaves a step unbound.
class ScrollKeys {
  /// The keys; the defaults bind pages and the ends, and no line keys,
  /// since plain up and down belong to a prompt's history and a picker.
  const ScrollKeys({
    this.pageUp = const ['pageup'],
    this.pageDown = const ['pagedown'],
    this.lineUp = const [],
    this.lineDown = const [],
    this.top = const ['home'],
    this.bottom = const ['end'],
  });

  /// Keys that scroll up a page.
  final List<String> pageUp;

  /// Keys that scroll down a page.
  final List<String> pageDown;

  /// Keys that scroll up a line.
  final List<String> lineUp;

  /// Keys that scroll down a line.
  final List<String> lineDown;

  /// Keys that scroll to the top.
  final List<String> top;

  /// Keys that scroll to the bottom.
  final List<String> bottom;
}

/// The standard bindings for [controller]'s steps, one per key, with their
/// descriptions, for an [Actions] above the focused widget; their ids,
/// `scroll:pageUp` to `scroll:bottom`, let a [Keymap] move them.
List<Binding> scrollBindings(
  ScrollController controller, {
  ScrollKeys keys = const ScrollKeys(),
}) => [
  for (final k in keys.pageUp)
    Binding(k, 'Scroll up a page', controller.pageUp, id: 'scroll:pageUp'),
  for (final k in keys.pageDown)
    Binding(
      k,
      'Scroll down a page',
      controller.pageDown,
      id: 'scroll:pageDown',
    ),
  for (final k in keys.lineUp)
    Binding(k, 'Scroll up a line', controller.lineUp, id: 'scroll:lineUp'),
  for (final k in keys.lineDown)
    Binding(
      k,
      'Scroll down a line',
      controller.lineDown,
      id: 'scroll:lineDown',
    ),
  for (final k in keys.top)
    Binding(k, 'Scroll to the top', controller.toTop, id: 'scroll:top'),
  for (final k in keys.bottom)
    Binding(
      k,
      'Scroll to the bottom',
      controller.toBottom,
      id: 'scroll:bottom',
    ),
];
