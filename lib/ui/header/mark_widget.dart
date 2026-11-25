import 'package:chord_tui/chord_tui.dart';

import '../theme/theme.dart';
import 'header.dart';
import 'mark.dart' as data;
import 'mark_rows.dart';

/// The original logo, painting each terminal cell's upper and lower halves.
class Mark extends StatelessWidget {
  const Mark({super.key, this.grid = data.mark});
  final data.MarkGrid grid;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final row in markRows(grid, markColour(chordThemeOf(context).mark)))
        Text.rich(
          TextSpan(
            '',
            children: [
              for (final segment in row)
                TextSpan(
                  segment.text,
                  style: Style(
                    fg: markColor(segment.color),
                    bg: markColor(segment.backgroundColor),
                  ),
                ),
            ],
          ),
          softWrap: false,
          maxLines: 1,
        ),
    ],
  );
}
