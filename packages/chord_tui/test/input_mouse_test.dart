import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

String _describe(InputEvent event) => event is MouseEvent
    ? '${event.kind.name}:${event.button.name}:${event.position}:${event.scrollDelta}:${event.shift}:${event.alt}:${event.ctrl}'
    : '$event';

void main() {
  test('SGR button, wheel direction, coordinates and modifier fields', () {
    final parser = InputParser();
    for (final (button, name) in [
      (0, MouseButton.primary),
      (1, MouseButton.middle),
      (2, MouseButton.secondary),
    ]) {
      for (final finalByte in ['M', 'm']) {
        final event =
            parser.feed('\x1b[<$button;12;8$finalByte').single as MouseEvent;
        expect(
          event.kind,
          finalByte == 'M' ? MouseEventKind.press : MouseEventKind.release,
        );
        expect(event.button, name);
        expect(event.position, const Offset(11, 7));
        expect(event.scrollDelta, Offset.zero);
      }
    }
    for (var i = 0; i < 4; i++) {
      final event = parser.feed('\x1b[<${64 + i};1;1M').single as MouseEvent;
      expect(event.kind, MouseEventKind.wheel);
      expect(event.button, MouseButton.none);
      expect(
        event.scrollDelta,
        const [Offset(0, -1), Offset(0, 1), Offset(-1, 0), Offset(1, 0)][i],
      );
    }
    for (var bits = 0; bits < 8; bits++) {
      final event =
          parser.feed('\x1b[<${64 + bits * 4};2;3M').single as MouseEvent;
      expect(event.shift, bits & 1 != 0);
      expect(event.alt, bits & 2 != 0);
      expect(event.ctrl, bits & 4 != 0);
    }
  });
  test('held-button motion retains supported buttons and all modifiers', () {
    for (var bits = 0; bits < 8; bits++) {
      for (var button = 0; button < 3; button++) {
        final wire = '\x1b[<${32 + button + bits * 4};9;7M';
        for (var split = 0; split <= wire.length; split++) {
          final parser = InputParser();
          final event =
              [
                    ...parser.feed(wire.substring(0, split)),
                    ...parser.feed(wire.substring(split)),
                  ].single
                  as MouseEvent;
          expect(event.kind, MouseEventKind.move);
          expect(event.button, MouseButton.values[button + 1]);
          expect(event.position, const Offset(8, 6));
          expect(event.scrollDelta, Offset.zero);
          expect(event.shift, bits & 1 != 0);
          expect(event.alt, bits & 2 != 0);
          expect(event.ctrl, bits & 4 != 0);
        }
      }
    }
    expect(InputParser().feed('\x1b[<32;1;1mz').map((e) => '$e'), [
      'KeyEvent(z)',
    ]);
  });
  test(
    'all report split boundaries preserve reports once and never create keys',
    () {
      const wire = 'a\x1b[<64;5;6M\x1b[<28;2;3M\x1b[<32;7;8M\x1b[<0;2;3mb';
      final expected = InputParser().feed(wire).map(_describe).toList();
      for (var split = 0; split <= wire.length; split++) {
        final parser = InputParser();
        expect(
          [
            ...parser.feed(wire.substring(0, split)),
            ...parser.feed(wire.substring(split)),
          ].map(_describe),
          expected,
        );
      }
      final parser = InputParser();
      final events = <InputEvent>[];
      for (final byte in wire.split('')) {
        events.addAll(parser.feed(byte));
      }
      expect(events.map(_describe), expected);
      expect(events.whereType<KeyEvent>().map((e) => e.key), ['a', 'b']);
    },
  );
  test('invalid and unsupported reports are controls with recovery', () {
    for (final params in [
      '0;0;1',
      '0;1;0',
      '0;-1;1',
      '0;1.5;2',
      '0;;2',
      '0;1',
      '0;1;2;3',
      '3;1;1',
      '35;1;1',
      '96;1;1',
      '128;1;1',
      '0;1234567890;1',
      '9999999999;1;1',
    ]) {
      expect(
        InputParser()
            .feed(
              '\x1b[<$params'
              'Mz',
            )
            .map((e) => '$e'),
        ['KeyEvent(z)'],
        reason: params,
      );
    }
    expect(InputParser().feed('\x1b[<64;1;1mz').map((e) => '$e'), [
      'KeyEvent(z)',
    ]);
    expect(InputParser().feed('\x1b[M !!!z').map((e) => '$e'), [
      'KeyEvent(!)',
      'KeyEvent(z)',
    ]);
  });
  test(
    'overlong or timed-out mouse fragments drain without numeric text leakage',
    () {
      final parser = InputParser();
      expect(parser.feed('\x1b[<64;${'9' * 200}'), isEmpty);
      expect(parser.feed(';1Mz').map((e) => '$e'), ['KeyEvent(z)']);
      expect(parser.feed('\x1b[<64;12;'), isEmpty);
      expect(parser.flush(), isEmpty);
      expect(parser.hasPending, isFalse);
      expect(parser.feed('8Mz').map((e) => '$e'), ['KeyEvent(z)']);
      expect(parser.feed('\x1b[<0;1;\x1b[A').single.toString(), 'KeyEvent(up)');
      parser.feed('\x1b[<64;');
      parser.reset();
      expect(parser.feed('\x1b[<65;1;1M').single, isA<MouseEvent>());
    },
  );
  test('paste contents resembling mouse reports remain literal', () {
    const text = '\x1b[<64;1;1M\x1b[<32;4;5M\x1b[<0;1;1m';
    final events = InputParser().feed('\x1b[200~$text\x1b[201~z');
    expect((events.first as PasteEvent).text, text);
    expect(events.whereType<MouseEvent>(), isEmpty);
    expect((events.last as KeyEvent).key, 'z');
  });
}
