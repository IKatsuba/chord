import '../terminal/terminal.dart';
import 'framework.dart';

/// The app's [Terminal], for the services no widget draws: opening a link,
/// copying, a notification. [of] finds the nearest scope, or else the
/// terminal runApp, the tester or an [AppHost] was given; a scope is only
/// needed to give a subtree another.
class TerminalScope extends InheritedWidget {
  /// [terminal] for everything under [child].
  const TerminalScope({
    super.key,
    required this.terminal,
    required super.child,
  });

  /// The terminal the app runs in.
  final Terminal terminal;

  /// The terminal [maybeOf] finds; throws when there is none.
  static Terminal of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'No TerminalScope above this widget, and its host was given no '
        'terminal.',
      ));

  /// The nearest scope's terminal, else the host's; null with neither.
  static Terminal? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TerminalScope>()?.terminal ??
      context.owner.terminal;

  @override
  bool updateShouldNotify(TerminalScope oldWidget) =>
      !identical(terminal, oldWidget.terminal);
}
