// Original state_test.ts: ctrl+o window part only. Scroll reducers belong to
// the framework; app event scroll effects are covered under ui/app.
import 'package:chord/ui/transcript/state.dart';
import 'package:test/test.dart';

void main() {
  test('ctrl+o expands and folds independent of turn or draft', () {
    const state = ViewWindow();
    expect(state.expanded, isFalse);
    final open = toggled(state);
    expect(open.expanded, isTrue);
    expect(toggled(open).expanded, isFalse);
    expect(state.expanded, isFalse);
  });
}
