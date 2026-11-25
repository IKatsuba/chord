import 'package:chord/ui/dialogs/plan_scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('the plan Note scroll, as the original PlanBox keeps its top', () {
    test('follows the tail until paged, and back to it on follow', () {
      final scroll = PlanNoteScroll()..configure(20, 5);
      var heard = 0;
      scroll.addListener(() => heard++);
      expect(scroll.overflows, isTrue);
      expect(scroll.top, 16);
      // The Note grows while it follows: the view stays at its end.
      scroll.configure(30, 5);
      expect(scroll.top, 26);
      scroll.step(ScrollStep.pageUp);
      expect(scroll.top, 23);
      expect(heard, 1);
      // Paged, it keeps its row as the Note grows.
      scroll.configure(40, 5);
      expect(scroll.top, 23);
      scroll.step(ScrollStep.top);
      expect(scroll.top, 0);
      // At the top, a page up moves nothing and tells no one.
      scroll.step(ScrollStep.pageUp);
      expect(heard, 2);
      scroll.follow();
      expect(scroll.top, 36);
      expect(heard, 3);
      scroll.follow();
      expect(heard, 3);
    });

    test('keeps the row it was paged to through a room that grows and '
        'shrinks back', () {
      final scroll = PlanNoteScroll()..configure(20, 5);
      scroll.step(ScrollStep.pageUp);
      scroll.step(ScrollStep.pageUp);
      final paged = scroll.top;
      scroll.configure(20, 30);
      expect(scroll.overflows, isFalse);
      expect(scroll.top, 0);
      scroll.configure(20, 5);
      expect(scroll.top, paged);
    });

    test('a one-row room moves a row at a time', () {
      final scroll = PlanNoteScroll()..configure(4, 1);
      expect(scroll.top, 3);
      scroll.step(ScrollStep.pageUp);
      expect(scroll.top, 2);
      scroll.step(ScrollStep.pageDown);
      expect(scroll.top, 3);
    });
  });
}
