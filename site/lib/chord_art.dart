import 'package:chord/ui/app/start_layout.dart' show wordmarkColours;
import 'package:chord/ui/header/header.dart' show markColour;
import 'package:chord/ui/header/mark.dart' as data;
import 'package:chord/ui/header/mark_widget.dart';
import 'package:chord/ui/header/wordmark.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';

/// How much of chord's art fits [width] columns of content: the splash mark
/// and the full wordmark from 57, the full wordmark alone from 45, and the
/// small mark with the compact wordmark below that.
enum ArtForm {
  /// The splash mark beside the full wordmark: 57 columns, 8 rows.
  full,

  /// The full wordmark alone: 45 columns, 6 rows.
  wordmark,

  /// The small mark beside the compact wordmark.
  compact,
}

/// The form of the art for [width] columns.
ArtForm artFormFor(int width) => width >= 57
    ? ArtForm.full
    : width >= 45
    ? ArtForm.wordmark
    : ArtForm.compact;

/// chord's own start-page art, in chord's dark colours whatever the site's
/// theme: the mark's gradient, and the wordmark's solid and shadow strokes
/// in its middle and last stops.
class ChordArt extends StatelessWidget {
  /// The art in [form].
  const ChordArt(this.form, {super.key});

  /// Which pieces it draws.
  final ArtForm form;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(extensions: [chordDark]),
      child: Builder(
        builder: (context) {
          final colours = wordmarkColours(
            markColour(chordThemeOf(context).mark),
          );
          final full = form != ArtForm.compact;
          final wordmark = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in full ? fullWordmark : compactWordmark)
                Text.rich(
                  TextSpan(
                    '',
                    children: [
                      for (final segment in row)
                        TextSpan(
                          segment.text,
                          style: Style(
                            fg: markColor(
                              segment.role == 0 ? colours?.$1 : colours?.$2,
                            ),
                          ),
                        ),
                    ],
                  ),
                  softWrap: false,
                  maxLines: 1,
                ),
            ],
          );
          if (form == ArtForm.wordmark) return wordmark;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Mark(grid: full ? data.splashMark : data.mark),
              SizedBox(width: full ? 3 : 2),
              // Centred on the mark, as chord's start page sets it.
              Padding(padding: const EdgeInsets.only(top: 1), child: wordmark),
            ],
          );
        },
      ),
    );
  }
}
