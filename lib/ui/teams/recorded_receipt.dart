/// A selected run's receipt as main's record kept it, drawn as chord's own
/// report rather than as an agent's call: what it is, the job, the
/// receipt's lines with the saved definition, and the failure it ended in.
/// From the original's `ui/teams/RecordedReceipt.tsx`.
library;

import 'package:chord_tui/chord_tui.dart' hide Folded;

import '../../session/team_selection.dart';
import '../../session/transcript/types.dart';
import '../transcript/tools/proposal.dart' show wrapLineText;
import '../transcript/tools/selection_lines.dart';
import '../transcript/tools/tool.dart' show Under;

/// One line of a recorded receipt: dim for what frames it, failed for the
/// failure it recorded.
typedef ReceiptLine = ({String text, bool dim, bool failed});

/// The title over [call]'s receipt: `Recorded Team receipt (bugfix)`;
/// null when the call holds no receipt.
String? recordedReceiptTitle(ChordCall call) {
  final receipt = recordedSelection(call);
  return receipt == null
      ? null
      : 'Recorded Team receipt (${(receipt['saved'] as Map)['name']})';
}

/// The lines under [call]'s title, wrapped to [width] less the `⎿` and
/// its gutter; [historical] when it is a resumed session's.
List<ReceiptLine> recordedReceiptLines(
  ChordCall call,
  int width, {
  bool historical = false,
}) {
  final receipt = recordedSelection(call);
  if (receipt == null) return const [];
  final job = call.input['job'];
  final lines = [
    'Recorded by Chord · current state unknown'
        '${historical ? ' · historical observation' : ''}',
    'Recorded: time unknown',
    if (job is String) ...job.split('\n'),
    ...selectionLines(receipt, expanded: true, recorded: true),
    if (call.error case final error?) 'Recorded failure: $error',
  ];
  return [
    for (final (index, line) in lines.indexed)
      for (final text in wrapLineText(line, width - 5 < 1 ? 1 : width - 5))
        (
          text: text,
          dim:
              index < 2 ||
              line.startsWith('Read ') ||
              line.startsWith('Read:') ||
              line.startsWith('Billing:') ||
              line.startsWith('Run:'),
          failed: call.error != null && line.startsWith('Recorded failure:'),
        ),
  ];
}

/// The receipts main's transcript holds whose run has no `Team(…)` row of
/// its own there, as a receipt served after a /clear or a resume has none:
/// the latest of each run, in the order the runs first came.
List<ChordCall> recordedReceipts(Transcript transcript) {
  final linked = {
    for (final entry in transcript.entries)
      if (entry case ToolEntry(:final call))
        if (call.chord case final chord?)
          if (recordedSelection(chord) case final receipt?) receipt['runId'],
  };
  final latest = <Object?, ChordCall>{};
  for (final call in transcript.served) {
    final receipt = recordedSelection(call);
    if (receipt != null && !linked.contains(receipt['runId'])) {
      latest[receipt['runId']] = call;
    }
  }
  return [...latest.values];
}

/// A recorded receipt as chord's own report: a blank row, its title, and
/// its lines under `⎿`, with no tool marker or claim of live work.
class RecordedReceipt extends StatelessWidget {
  /// [call]'s receipt; [historical] when it is a resumed session's.
  const RecordedReceipt(this.call, {super.key, this.historical = false});

  final ChordCall call;
  final bool historical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = recordedReceiptTitle(call);
        if (title == null) return const SizedBox();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 1),
            Text(title),
            // The original's width is the window's less four, where the
            // port's entry is given two less.
            for (final (index, line) in recordedReceiptLines(
              call,
              constraints.maxWidth.toInt() - 2,
              historical: historical,
            ).indexed)
              Under(
                first: index == 0,
                child: Text(
                  line.text,
                  style: line.failed
                      ? theme.error
                      : line.dim
                      ? theme.dim
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}
