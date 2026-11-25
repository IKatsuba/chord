import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  List<String> keys(String data) => InputParser()
      .feed(data)
      .map((e) => e is KeyEvent ? e.combo.toString() : e.toString())
      .toList();

  group('InputParser', () {
    test('printable keys', () => expect(keys('aA?'), ['a', 'shift+a', '?']));
    test('control keys', () {
      expect(keys('\x0f\x18\r\t\x7f'), [
        'ctrl+o',
        'ctrl+x',
        'enter',
        'tab',
        'backspace',
      ]);
    });
    test('arrows and modifiers', () {
      expect(keys('\x1b[A\x1b[1;5C\x1b[3~\x1b[Z\x1bOP'), [
        'up',
        'ctrl+right',
        'delete',
        'shift+tab',
        'f1',
      ]);
    });
    test('alt', () => expect(keys('\x1bb\x1b\r'), ['alt+b', 'alt+enter']));
    test('CR is enter and LF is ctrl+j', () {
      expect(keys('\r\n\x1b\n'), ['enter', 'ctrl+j', 'ctrl+alt+j']);
    });
    test('LF is enter where the terminal turns CR into LF', () {
      final p = InputParser()..linefeedIsEnter = true;
      expect(p.feed('\n\r\x1b\n').map(_name), ['enter', 'enter', 'alt+enter']);
    });
    test('unicode', () => expect(keys('й🙂'), ['й', '🙂']));
    test('kitty CSI u', () => expect(keys('\x1b[97;5u'), ['ctrl+a']));

    test('a sequence split between reads', () {
      final p = InputParser();
      expect(p.feed('\x1b['), isEmpty);
      expect(p.hasPending, isTrue);
      expect((p.feed('B').single as KeyEvent).key, 'down');
    });

    test('a lone escape resolves on flush', () {
      final p = InputParser();
      expect(p.feed('\x1b'), isEmpty);
      expect((p.flush().single as KeyEvent).key, 'escape');
    });

    test('bracketed paste arrives whole', () {
      final p = InputParser();
      final first = p.feed('x\x1b[200~hello\r\nwor');
      expect(first, hasLength(1));
      final rest = p.feed('ld\x1b[201~y');
      expect((rest[0] as PasteEvent).text, 'hello\nworld');
      expect((rest[1] as KeyEvent).key, 'y');
    });
  });

  group('InputParser OSC replies', () {
    List<String> events(InputParser p, String data) =>
        p.feed(data).map(_name).toList();

    test('a reply ended by BEL or ESC backslash is an event, never keys', () {
      expect(events(InputParser(), 'a\x1b]11;rgb:ffff/0000/1234\x07b'), [
        'a',
        'OscEvent(11, rgb:ffff/0000/1234)',
        'b',
      ]);
      expect(events(InputParser(), '\x1b]10;#ffffff\x1b\\'), [
        'OscEvent(10, #ffffff)',
      ]);
    });

    test('a reply split across reads is held until it ends', () {
      final p = InputParser();
      for (final part in [
        '\x1b',
        ']',
        '1',
        '1;rgb:ff',
        'ff/ffff/ffff',
        '\x1b',
      ]) {
        expect(events(p, part), isEmpty, reason: part);
        expect(p.hasPending, isTrue);
      }
      expect(p.hasPendingOsc, isTrue);
      expect(events(p, '\\x'), ['OscEvent(11, rgb:ffff/ffff/ffff)', 'x']);
      expect(p.hasPending, isFalse);
      expect(p.hasPendingOsc, isFalse);
    });

    test('a lone escape is not a pending reply', () {
      final p = InputParser()..feed('\x1b');
      expect(p.hasPending, isTrue);
      expect(p.hasPendingOsc, isFalse);
    });

    test('ESC ] and no digit is alt+] at once', () {
      expect(events(InputParser(), '\x1b]x'), ['alt+]', 'x']);
      expect(events(InputParser(), '\x1b]\x1b[A'), ['alt+]', 'up']);
    });

    test('a reply broken off gives the keys back', () {
      // Digits followed by neither a digit nor ';'.
      expect(events(InputParser(), '\x1b]11x'), ['alt+]', '1', '1', 'x']);
      // A control character inside: it is parsed as usual.
      expect(events(InputParser(), '\x1b]11;ab\x03c'), [
        'alt+]',
        '1',
        '1',
        ';',
        'a',
        'b',
        'ctrl+c',
        'c',
      ]);
      // ESC followed by anything but a backslash.
      expect(events(InputParser(), '\x1b]1;a\x1b[B'), [
        'alt+]',
        '1',
        ';',
        'a',
        'down',
      ]);
    });

    test('more than 1024 characters of data is typed text', () {
      final ok = 'x' * 1024;
      expect(events(InputParser(), '\x1b]11;$ok\x07'), ['OscEvent(11, $ok)']);
      final p = InputParser();
      final out = events(p, '\x1b]11;${'x' * 1025}\x07');
      expect(out.first, 'alt+]');
      expect(out.last, 'ctrl+g');
      expect(out, hasLength(1 + 3 + 1025 + 1));
      expect(p.hasPending, isFalse);
    });

    test('an unterminated reply breaks on its 1025th character', () {
      final p = InputParser();
      expect(events(p, '\x1b]11;${'x' * 1024}'), isEmpty);
      expect(p.hasPendingOsc, isTrue);
      final out = events(p, 'xy');
      expect(out.first, 'alt+]');
      expect(out, hasLength(1 + 3 + 1024 + 2));
      expect(out.last, 'y');
      expect(p.hasPending, isFalse);
      final q = InputParser();
      expect(events(q, '\x1b]11;${'x' * 1025}'), hasLength(1 + 3 + 1025));
      expect(q.hasPending, isFalse);
    });

    test('a code of more than nine digits is typed text, never a throw', () {
      final out = events(InputParser(), '\x1b]${'9' * 24};x\x07a');
      expect(out.first, 'alt+]');
      expect(out.sublist(1, 25), List.filled(24, '9'));
      expect(out.sublist(25), [';', 'x', 'ctrl+g', 'a']);
      expect(events(InputParser(), '\x1b]123456789;x\x07'), [
        'OscEvent(123456789, x)',
      ]);
    });

    test('flush with a reply pending gives the keys back', () {
      final p = InputParser();
      expect(events(p, '\x1b]11;rgb:f'), isEmpty);
      expect(p.flush().map(_name), [
        'alt+]',
        '1',
        '1',
        ';',
        'r',
        'g',
        'b',
        ':',
        'f',
      ]);
      expect(p.hasPending, isFalse);
      final q = InputParser()..feed('\x1b]');
      expect(q.hasPendingOsc, isTrue);
      expect(q.flush().map(_name), ['alt+]']);
    });

    test('inside a bracketed paste ESC ] is pasted text', () {
      final p = InputParser();
      final out = p.feed('\x1b[200~a\x1b]11;x\x07b\x1b[201~');
      expect((out.single as PasteEvent).text, 'a\x1b]11;x\x07b');
      expect(p.hasPendingOsc, isFalse);
    });
  });

  group('tester: OSC parser boundaries', () {
    test('every two-feed split preserves reply data and surrounding keys', () {
      for (final data in ['', 'rgb:f/ff/ffff', '日本語🙂e\u0301;[]']) {
        for (final end in ['\x07', '\x1b\\']) {
          final reply = '\x1b]11;$data$end';
          for (var split = 0; split <= reply.length; split++) {
            final p = InputParser();
            final events = [
              ...p.feed('a${reply.substring(0, split)}'),
              ...p.feed('${reply.substring(split)}b'),
            ];
            expect(events.map(_name), [
              'a',
              'OscEvent(11, $data)',
              'b',
            ], reason: 'split $split of $reply');
            expect(p.hasPending, isFalse);
            expect(p.hasPendingOsc, isFalse);
            expect(p.flush(), isEmpty);
          }
        }
      }
    });

    test('one-code-unit feeds preserve a thousand consecutive replies', () {
      final p = InputParser();
      final events = <InputEvent>[];
      final input = 'x${'\x1b]11;rgb:0/0/0\x1b\\' * 1000}y';
      for (var i = 0; i < input.length; i++) {
        events.addAll(p.feed(input.substring(i, i + 1)));
      }
      expect(_name(events.first), 'x');
      expect(_name(events.last), 'y');
      expect(events.whereType<OscEvent>(), hasLength(1000));
      expect(events, hasLength(1002));
      expect(p.hasPending, isFalse);
    });

    test(
      'all disallowed control bytes recover and preserve the next reply',
      () {
        for (final control in [
          for (var c = 0; c < 32; c++)
            if (c != 7 && c != 27) c,
          127,
        ]) {
          final p = InputParser();
          final tail = '${String.fromCharCode(control)}z';
          final events = p.feed('\x1b]11;abc$tail\x1b]11;ok\x07');
          expect(events.map(_name), [
            'alt+]',
            '1',
            '1',
            ';',
            'a',
            'b',
            'c',
            ...InputParser().feed(tail).map(_name),
            'OscEvent(11, ok)',
          ], reason: 'control $control');
          expect(p.hasPending, isFalse);
        }
      },
    );

    test('flush clears incomplete command and split ST exactly once', () {
      for (final unfinished in [
        '\x1b]',
        '\x1b]11',
        '\x1b]11;',
        '\x1b]11;x\x1b',
      ]) {
        final p = InputParser();
        expect(p.feed(unfinished), isEmpty);
        expect(p.hasPendingOsc, isTrue);
        expect(p.flush().map(_name), [
          'alt+]',
          ...InputParser().feed(unfinished.substring(2)).map(_name),
          if (unfinished.endsWith('\x1b')) 'escape',
        ]);
        expect(p.hasPendingOsc, isFalse);
        expect(p.hasPending, isFalse);
        expect(p.flush(), isEmpty);
        expect(p.feed('\\z').map(_name), ['\\', 'z']);
        expect(p.feed('\x1b]11;late\x07').map(_name), ['OscEvent(11, late)']);
      }
    });

    test('fragmented paste holds OSC literally even across flush calls', () {
      final p = InputParser();
      const content = '🙂\x1b]11;rgb:f/f/f\x1b\\e\u0301';
      expect(p.feed('\x1b[200~'), isEmpty);
      for (var i = 0; i < content.length; i++) {
        expect(p.feed(content.substring(i, i + 1)), isEmpty);
        expect(p.hasPendingOsc, isFalse);
        expect(p.flush(), isEmpty);
      }
      expect(p.feed('\x1b[20'), isEmpty);
      expect(p.flush(), isEmpty);
      final events = p.feed('1~\x1b]11;outside\x07');
      expect((events.first as PasteEvent).text, content);
      expect(events.last.toString(), 'OscEvent(11, outside)');
      expect(p.hasPending, isFalse);
    });

    test('command and data limits recover across fragmented feeds', () {
      final p = InputParser();
      expect(p.feed('\x1b]999999999'), isEmpty);
      expect(p.feed('9').map(_name), ['alt+]', ...List.filled(10, '9')]);
      expect(p.hasPending, isFalse);
      final q = InputParser();
      expect(q.feed('\x1b]0;${'x' * 1024}'), isEmpty);
      expect(q.feed('\x1b'), isEmpty);
      expect(q.feed('\\').single.toString(), 'OscEvent(0, ${'x' * 1024})');
      expect(q.hasPending, isFalse);
    });
  });

  group('Chord', () {
    test('parses chords', () {
      final c = Chord.parse('ctrl+x a');
      expect(c.length, 2);
      expect('$c', 'ctrl+x a');
    });
    test('aliases and case', () {
      expect(KeyCombo.parse('Ctrl+Esc'), KeyCombo.parse('ctrl+escape'));
      expect(KeyCombo.parse('G'), KeyCombo.parse('shift+g'));
      expect('${KeyCombo.parse('ctrl++')}', 'ctrl++');
    });
    test('rejects unknown modifiers', () {
      expect(() => KeyCombo.parse('bogus+a'), throwsFormatException);
    });
  });
}

String _name(InputEvent e) => switch (e) {
  KeyEvent() => e.combo.toString(),
  _ => e.toString(),
};
