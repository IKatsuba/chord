import 'dart:async';

import '../terminal/style.dart';
import 'basic.dart';
import 'framework.dart';

/// A small animation that says work is going on.
class Spinner extends StatefulWidget {
  /// A spinner cycling [frames] every [interval] while [visible].
  const Spinner({
    super.key,
    this.visible = true,
    this.frames = const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
    this.interval = const Duration(milliseconds: 80),
    this.style,
  });

  /// Whether it shows and turns; hidden, it draws a blank cell.
  final bool visible;

  /// The glyphs shown in turn.
  final List<String> frames;

  /// How long each frame shows.
  final Duration interval;

  /// The glyphs' style over the default text style.
  final Style? style;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> {
  Timer? _timer;
  int _frame = 0;

  void _sync() {
    if (widget.visible && _timer == null) {
      _timer = Timer.periodic(widget.interval, (_) => setState(() => _frame++));
    } else if (!widget.visible) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Spinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _timer?.cancel();
      _timer = null;
    }
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    widget.visible ? widget.frames[_frame % widget.frames.length] : ' ',
    style: widget.style,
  );
}
