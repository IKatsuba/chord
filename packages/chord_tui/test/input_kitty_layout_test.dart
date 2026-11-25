// kitty's base-layout key on a press, and the press as made on the US
// layout, as docs/design/CTUI-67.md has them.
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

KeyEvent _parse(String bytes) => InputParser().feed(bytes).single as KeyEvent;

void main() {
  group('tester: CTUI-67 protocol boundaries', () {
    test('every split of an alternate-key report preserves the next event', () {
      const bytes = '\x1b[1095:1063:120;253u';
      for (var split = 0; split <= bytes.length; split++) {
        final parser = InputParser();
        final events = [
          ...parser.feed(bytes.substring(0, split)),
          ...parser.feed('${bytes.substring(split)}界'),
        ];
        expect(events, hasLength(2), reason: 'split $split');
        final first = events.first as KeyEvent;
        final reading = first.onBaseLayout!;
        expect(first.baseKey, 'x');
        expect(
          [
            reading.ctrl,
            reading.alt,
            reading.shift,
            reading.superKey,
            reading.hyper,
            reading.meta,
          ],
          [true, false, false, true, true, true],
        );
        expect(reading.char, isNull);
        expect(identical(reading.typed, first), isTrue);
        expect((events.last as KeyEvent).char, '界');
      }
    });

    test(
      'all US shifted punctuation spends shift but keeps other modifiers',
      () {
        const plain = r'''`1234567890-=[]\;',./''';
        const shifted = r'''~!@#$%^&*()_+{}|:"<>?''';
        for (var i = 0; i < plain.length; i++) {
          const typed = KeyEvent('ф');
          final event = KeyEvent(
            typed.key,
            baseKey: plain[i],
            shift: true,
            ctrl: true,
            alt: true,
            superKey: true,
            hyper: true,
            meta: true,
          );
          final reading = event.onBaseLayout!;
          expect(reading.key, shifted[i]);
          expect(reading.shift, isFalse);
          expect([
            reading.ctrl,
            reading.alt,
            reading.superKey,
            reading.hyper,
            reading.meta,
          ], everyElement(isTrue));
          expect(reading.char, isNull);
        }
      },
    );
  });

  test('the third alternate field is the base key, lower-cased', () {
    final event = _parse('\x1b[1095::120;5u');
    expect(event.combo, KeyCombo.parse('ctrl+ч'));
    expect(event.baseKey, 'x');
    expect(event.toString(), 'KeyEvent(ctrl+ч base x)');
    expect(_parse('\x1b[1060:1060:65;5u').baseKey, 'a');
    expect(_parse('\x1b[97;5u').baseKey, isNull);
    expect(_parse('\x1b[97:65;5u').baseKey, isNull);
  });

  test('a control code or a private-use key is no base key', () {
    for (final base in [0, 9, 13, 27, 32, 127, 0x9f, 57344, 57399, 63743]) {
      expect(_parse('\x1b[1095::$base;5u').baseKey, isNull, reason: '$base');
    }
    expect(_parse('\x1b[1095::33;5u').baseKey, '!');
  });

  test('a legacy key never has one', () {
    expect((InputParser().feed('\x18').single as KeyEvent).baseKey, isNull);
    expect(_parse('\x1b[1;5A').baseKey, isNull);
  });

  test('on the base layout a letter keeps shift, any other key spends it '
      'on what US PC-101 types there', () {
    expect(
      const KeyEvent('ф', shift: true, baseKey: 'a').onBaseLayout!.combo,
      KeyCombo.parse('shift+a'),
    );
    final question = const KeyEvent(
      '.',
      shift: true,
      baseKey: '/',
    ).onBaseLayout!;
    expect(question.combo, KeyCombo.parse('?'));
    expect(question.shift, isFalse);
    expect(
      const KeyEvent(
        'ч',
        ctrl: true,
        alt: true,
        baseKey: 'x',
      ).onBaseLayout!.combo,
      KeyCombo.parse('ctrl+alt+x'),
    );
    expect(
      const KeyEvent(
        '1',
        shift: true,
        superKey: true,
        baseKey: '1',
      ).onBaseLayout!.combo,
      KeyCombo.parse('super+!'),
    );
  });

  test('none without a base key, or where it reads as the press itself', () {
    expect(const KeyEvent('ч', ctrl: true).onBaseLayout, isNull);
    expect(const KeyEvent('x', ctrl: true, baseKey: 'x').onBaseLayout, isNull);
  });

  test('a reading never types, and knows the press it was read from', () {
    const typed = KeyEvent('ф', baseKey: 'a');
    final reading = typed.onBaseLayout!;
    expect(reading.key, 'a');
    expect(reading.char, isNull);
    expect(identical(reading.typed, typed), isTrue);
    expect(typed.char, 'ф');
  });
}
