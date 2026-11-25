import 'package:chord/ui/transcript/state.dart';
import 'package:test/test.dart';

void main() {
  group('tester U3 window details state', () {
    test(
      'repeated toggles retain earlier snapshots and independent windows',
      () {
        const first = ViewWindow();
        const second = ViewWindow(expanded: true);
        var latest = first;
        for (var i = 1; i <= 1000; i++) {
          final before = latest;
          latest = toggled(latest);
          expect(latest, isNot(same(before)));
          expect(latest.expanded, i.isOdd);
          expect(before.expanded, i.isEven);
        }
        expect(first.expanded, isFalse);
        expect(second.expanded, isTrue);
        expect(toggled(second).expanded, isFalse);
      },
    );
  });
}
