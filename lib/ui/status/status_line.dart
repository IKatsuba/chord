import 'package:chord_tui/chord_tui.dart';

import '../theme/theme.dart';
import 'status.dart';

/// One status row: mode or notice left, agent-reported facts right.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.facts});
  final StatusFacts facts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final view = statusLine(facts, constraints.maxWidth);
      final rightWidth = partsWidth(view.right).clamp(0, constraints.maxWidth);
      return SizedBox(
        height: 1,
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                _parts(context, view.left, ' '),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.middle,
              ),
            ),
            if (view.left.isNotEmpty && view.right.isNotEmpty)
              const SizedBox(width: 2),
            if (view.right.isNotEmpty)
              SizedBox(
                width: rightWidth,
                child: Text.rich(
                  _parts(context, view.right, statusSeparator),
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.middle,
                ),
              ),
          ],
        ),
      );
    },
  );

  TextSpan _parts(
    BuildContext context,
    List<StatusPart> parts,
    String separator,
  ) {
    final theme = Theme.of(context);
    final palette = chordThemeOf(context);
    return TextSpan(
      '',
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0) TextSpan(separator, style: theme.dim),
          TextSpan(
            part.text,
            style: switch (part.tone) {
              StatusTone.plain => theme.dim,
              StatusTone.plan => palette.plan,
              StatusTone.edits => palette.edits,
              StatusTone.auto => palette.auto,
              StatusTone.bash => palette.bash,
              StatusTone.bypass => theme.error,
              StatusTone.low ||
              StatusTone.waits ||
              StatusTone.failed => theme.warning,
              StatusTone.ended => theme.error,
            },
          ),
        ],
      ],
    );
  }
}

/// The pending leader, preserving whole follow-up items before clipping held keys.
class LeaderLine extends StatelessWidget {
  const LeaderLine({super.key, required this.held, required this.bindings});
  final List<KeyCombo> held;
  final List<Binding> bindings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final view = leaderLine(held, bindings, constraints.maxWidth);
      final dim = Theme.of(context).dim;
      return SizedBox(
        height: 1,
        child: Text.rich(
          TextSpan(
            '',
            children: [
              TextSpan(view.held),
              const TextSpan(leaderGap),
              for (final (index, item) in view.items.indexed) ...[
                if (index > 0) TextSpan(statusSeparator, style: dim),
                TextSpan(item.keys),
                if (item.words.isNotEmpty)
                  TextSpan(' ${item.words}', style: dim),
              ],
            ],
          ),
          softWrap: false,
          maxLines: 1,
        ),
      );
    },
  );
}
