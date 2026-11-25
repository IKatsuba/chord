import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: zero-width replacement boundaries', () {
    const mark = '\u0301';
    const style = Style(fg: Colors.red, bg: Colors.blue);

    for (final size in const [Size(0, 0), Size(0, 1), Size(1, 0), Size(1, 1)]) {
      test('normalization stays within $size', () {
        final buffer = Buffer(size.width, size.height);
        for (final x in [-1, 0, 1]) {
          for (final y in [-1, 0, 1]) {
            buffer.set(x, y, mark, 0, style);
          }
        }
        expect(diffBuffers(null, buffer), isNot(contains(mark)));
        if (size == const Size(1, 1)) {
          expect(buffer.charAt(0, 0), ' ');
          expect(buffer.styleAt(0, 0), style);
        }
      });
    }

    for (final glyph in ['日', '🙂', '👩‍💻']) {
      for (final half in [0, 1]) {
        test(
          'replacing half $half of $glyph clears its cursor and other half',
          () {
            final buffer = Buffer(3, 1);
            buffer.set(0, 0, glyph, 2, Style.plain);
            Canvas(buffer).setCursor(Offset(1 - half, 0));
            buffer.set(half, 0, mark, 0, style);
            expect(buffer.line(0), '   ');
            expect(buffer.styleAt(half, 0), style);
            expect(buffer.cursor, isNull);
            expect(diffBuffers(null, buffer), isNot(contains(mark)));
          },
        );
      }
    }

    test(
      'a thousand changes preserve joined edge graphemes and background',
      () {
        final buffer = Buffer(4, 1);
        Canvas(
          buffer,
        ).fill(const Rect(0, 0, 4, 1), const Style(bg: Colors.blue));
        buffer.set(0, 0, 'e\u0301', 1, Style.plain);
        buffer.set(3, 0, 'a\u0308', 1, Style.plain);
        for (var i = 0; i < 1000; i++) {
          Canvas(buffer).put(
            1,
            0,
            i.isEven ? mark : 'x',
            i.isEven ? 0 : 1,
            const Style(fg: Colors.red),
          );
        }
        Canvas(buffer).put(1, 0, mark, 0, const Style(fg: Colors.red));
        expect(buffer.line(0), 'e\u0301  a\u0308');
        expect(buffer.styleAt(1, 0), style);
      },
    );

    testWidgets('resize keeps joined marks while standalone marks stay blank', (
      t,
    ) async {
      final child = Align(
        alignment: Alignment.topLeft,
        child: Text('\u0301\ne\u0301🙂\n\u0301', style: style),
      );
      for (final size in const [
        Size(120, 40),
        Size(80, 24),
        Size(1, 1),
        Size(0, 0),
        Size(120, 40),
      ]) {
        await t.pumpWidget(child, size: size);
        if (size.width > 0 && size.height > 0) {
          expect(t.screen.charAt(0, 0), ' ');
        }
        if (size.height > 2) {
          expect(t.screen.charAt(0, 1), 'e\u0301');
          expect(t.screen.charAt(0, 2), ' ');
        }
      }
    });
  });

  test('the first frame draws everything', () {
    final b = Buffer(3, 1);
    Canvas(b).drawText(0, 0, 'abc');
    final out = diffBuffers(null, b, synchronized: false);
    expect(out, contains('\x1b[2J'));
    expect(out, contains('abc'));
  });

  test('only changed cells are written', () {
    final a = Buffer(10, 2);
    Canvas(a).drawText(0, 0, 'hello');
    Canvas(a).drawText(0, 1, 'world');
    final b = Buffer(10, 2);
    Canvas(b).drawText(0, 0, 'hello');
    Canvas(b).drawText(0, 1, 'worXd');
    final out = diffBuffers(a, b, synchronized: false);
    expect(out, '\x1b[?25l\x1b[2;4H\x1b[0mX\x1b[0m');
  });

  test('nothing changed, nothing drawn', () {
    final a = Buffer(4, 1);
    final b = Buffer(4, 1);
    expect(diffBuffers(a, b, synchronized: false), '\x1b[?25l');
  });

  test('a wide grapheme takes two cells in the buffer', () {
    final b = Buffer(4, 1);
    Canvas(b).drawText(0, 0, '日a');
    expect(b.charAt(0, 0), '日');
    expect(b.charAt(1, 0), '');
    expect(b.charAt(2, 0), 'a');
    Canvas(b).drawText(1, 0, 'x');
    expect(b.line(0), ' xa ');
  });

  test('text keeps the background under it', () {
    final b = Buffer(3, 1);
    final c = Canvas(b);
    c.fill(const Rect(0, 0, 3, 1), const Style(bg: Colors.blue));
    c.drawText(0, 0, 'a', const Style(fg: Colors.red));
    expect(b.styleAt(0, 0), const Style(fg: Colors.red, bg: Colors.blue));
  });

  // CTUI-96: a lone zero-width mark written as a cell of its own joins the
  // glyph to its left on a real terminal, which never advances; redrawing
  // the cell then left the mark on its neighbour. It takes its cell as the
  // styled space a fresh draw shows.
  group('a lone zero-width mark', () {
    const mark = '\u0301';
    const style = Style(fg: Colors.red);

    test('takes its cell as a space in its style', () {
      final b = Buffer(3, 1);
      Canvas(b).drawText(0, 0, 'ab');
      Canvas(b).put(1, 0, mark, 0, style);
      expect(b.charAt(1, 0), ' ');
      expect(b.styleAt(1, 0), style);
    });

    test('is never written bare, and a redraw leaves no mark behind', () {
      final a = Buffer(3, 1);
      Canvas(a).drawText(0, 0, 'ab');
      Canvas(a).put(1, 0, mark, 0, style);
      final first = diffBuffers(null, a, synchronized: false);
      expect(first, isNot(contains(mark)));
      final b = Buffer(3, 1);
      Canvas(b).drawText(0, 0, 'a');
      Canvas(b).put(1, 0, ' ', 1, style);
      expect(diffBuffers(a, b, synchronized: false), '\x1b[?25l');
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('a mark that starts a line leaves no mark on screen, '
          'at $size', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: Text('ab\n$mark', style: style),
          ),
          size: size,
        );
        expect(t.screen.charAt(0, 1), ' ');
        expect(t.screen.text, isNot(contains(mark)));
      });
    }
  });
}
