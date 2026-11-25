/// How `lines` rows fold into `room` rows ([foldOf]): those shown from
/// the top, and those folded under a `… N more lines` row.
typedef Folded = ({int shown, int more});

/// [lines] in [room] rows: all of them where they fit, else as many as
/// leave a row for the line that counts the rest.
Folded foldOf(int lines, int room) {
  if (lines <= room) return (shown: lines, more: 0);
  final shown = room - 1 < 0 ? 0 : room - 1;
  return (shown: shown, more: lines - shown);
}

/// `… 1 more line`, `… 2 more lines`.
String moreLines(int more) => '… $more more ${more == 1 ? 'line' : 'lines'}';
