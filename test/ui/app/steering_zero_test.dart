import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'steering_window_test.dart' show connected, send;
import 'window_fake_test.dart' show until;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('Tab at zero area cannot take a serialized second row $size', (
      t,
    ) async {
      final f = await connected(t, size);
      await send(t, 'running');
      await send(t, 'first');
      await send(t, 'second');
      await t.type('draft');
      await t.press('tab');
      await until(() => f.agent.pendingSteers.length == 1);
      expect(
        f.connection.app.value.queue.where((row) => row.taken),
        hasLength(1),
      );
      for (final zero in [Size.zero, const Size(0, 24), const Size(80, 0)]) {
        await t.resize(zero);
        await t.press('tab');
        expect(
          f.connection.app.value.queue.where((row) => row.taken),
          hasLength(1),
        );
        expect(f.agent.pendingSteers, hasLength(1));
        expect(f.connection.app.value.draft, 'draft');
      }
      // Positive clipped surfaces retain the original query/action boundary.
      await t.resize(const Size(8, 3));
      expect(
        f.connection.app.value.queue.where((row) => row.taken),
        hasLength(1),
      );
      await t.press('tab');
      expect(
        f.connection.app.value.queue.where((row) => row.taken),
        hasLength(2),
      );
      expect(f.agent.pendingSteers, hasLength(1));
      f.agent.answerSteer();
      await until(() => f.agent.pendingSteers.length == 1);
      f.agent.answerSteer();
      await until(() => f.connection.app.value.queue.isEmpty);
      await t.resize(size);
      expect(f.connection.app.value.draft, 'draft');
      expect(
        f.agent.requests.where((r) => r['method'] == '_session/steering'),
        hasLength(2),
      );
    });
  }
}
