import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Chord c(String keys) => Chord.parse(keys);

List<String> shown(List<Binding> bindings) => [
  for (final b in bindings) '${b.chord}=${b.id ?? b.description}',
];

void main() {
  group('Binding', () {
    test('copyWith keeps the id and changes what is given', () {
      final b = Binding('ctrl+o', 'Toggle', () {}, id: 'app:toggle');
      final moved = b.copyWith(chord: c('ctrl+t'));
      expect(moved.id, 'app:toggle');
      expect(moved.chord, c('ctrl+t'));
      expect(moved.description, 'Toggle');
      expect(moved.enabled, isTrue);
      expect(b.copyWith(enabled: false).enabled, isFalse);
    });

    test('scrollBindings carry the scroll ids', () {
      final controller = ScrollController();
      final ids = scrollBindings(
        controller,
        keys: const ScrollKeys(lineUp: ['shift+up'], lineDown: ['shift+down']),
      ).map((b) => b.id);
      expect(ids, [
        'scroll:pageUp',
        'scroll:pageDown',
        'scroll:lineUp',
        'scroll:lineDown',
        'scroll:top',
        'scroll:bottom',
      ]);
    });
  });

  group('KeymapData.apply', () {
    final defaults = [
      Binding('ctrl+c', 'Quit', () {}),
      Binding('pageup', 'Up a page', () {}, id: 'up'),
      Binding('shift+pageup', 'Up a page', () {}, id: 'up'),
      Binding('home', 'Top', () {}, id: 'top'),
      Binding('ctrl+x a', 'Attend', () {}, id: 'attend'),
    ];

    test('with nothing named, the bindings are as written', () {
      final r = const KeymapData().apply(defaults);
      expect(r.bindings, same(defaults));
      expect(r.conflicts, isEmpty);
    });

    test('moves, adds and removes keys at the first binding\'s place', () {
      final r = KeymapData({
        'up': [c('ctrl+u'), c('pageup')],
        'top': [],
        'nobody': [c('f')],
      }).apply(defaults);
      expect(shown(r.bindings), [
        'ctrl+c=Quit',
        'ctrl+u=up',
        'pageup=up',
        'ctrl+x a=attend',
      ]);
      expect(r.conflicts, isEmpty);
    });

    test('a key a fixed binding holds is left out and reported', () {
      final r = KeymapData({
        'top': [c('ctrl+c'), c('t')],
      }).apply(defaults);
      expect(shown(r.bindings), contains('t=top'));
      expect(shown(r.bindings), isNot(contains('ctrl+c=top')));
      final [conflict] = r.conflicts;
      expect(conflict.id, 'top');
      expect(conflict.chord, c('ctrl+c'));
      expect(conflict.other.description, 'Quit');
      expect(conflict.prefix, isFalse);
    });

    test('a key that starts or ends another chord is a prefix conflict', () {
      final r = KeymapData({
        'top': [c('ctrl+x')],
        'up': [c('ctrl+c b')],
      }).apply(defaults);
      expect(r.bindings.map((b) => b.id), isNot(contains('top')));
      expect(r.bindings.map((b) => b.id), isNot(contains('up')));
      expect(r.conflicts.map((x) => (x.id, x.prefix)), [
        ('up', true),
        ('top', true),
      ]);
    });

    test('of two keys the keymap gives, the later gives way', () {
      final r = KeymapData({
        'up': [c('u')],
        'top': [c('u')],
      }).apply(defaults);
      expect(shown(r.bindings), contains('u=up'));
      final [conflict] = r.conflicts;
      expect(conflict.id, 'top');
      expect(conflict.other.id, 'up');
    });

    test('a key moved off frees it for another id', () {
      final r = KeymapData({
        'top': [c('pageup')],
        'up': [c('ctrl+u')],
      }).apply(defaults);
      expect(shown(r.bindings), containsAll(['ctrl+u=up', 'pageup=top']));
      expect(r.conflicts, isEmpty);
    });

    test('equal by content', () {
      expect(
        KeymapData({
          'a': [c('x')],
        }),
        KeymapData({
          'a': [c('x')],
        }),
      );
      expect(
        KeymapData({
          'a': [c('x')],
        }),
        isNot(
          KeymapData({
            'a': [c('y')],
          }),
        ),
      );
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('Actions under a Keymap at $size', () {
      Future<(List<String>, ValueNotifier<KeymapData>)> pump(
        WidgetTester t, {
        KeymapData data = const KeymapData(),
        List<Binding>? extra,
      }) async {
        final log = <String>[];
        final keymap = ValueNotifier(data);
        addTearDown(keymap.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: keymap,
            builder: (_) => Keymap(
              data: keymap.value,
              child: Actions(
                bindings: [
                  Binding('q', 'Quit', () => log.add('quit'), id: 'app:quit'),
                  Binding(
                    'ctrl+x a',
                    'Attend',
                    () => log.add('attend'),
                    id: 'attend',
                  ),
                  ...?extra,
                ],
                child: Column(
                  children: [
                    Focus(autofocus: true, child: Text('body')),
                    KeyHelp(),
                  ],
                ),
              ),
            ),
          ),
          size: size,
        );
        return (log, keymap);
      }

      testWidgets('a moved key invokes, and the old one does not', (t) async {
        final (log, _) = await pump(
          t,
          data: KeymapData({
            'app:quit': [c('ctrl+q')],
          }),
        );
        await t.press('q');
        expect(log, isEmpty);
        await t.press('ctrl+q');
        expect(log, ['quit']);
        expect(t.screen.text, contains('ctrl+q Quit'));
      });

      testWidgets('a moved chord waits on its first key', (t) async {
        final (log, _) = await pump(
          t,
          data: KeymapData({
            'attend': [c('ctrl+b w')],
          }),
        );
        await t.press('ctrl+b');
        expect(t.screen.text, contains('ctrl+b …'));
        await t.press('w');
        expect(log, ['attend']);
      });

      testWidgets('a new keymap registers the scope again', (t) async {
        final (log, keymap) = await pump(t);
        await t.press('q');
        expect(log, ['quit']);
        keymap.value = KeymapData({'app:quit': []});
        await t.pump();
        await t.press('q');
        expect(log, ['quit']);
        expect(t.screen.text, isNot(contains('Quit')));
      });

      testWidgets('a key the keymap cannot bind leaves the scope working', (
        t,
      ) async {
        final (log, _) = await pump(
          t,
          data: KeymapData({
            'app:quit': [c('ctrl+x')],
          }),
        );
        await t.press('q');
        expect(log, isEmpty);
        expect(t.screen.text, isNot(contains('Quit')));
        await t.press('ctrl+x');
        await t.press('a');
        expect(log, ['attend']);
      });

      testWidgets('the app\'s own clash still throws', (t) async {
        expect(
          () => pump(t, extra: [Binding('q', 'Again', () {})]),
          throwsArgumentError,
        );
      });
    });
  }
}
