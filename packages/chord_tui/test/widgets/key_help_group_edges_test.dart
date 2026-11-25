import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: grouped help boundaries', () {
    test('groups snapshot their input and expose immutable bindings', () {
      final input = [Binding('a', '界👩‍💻é', () {}, id: 'action')];
      final groups = groupBindings(input);
      input.clear();
      expect(groups.single.description, '界👩‍💻é');
      expect(groups.single.chords, [Chord.parse('a')]);
      expect(() => groups.single.bindings.clear(), throwsUnsupportedError);
      groups.single.chords.clear();
      expect(groups.single.chords, [Chord.parse('a')]);
    });

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'Unicode descriptions and aliases survive tiny resize $size',
        (t) async {
          await t.pumpWidget(
            Actions(
              bindings: [
                Binding('a', '界👩‍💻é', () {}, id: 'one'),
                Binding('b', 'later wording', () {}, id: 'one'),
              ],
              child: Focus(autofocus: true, child: KeyHelp()),
            ),
            size: size,
          );
          expect(t.screen.text, contains('a/b 界👩‍💻é'));
          for (var width = 0; width < 15; width++) {
            await t.resize(Size(width, 1));
            expect(t.screen.lines, hasLength(1));
          }
          await t.resize(size);
          expect(t.screen.text, contains('a/b 界👩‍💻é'));
          expect(t.screen.text, isNot(contains('later wording')));
        },
      );

      testWidgets('both continuations of one group stay after pending $size', (
        t,
      ) async {
        await t.pumpWidget(
          Actions(
            bindings: [
              Binding('ctrl+x a', 'Choose', () {}, id: 'one'),
              Binding('ctrl+x b', 'Choose', () {}, id: 'one'),
              Binding('z', 'Choose', () {}, id: 'one'),
              Binding('q', 'Quit', () {}),
            ],
            child: Focus(autofocus: true, child: KeyHelp()),
          ),
          size: size,
        );
        await t.press('ctrl+x');
        expect(t.screen.text.trim(), 'ctrl+x …  ctrl+x a/ctrl+x b Choose');
        await t.press('b');
        expect(t.screen.text, contains('ctrl+x a/ctrl+x b/z Choose'));
        expect(t.screen.text, contains('q Quit'));
      });
    }
  });
}
