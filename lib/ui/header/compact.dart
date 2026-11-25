import 'package:chord_tui/chord_tui.dart';

import '../pickers/mcp.dart';
import 'mark_widget.dart';
import 'resumed.dart';
import '../transcript/selection.dart' show selectionChild;

/// The original four-row startup header, as the transcript's first item.
class CompactHeader extends StatelessWidget {
  const CompactHeader({
    super.key,
    required this.version,
    required this.agent,
    required this.directory,
    this.model,
    this.resumed,
    this.selectionSource,
    this.helpKey = '?',
  });
  final String version;
  final String agent;
  final String directory;
  final String? model;
  final ResumedHeader? resumed;
  final SelectionSource? selectionSource;

  /// The key that opens the shortcuts panel; none when nothing does.
  final String? helpKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final width = (constraints.maxWidth - 7).clamp(0, unbounded);
      Widget row(String role, String text) => selectionSource != null
          ? Text.fromSelectionSource(
              selectionChild(selectionSource!, role),
              style: theme.dim,
            )
          : Text(
              text,
              style: theme.dim,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.middle,
            );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SelectionContainer.disabled(
            child: SizedBox(width: 4, child: Mark()),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectionSource != null)
                  Text.fromSelectionSource(
                    selectionChild(selectionSource!, 'version'),
                  )
                else
                  Text.rich(
                    TextSpan(
                      '',
                      children: [
                        const TextSpan('chord', style: Style.bold),
                        TextSpan(' v$version', style: theme.dim),
                      ],
                    ),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.middle,
                  ),
                row('agent', '$agent${model == null ? '' : ' · $model'}'),
                row('directory', cutPath(directory, width)),
                // /help is a command, which no keybindings file takes away.
                row('help', helpRow(helpKey)),
                if (resumed case final facts?)
                  selectionSource != null
                      ? Text.fromSelectionSource(
                          selectionChild(selectionSource!, 'resumed'),
                          style: theme.dim,
                        )
                      : Text(
                          resumedRows(facts, width),
                          style: theme.dim,
                          softWrap: facts.wrap,
                          maxLines: facts.wrap ? null : 1,
                          overflow: facts.wrap
                              ? TextOverflow.clip
                              : TextOverflow.middle,
                        ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The header's last row: the panel's key, while one opens it, and /help.
String helpRow(String? helpKey) =>
    helpKey == null ? '/help' : '$helpKey for shortcuts · /help';
