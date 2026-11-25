import 'package:chord_tui/chord_tui.dart';

import '../../session/start_failure.dart';
import '../transcript/tools/tool.dart' show Under;

/// Under a start failure, what chord knows of why: the pin it ran, the end
/// of the agent's stderr with what was cut before it, and the way on chord
/// knows for [agent], each only when it has something to say.
class StartFailureBlock extends StatelessWidget {
  /// The block for [agent]'s [failure].
  const StartFailureBlock({
    super.key,
    required this.agent,
    required this.failure,
  });

  final String agent;
  final StartFailure failure;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).dim;
    final way = wayOnFor(agent, failure);
    final stderr = failure.stderr;
    // Each row: chord's words, or a line of the tail two in under them.
    final rows = <(String, {bool tail, bool dim})>[
      if (failure.pinned case final pinned?)
        (pinLine(pinned), tail: false, dim: false),
      if (stderr != null) ...[
        (stderrHeading, tail: false, dim: false),
        if (stderr.cut > 0) (cutLine(stderr.cut), tail: true, dim: true),
        for (final line in stderr.lines) (line, tail: true, dim: false),
      ],
      if (way != null) (way, tail: false, dim: false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, row) in rows.indexed)
          Under(
            first: i == 0,
            // A tail's line wraps under its column, not its own indent.
            child: Padding(
              padding: EdgeInsets.only(left: row.tail ? 2 : 0),
              child: Text.ansi(row.$1, style: row.dim ? dim : null),
            ),
          ),
      ],
    );
  }
}
