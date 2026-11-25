import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: kitty modifiers and input boundaries', () {
    test(
      'lock bits and every split preserve all modifiers and event types',
      () {
        for (var bits = 0; bits < 64; bits++) {
          final expected =
              (InputParser().feed('\x1b[120;${bits + 1}u').single as KeyEvent)
                  .combo;
          for (final locks in [0, 64, 128, 192]) {
            for (final event in [1, 2, 3]) {
              final wire = '\x1b[120;${bits + locks + 1}:${event}u';
              for (var split = 0; split <= wire.length; split++) {
                final parser = InputParser();
                final output = [
                  ...parser.feed(wire.substring(0, split)),
                  ...parser.feed(wire.substring(split)),
                ];
                if (event == 3) {
                  expect(output, isEmpty);
                } else {
                  expect((output.single as KeyEvent).combo, expected);
                }
                expect(parser.hasPending, isFalse);
              }
            }
          }
        }
      },
    );

    test('scalar boundaries stay controls or complete Unicode keys', () {
      for (final scalar in [0xa0, 0xd7ff, 0xf900, 0x10000, 0x1f469, 0x10ffff]) {
        final wire = '\x1b[${scalar}u';
        final parser = InputParser();
        final events = <InputEvent>[];
        for (final rune in wire.runes) {
          events.addAll(parser.feed(String.fromCharCode(rune)));
        }
        expect((events.single as KeyEvent).char, String.fromCharCode(scalar));
      }
      for (final scalar in [
        0,
        31,
        159,
        0xd800,
        0xdfff,
        0xe100,
        0xf8ff,
        0x110000,
      ]) {
        expect(
          InputParser().feed('\x1b[${scalar}u\x1b[13;2u').map((e) => '$e'),
          ['KeyEvent(shift+enter)'],
        );
      }
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'release never edits and Super movement preserves Unicode at $size',
        (t) async {
          final controller = TextAreaController(text: '界👩‍💻e\u0301\nsecond');
          await t.pumpWidget(
            TextArea(controller: controller, autofocus: true),
            size: size,
          );
          final parser = InputParser();
          for (final event in parser.feed(
            '\x1b[120;1:1u\x1b[120;1:2u\x1b[120;1:3u',
          )) {
            t.host.handleKey(event as KeyEvent);
          }
          await t.pump();
          expect(controller.text, '界👩‍💻e\u0301\nsecondxx');
          for (final event in parser.feed('\x1b[1;9D\x1b[1;9:3C')) {
            t.host.handleKey(event as KeyEvent);
          }
          await t.pump();
          expect(controller.beforeCursor, '界👩‍💻e\u0301\n');
          await t.press('command+right');
          expect(controller.cursor, controller.length);
          await t.press('hyper+x meta+x');
          expect(controller.text, '界👩‍💻e\u0301\nsecondxx');
          t.dispose();
          controller.dispose();
        },
      );
    }
  });
}
