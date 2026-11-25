import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import '../app/context.dart' show hintKeyOf;
import 'package:clock/clock.dart';

import '../../session/transcript/types.dart' as model;
import '../theme/theme.dart';
import 'status.dart';

/// The running turn's spinner, wait label and elapsed time.
class Working extends StatefulWidget {
  const Working({
    super.key,
    required this.turn,
    this.plan = false,
    this.compacting = false,
    this.input,
  });

  /// A form or link waits on the person, which the line says.
  final model.ElicitationWait? input;
  final model.TurnState turn;

  /// The agent compacts the conversation within the turn.
  final bool compacting;

  /// A plan is put to the person, which the line says.
  final bool plan;

  @override
  State<Working> createState() => _WorkingState();
}

class _WorkingState extends State<Working> {
  Timer? _timer;
  late int _now;

  void _sync() {
    if (widget.turn is model.Idle && widget.input == null) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null) {
      _now = clock.now().millisecondsSinceEpoch;
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        setState(() => _now = clock.now().millisecondsSinceEpoch);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _now = clock.now().millisecondsSinceEpoch;
    _sync();
  }

  @override
  void didUpdateWidget(Working oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = workingLine(
      widget.turn,
      _now,
      plan: widget.plan,
      compacting: widget.compacting,
      input: widget.input == null ? null : (at: widget.input!.at),
      cancelKey: hintKeyOf(context, 'chat:cancel'),
    );
    if (line == null) return const SizedBox();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 1, right: 1, top: 1),
      child: Row(
        spacing: 1,
        children: [
          const _Spinner(),
          Text(line.label, style: theme.accent),
          Text('(${line.detail})', style: theme.dim),
        ],
      ),
    );
  }
}

class _Spinner extends StatefulWidget {
  const _Spinner();
  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> {
  late final Timer _timer;
  int _step = 0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      setState(() => _step = (_step + 1) % spinnerSteps);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      '',
      children: [
        for (final mark in spinnerMarks(_step, chordThemeOf(context).mark))
          TextSpan(
            '›',
            style: Style(fg: markColor(mark.colour), dim: mark.dim),
          ),
      ],
    ),
  );
}
