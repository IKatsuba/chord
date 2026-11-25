import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: context geometry thin delegation boundaries', () {
    testWidgets(
      'missing hook is false and each explicit query delegates once',
      (t) async {
        late BuildContext captured;
        await t.pumpWidget(
          Builder(
            builder: (context) {
              captured = context;
              return Text('geometry');
            },
          ),
        );
        final owner = captured.owner,
            original = captured.owner.synchronizeInputGeometry;
        var calls = 0;
        try {
          owner.synchronizeInputGeometry = null;
          expect(captured.ensureCurrentInputGeometry(), isFalse);
          owner.synchronizeInputGeometry = (passes) {
            expect(passes, 2);
            calls++;
            return false;
          };
          expect(captured.ensureCurrentInputGeometry(), isFalse);
          expect(calls, 1);
          owner.synchronizeInputGeometry = (passes) {
            expect(passes, 2);
            calls++;
            return true;
          };
          expect(captured.ensureCurrentInputGeometry(), isTrue);
          expect(calls, 2);
          t.host.dispose();
          expect(captured.ensureCurrentInputGeometry(), isFalse);
          expect(calls, 2);
        } finally {
          owner.synchronizeInputGeometry = original;
        }
      },
    );

    testWidgets('delegate exceptions retain identity and cause no retry', (
      t,
    ) async {
      late BuildContext captured;
      await t.pumpWidget(
        Builder(
          builder: (context) {
            captured = context;
            return Text('geometry');
          },
        ),
      );
      final owner = captured.owner,
          original = captured.owner.synchronizeInputGeometry;
      final error = ArgumentError('delegate sentinel');
      var calls = 0;
      owner.synchronizeInputGeometry = (_) {
        calls++;
        throw error;
      };
      try {
        expect(
          () => captured.ensureCurrentInputGeometry(),
          throwsA(same(error)),
        );
        expect(calls, 1);
      } finally {
        owner.synchronizeInputGeometry = original;
      }
      expect(captured.ensureCurrentInputGeometry(), isTrue);
    });

    for (final size in [
      const Size(0, 0),
      const Size(1, 1),
      const Size(0, 24),
      const Size(80, 0),
    ]) {
      testWidgets('known constrained geometry remains current $size', (
        t,
      ) async {
        late BuildContext captured;
        await t.pumpWidget(
          Builder(
            builder: (context) {
              captured = context;
              return Text('界👩‍💻é\x1b[31m');
            },
          ),
          size: size,
        );
        final before = t.inputLayoutPasses;
        expect(captured.ensureCurrentInputGeometry(), isTrue);
        expect(captured.ensureCurrentInputGeometry(), isTrue);
        expect(t.inputLayoutPasses, before);
      });
    }
  });
}
