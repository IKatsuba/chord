import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('groupBindings', () {
    test('by id, else by description, in first-seen order', () {
      final groups = groupBindings([
        Binding('pageup', 'Up', () {}, id: 'up'),
        Binding('q', 'Quit', () {}),
        Binding('shift+pageup', 'Up a page', () {}, id: 'up'),
        Binding('ctrl+q', 'Quit', () {}),
        Binding('u', 'Up', () {}),
      ]);
      expect(
        [for (final g in groups) (g.id, g.description, g.chords.join('/'))],
        [
          ('up', 'Up', 'pageup/shift+pageup'),
          (null, 'Quit', 'q/ctrl+q'),
          (null, 'Up', 'u'),
        ],
      );
    });

    test('nothing gives no groups', () {
      expect(groupBindings(const []), isEmpty);
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('KeyHelp at $size', () {
      Future<void> pump(WidgetTester t, {KeymapData? keymap}) async {
        final actions = Actions(
          bindings: [
            Binding('ctrl+x a', 'Attend', () {}, id: 'attend'),
            Binding('q', 'Quit', () {}, id: 'quit'),
            Binding('pageup', 'Scroll up a page', () {}, id: 'up'),
            Binding('shift+pageup', 'Scroll up a page', () {}, id: 'up'),
            Binding('ctrl+x b', 'Pick', () {}, id: 'pick'),
            Binding('g', 'Pick', () {}, id: 'pick'),
          ],
          child: Column(
            children: [
              Focus(autofocus: true, child: Text('body')),
              KeyHelp(),
            ],
          ),
        );
        await t.pumpWidget(
          keymap == null ? actions : Keymap(data: keymap, child: actions),
          size: size,
        );
      }

      String line(WidgetTester t) => t.screen.lines[1];

      testWidgets('the keys of one action are one entry, joined by /', (
        t,
      ) async {
        await pump(t);
        expect(
          line(t),
          startsWith(
            'ctrl+x a Attend  q Quit  pageup/shift+pageup Scroll up a page',
          ),
        );
        expect('Scroll up a page'.allMatches(line(t)), hasLength(1));
        final slash = line(t).indexOf('/');
        expect(t.screen.styleAt(slash, 1).isBold, isTrue);
        expect(t.screen.styleAt(slash + 2, 1).isDim, isFalse);
      });

      testWidgets('a pending chord keeps a group\'s chords that continue it, '
          'and leaves out a group with none', (t) async {
        await pump(t);
        await t.press('ctrl+x');
        expect(line(t), 'ctrl+x …  ctrl+x a Attend  ctrl+x b Pick');
      });

      testWidgets('moved keys are drawn where the action was', (t) async {
        await pump(
          t,
          keymap: KeymapData({
            'quit': [Chord.parse('ctrl+q')],
          }),
        );
        expect(line(t), startsWith('ctrl+x a Attend  ctrl+q Quit  pageup/'));
      });
    });
  }
}
