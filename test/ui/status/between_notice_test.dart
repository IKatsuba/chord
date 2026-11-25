import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/status/status_line.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test('between notice has original wide and short answer wording', () {
    final notice = betweenNotice('permission', 'ctrl+x a');
    expect(notice.tone, StatusTone.waits);
    expect(
      waitsParts(notice, true).single.text,
      '● permission asked between turns · ctrl+x a to answer',
    );
    expect(
      waitsParts(notice, false).single.text,
      '● permission · ctrl+x a to answer',
    );
    expect(
      waitsParts(betweenNotice('permission', null), true).single.text,
      '● permission asked between turns',
    );
  });
  test('short notice is tried before cutting reported model', () {
    final facts = StatusFacts(
      model: 'Fake Large with a 1M context window',
      effort: 'medium',
      waits: betweenNotice('permission', 'ctrl+x a'),
    );
    final wide = statusLine(facts, 120);
    expect(
      wide.left.single.text,
      '● permission asked between turns · ctrl+x a to answer',
    );
    final short = statusLine(facts, 80);
    expect(short.left.single.text, '● permission · ctrl+x a to answer');
    expect(short.right.first.text, facts.model);
    expect(
      statusLine(
        StatusFacts(notice: 'Pressed', waits: facts.waits),
        120,
      ).left.single.text,
      'Pressed',
    );
    final mode = statusLine(StatusFacts(mode: 'plan', waits: facts.waits), 120);
    expect(mode.left.map((part) => part.text), [
      '● permission asked between turns · ctrl+x a to answer',
      '·',
      '⏸ plan mode on',
    ]);
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('waits tone uses warning on the status row at $size', (
      t,
    ) async {
      await t.pumpWidget(
        StatusLine(
          facts: StatusFacts(
            model: 'Fake Large with a 1M context window',
            waits: betweenNotice('permission', 'ctrl+x a'),
          ),
        ),
        size: size,
      );
      expect(t.screen, shows('ctrl+x a to answer'));
      expect(t.screen.styleAt(0, 0), ThemeData.dark().warning);
    });
  }
}
