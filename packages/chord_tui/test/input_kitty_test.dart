import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'six modifiers round trip independently through every key representation',
    () {
      for (var bits = 0; bits < 64; bits++) {
        final event = KeyEvent(
          'x',
          shift: bits & 1 != 0,
          alt: bits & 2 != 0,
          ctrl: bits & 4 != 0,
          superKey: bits & 8 != 0,
          hyper: bits & 16 != 0,
          meta: bits & 32 != 0,
        );
        final combo = event.combo;
        expect(KeyCombo.parse('$combo'), combo);
        expect(combo.toEvent().combo, combo);
        expect(combo.hashCode, KeyCombo.parse('$combo').hashCode);
        expect(event.char, bits & 62 == 0 ? 'x' : isNull);
        final parsed =
            InputParser().feed('\x1b[120;${bits + 1}u').single as KeyEvent;
        expect(parsed.combo, combo);
        expect(parsed.char, event.char);
      }
      expect(KeyCombo.parse('cmd+left'), KeyCombo.parse('super+left'));
      expect(KeyCombo.parse('COMMAND+right'), KeyCombo.parse('super+right'));
      expect(KeyCombo.parse('option+x'), KeyCombo.parse('alt+x'));
      expect(KeyCombo.parse('meta+x'), isNot(KeyCombo.parse('alt+x')));
      expect(KeyCombo.parse('ctrl+X'), KeyCombo.parse('ctrl+x'));
    },
  );
  test('kitty press/repeat/release, scalar and functional keys', () {
    final parser = InputParser();
    expect(parser.feed('\x1b[105;5u').single.toString(), 'KeyEvent(ctrl+i)');
    expect(parser.feed('\t').single.toString(), 'KeyEvent(tab)');
    expect(
      parser.feed('\x1b[13;2u').single.toString(),
      'KeyEvent(shift+enter)',
    );
    expect(
      parser.feed('\x1b[120;1:1u\x1b[120;1:2u\x1b[120;1:3u'),
      hasLength(2),
    );
    expect(parser.feed('\x1b[120;1:3u'), isEmpty);
    expect(parser.feed('\x1b[1;9:3D'), isEmpty);
    expect(
      parser.feed('\x1b[120::88;9:2;88:120u').single.toString(),
      // The base key is kept, lower-cased, though it reads as the press.
      'KeyEvent(super+x base x)',
    );
    expect((parser.feed('\x1b[30028u').single as KeyEvent).char, '界');
    for (final (code, key) in [
      (57350, 'left'),
      (57357, 'end'),
      (57364, 'f1'),
      (57375, 'f12'),
      (57414, 'enter'),
      (57417, 'left'),
    ]) {
      expect((parser.feed('\x1b[${code}u').single as KeyEvent).key, key);
    }
    expect(parser.feed('\x1b[120;193u').single.toString(), 'KeyEvent(x)');
    expect(parser.feed('\x1b[57358u'), isEmpty); // lock key, not typed PUA
  });
  test(
    'fragmented keyboard replies and keys are independent, including paste',
    () {
      const wire = 'a\x1b[?31u\x1b[13;2u\x1b[105;5ub';
      const expected = [
        'KeyEvent(a)',
        'KeyboardProtocolEvent(31)',
        'KeyEvent(shift+enter)',
        'KeyEvent(ctrl+i)',
        'KeyEvent(b)',
      ];
      for (var split = 0; split <= wire.length; split++) {
        final parser = InputParser();
        expect(
          [
            ...parser.feed(wire.substring(0, split)),
            ...parser.feed(wire.substring(split)),
          ].map((e) => '$e'),
          expected,
        );
      }
      final pasted = InputParser().feed('\x1b[200~\x1b[?1u\x1b[201~').single;
      expect((pasted as PasteEvent).text, '\x1b[?1u');
    },
  );
  test('malformed complete CSI controls never become text', () {
    for (final control in [
      '\x1b[?u',
      '\x1b[?1234567890u',
      '\x1b[1114112u',
      '\x1b[55296u',
      '\x1b[0u',
      '\x1b[31u',
      '\x1b[128u',
      '\x1b[63743u',
      '\x1b[97;0u',
      '\x1b[97;257u',
      '\x1b[97;1:0u',
      '\x1b[97;1:4u',
      '\x1b[97;1:1:1u',
      '\x1b[97:9999999999u',
      '\x1b[97;1;55296u',
      '\x1b[97;1;65;66u',
      '\x1b[-1u',
      '\x1b[999999999999999999u',
    ]) {
      final parser = InputParser();
      expect(parser.feed('${control}z').map((e) => '$e'), [
        'KeyEvent(z)',
      ], reason: control);
      expect(parser.hasPending, isFalse);
    }
  });
  test(
    'CSI fragments are bounded, time out without invented keys, and recover',
    () {
      final parser = InputParser();
      expect(parser.feed('\x1b[?'), isEmpty);
      expect(parser.hasPendingCsi, isTrue);
      expect(parser.flush(), isEmpty);
      expect(parser.hasPending, isFalse);
      expect(parser.feed('\x1b[${'9' * 200}'), isEmpty);
      expect(parser.hasPending, isTrue);
      expect(parser.feed('9uz').map((e) => '$e'), ['KeyEvent(z)']);
      expect(parser.hasPending, isFalse);
      expect(parser.feed('\x1b[${'9' * 200}'), isEmpty);
      expect(parser.flush(), isEmpty);
      expect(parser.feed('\x1b[Au\x1bOP').map((e) => '$e'), [
        'KeyEvent(up)',
        'KeyEvent(u)',
        'KeyEvent(f1)',
      ]);
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'Super row movement on an unwrapped line and described help at $size',
      (t) async {
        final controller = TextAreaController(
          text: '${'a' * 100}\nsecond line',
        );
        await t.pumpWidget(
          Column(
            children: [
              TextArea(controller: controller, autofocus: true),
              const KeyHelp(),
            ],
          ),
          size: size,
        );
        await t.press('cmd+left');
        expect(controller.cursor, 101);
        await t.press('super+right');
        expect(controller.cursor, 112);
        await t.press('ctrl+a');
        expect(controller.cursor, 101);
        await t.press('super+x hyper+y meta+z');
        expect(controller.text, '${'a' * 100}\nsecond line');
        final bindings = t.host.focusManager.activeBindings;
        expect(
          bindings.any(
            (b) =>
                '${b.chord}' == 'super+left' &&
                b.description == 'Move to row start',
          ),
          isTrue,
        );
        expect(
          bindings.any(
            (b) =>
                '${b.chord}' == 'super+right' &&
                b.description == 'Move to row end',
          ),
          isTrue,
        );
        t.dispose();
        controller.dispose();
      },
    );
  }
}
