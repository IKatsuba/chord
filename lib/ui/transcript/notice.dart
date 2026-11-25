/// How an agent's notice reads on screen, from the original's
/// `ui/transcript/notice.ts` and Transcript.tsx's `Notice`: its title by a
/// `⏺` in the severity's role, dim for info, and its description under it at
/// the text's column, all of it dim, wrapped and never cut.
library;

import 'package:chord_tui/chord_tui.dart';

import '../../session/transcript/types.dart';
import 'gap.dart';
import 'tools/tool.dart' show Gutter;

/// The description with each run of blank lines folded to one break.
String noticeDescription(String description) =>
    description.replaceAll(RegExp(r'\n(?:[ \t]*\n)+'), '\n').trim();

/// The style of the notice's `⏺`: dim for info, the severity's own role for
/// the others.
Style noticeMarker(NoticeSeverity severity, ThemeData theme) =>
    switch (severity) {
      NoticeSeverity.info => theme.dim,
      NoticeSeverity.warning => theme.warning,
      NoticeSeverity.error => theme.error,
    };

/// An agent's notice as a transcript block.
class Notice extends StatelessWidget {
  const Notice(this.entry, {super.key});

  final NoticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = entry.description;
    return blockGap(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gutter('⏺', style: noticeMarker(entry.severity, theme)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.ansi(entry.title, style: theme.dim),
                if (description != null)
                  Text.ansi(noticeDescription(description), style: theme.dim),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
