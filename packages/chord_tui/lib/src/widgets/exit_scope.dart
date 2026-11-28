import 'framework.dart';

/// Takes the exit an app asks for under it: `exitApp` inside calls
/// [onExit] instead of quitting, for an app embedded in another, as a
/// screen shown on a page. The nearest scope always takes it; an app that
/// means to quit calls `exitApp` from above the scope.
class ExitScope extends InheritedWidget {
  /// A scope over [child] whose exits run [onExit].
  const ExitScope({super.key, required this.onExit, required super.child});

  /// What an exit under it does instead.
  final void Function() onExit;

  @override
  bool updateShouldNotify(ExitScope oldWidget) => false;
}
