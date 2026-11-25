import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('detached queries never retain a copy snapshot or code geometry', () {
    final controller = SelectionController();
    expect(controller.value.phase, SelectionPhase.none);
    expect(controller.snapshot(), isNull);
    expect(controller.visibleCodeBlocks(), isEmpty);
    controller.clear();
    controller.dispose();
    expect(controller.snapshot, throwsStateError);
  });
}
