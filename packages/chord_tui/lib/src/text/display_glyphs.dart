/// Display type from block cells: a 5x7 bitmap table of glyphs, and the
/// layout that draws a line of them at a size, apart from the widget.
library;

/// How big display type is drawn: how many cells a glyph pixel takes.
enum DisplaySize {
  /// Half blocks, a column a pixel: 4 rows, 6 columns a glyph.
  half(rows: 4, columns: 6),

  /// Half blocks, two columns a pixel: 4 rows, 12 columns a glyph.
  numeral(rows: 4, columns: 12),

  /// Full blocks, two columns by one row a pixel: 7 rows, 12 columns.
  large(rows: 7, columns: 12),

  /// Full blocks, four columns by two rows a pixel: 14 rows, 24 columns.
  huge(rows: 14, columns: 24);

  const DisplaySize({required this.rows, required this.columns});

  /// The rows a line of glyphs takes.
  final int rows;

  /// The columns one glyph advances by, its gap included.
  final int columns;

  /// Columns a pixel takes.
  int get pixelColumns => columns ~/ 6;

  /// Whether two pixel rows share a cell, as half blocks.
  bool get halfBlocks => this == half || this == numeral;
}

/// The pixels of each glyph, 5 wide and 7 tall, `#` on.
const Map<String, List<String>> displayGlyphs = {
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
  'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  'N': ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
  'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.'],
  'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
  ',': ['.....', '.....', '.....', '.....', '.##..', '..#..', '.#...'],
  ':': ['.....', '.##..', '.##..', '.....', '.##..', '.##..', '.....'],
  '!': ['..#..', '..#..', '..#..', '..#..', '..#..', '.....', '..#..'],
  '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  '_': ['.....', '.....', '.....', '.....', '.....', '.....', '#####'],
  '/': ['.....', '....#', '...#.', '..#..', '.#...', '#....', '.....'],
  "'": ['..#..', '..#..', '.#...', '.....', '.....', '.....', '.....'],
  '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
  '&': ['.##..', '#..#.', '#.#..', '.#...', '#.#.#', '#..#.', '.##.#'],
  '#': ['.#.#.', '.#.#.', '#####', '.#.#.', '#####', '.#.#.', '.#.#.'],
};

/// What a character without a glyph draws: a hollow box.
const List<String> missingGlyph = [
  '#####',
  '#...#',
  '#...#',
  '#...#',
  '#...#',
  '#...#',
  '#####',
];

/// The pixels [char] draws: its glyph, lower case as capitals, or the
/// hollow box.
List<String> glyphFor(String char) =>
    displayGlyphs[char.toUpperCase()] ?? missingGlyph;

/// The cells [text] takes at [size]: a glyph's advance each, less the gap
/// after the last; 0 wide when [text] is empty.
({int width, int height}) displayMeasure(String text, DisplaySize size) {
  final glyphs = text.runes.length;
  return (
    width: glyphs == 0 ? 0 : glyphs * size.columns - size.pixelColumns,
    height: size.rows,
  );
}

/// One row of drawn display type as runs: each run's characters, and the
/// index of the source character whose glyph it draws, for its style;
/// -1 for the gap between glyphs.
typedef DisplayRun = ({String text, int source});

/// [text] drawn at [size]: [DisplaySize.rows] rows, each as runs of block
/// characters, and the gap between glyphs as spaces.
List<List<DisplayRun>> displayRows(String text, DisplaySize size) {
  final chars = [for (final r in text.runes) String.fromCharCode(r)];
  final px = size.pixelColumns;
  final rows = <List<DisplayRun>>[];
  for (var row = 0; row < size.rows; row++) {
    final runs = <DisplayRun>[];
    for (var i = 0; i < chars.length; i++) {
      final glyph = glyphFor(chars[i]);
      final cells = StringBuffer();
      for (var x = 0; x < 5; x++) {
        final String cell;
        if (size.halfBlocks) {
          // Two pixel rows a cell: the top, then the bottom.
          final top = _on(glyph, 2 * row, x);
          final bottom = _on(glyph, 2 * row + 1, x);
          cell = top && bottom
              ? '█'
              : top
              ? '▀'
              : bottom
              ? '▄'
              : ' ';
        } else {
          // A pixel row is one row, or two at huge.
          final y = size == DisplaySize.huge ? row ~/ 2 : row;
          cell = _on(glyph, y, x) ? '█' : ' ';
        }
        cells.write(cell * px);
      }
      runs.add((text: cells.toString(), source: i));
      if (i < chars.length - 1) runs.add((text: ' ' * px, source: -1));
    }
    rows.add(runs);
  }
  return rows;
}

bool _on(List<String> glyph, int y, int x) =>
    y < glyph.length && glyph[y][x] == '#';
