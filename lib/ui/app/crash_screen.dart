import 'package:chord_tui/chord_tui.dart';

import '../theme/theme.dart';
import 'crash.dart';

/// A themed boundary around the window, with no logging over its fallback.
class CrashBoundary extends StatelessWidget {
  const CrashBoundary({super.key, required this.child, this.onCrash});
  final Widget child;
  final void Function(Object, StackTrace)? onCrash;

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    child: ErrorBoundary(
      onError: onCrash,
      errorBuilder: (context, error, stack) => CrashScreen(
        error: error,
        stackTrace: stack,
        onQuit: () => exitApp(context),
      ),
      child: child,
    ),
  );
}

/// The native crash rows; any non-modifier key quits once, and paste does not.
class CrashScreen extends StatefulWidget {
  const CrashScreen({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.onQuit,
  });
  final Object error;
  final StackTrace? stackTrace;
  final void Function() onQuit;

  @override
  State<CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<CrashScreen> {
  bool _quitting = false;

  bool _key(KeyEvent event) {
    if (const {
      'shift',
      'ctrl',
      'control',
      'alt',
      'meta',
      'super',
      'cmd',
    }.contains(event.key)) {
      return false;
    }
    if (!_quitting) {
      _quitting = true;
      widget.onQuit();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKey: _key,
    onPaste: (_) => true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in crashRows(
              widget.error,
              widget.stackTrace,
              constraints.maxWidth,
              constraints.maxHeight,
            ))
              Text(
                row.text,
                style: switch (row.role) {
                  CrashRole.error => theme.error,
                  CrashRole.dim => theme.dim,
                  CrashRole.blank => theme.text,
                },
                softWrap: false,
                maxLines: 1,
              ),
          ],
        );
      },
    ),
  );
}
