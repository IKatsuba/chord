import 'package:chord/ui/app/crash_screen.dart';
import 'package:chord/ui/app/renderer.dart';
import 'package:chord_tui/chord_tui.dart';

void main() {
  final failure = WindowCrash();
  runApp(
    CrashBoundary(
      onCrash: failure.caught,
      child: Builder(
        builder: (_) {
          Error.throwWithStackTrace(
            StateError('window failed'),
            StackTrace.fromString('#0 Throws (fixture.dart:1:1)'),
          );
        },
      ),
    ),
    beforeExit: () async => failure.rethrowIfCaught(),
  );
}
