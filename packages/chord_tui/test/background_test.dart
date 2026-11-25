import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('brightnessFromOsc11', () {
    test('a whole answer, ended by BEL or ESC backslash', () {
      expect(
        brightnessFromOsc11('\x1b]11;rgb:0000/0000/0000\x07'),
        Brightness.dark,
      );
      expect(
        brightnessFromOsc11('\x1b]11;rgb:ffff/ffff/ffff\x1b\\'),
        Brightness.light,
      );
    });

    test('the colour alone', () {
      expect(brightnessFromOsc11('rgb:1e1e/1e1e/2e2e'), Brightness.dark);
      expect(brightnessFromOsc11('rgb:fdfd/f6f6/e3e3'), Brightness.light);
    });

    test('one to four hex digits a channel', () {
      expect(brightnessFromOsc11('rgb:f/f/f'), Brightness.light);
      expect(brightnessFromOsc11('rgb:2/2/2'), Brightness.dark);
      expect(brightnessFromOsc11('rgb:eee/eee/eee'), Brightness.light);
      expect(brightnessFromOsc11('rgb:ff/ff/ff'), Brightness.light);
    });

    test('#rrggbb', () {
      expect(brightnessFromOsc11('\x1b]11;#ffffff\x07'), Brightness.light);
      expect(brightnessFromOsc11('#282c34'), Brightness.dark);
    });

    test('perceived brightness over 128 is light, as OpenTUI decides', () {
      // 128 is not over 128; 129 is.
      expect(brightnessFromOsc11('#808080'), Brightness.dark);
      expect(brightnessFromOsc11('#818181'), Brightness.light);
      // Green weighs most: pure green is light, pure blue dark.
      expect(brightnessFromOsc11('#00ff00'), Brightness.light);
      expect(brightnessFromOsc11('#0000ff'), Brightness.dark);
    });

    test('anything else is null', () {
      for (final reply in [
        '',
        'rgb:',
        'rgb:ff/ff',
        'rgb:fffff/0/0',
        'rgb:gg/gg/gg',
        '#fff',
        '\x1b]10;rgb:ffff/ffff/ffff\x07',
        'rgb:ffff/ffff/ffff junk',
      ]) {
        expect(brightnessFromOsc11(reply), isNull, reason: reply);
      }
    });
  });

  group('brightnessFromColorFgBg', () {
    test('7 or 15 last is light', () {
      expect(brightnessFromColorFgBg('0;15'), Brightness.light);
      expect(brightnessFromColorFgBg('0;default;7'), Brightness.light);
    });

    test('any other number last is dark', () {
      expect(brightnessFromColorFgBg('15;0'), Brightness.dark);
      expect(brightnessFromColorFgBg('7;8'), Brightness.dark);
    });

    test('unset, empty or no number last is null', () {
      expect(brightnessFromColorFgBg(null), isNull);
      expect(brightnessFromColorFgBg(''), isNull);
      expect(brightnessFromColorFgBg('15;default'), isNull);
    });
  });

  group('resolveBackground', () {
    test('the terminal first', () {
      expect(
        resolveBackground(Brightness.light, '15;0'),
        const TerminalBackground(Brightness.light, BrightnessSource.terminal),
      );
    });

    test('then COLORFGBG', () {
      expect(
        resolveBackground(null, '0;15'),
        const TerminalBackground(Brightness.light, BrightnessSource.colorFgBg),
      );
    });

    test('else dark by default', () {
      expect(
        resolveBackground(null, 'x'),
        const TerminalBackground(Brightness.dark, BrightnessSource.fallback),
      );
    });
  });

  group('tester: background detection edges', () {
    test('all channel widths keep the rounding boundary', () {
      for (final channels in [
        ['7', '7', '7'],
        ['80', '80', '80'],
        ['808', '808', '808'],
        ['8080', '8080', '8080'],
      ]) {
        expect(
          brightnessFromOsc11('rgb:${channels.join('/')}'),
          Brightness.dark,
        );
      }
      for (final channels in [
        ['8', '8', '8'],
        ['81', '81', '81'],
        ['810', '810', '810'],
        ['8181', '8181', '8181'],
      ]) {
        expect(
          brightnessFromOsc11('rgb:${channels.join('/')}'),
          Brightness.light,
        );
      }
    });

    test('mixed channel widths and hex case use the same colour', () {
      for (final payload in ['rgb:F/fF/fffF', 'rgb:0/FF/000', '#aBcDeF']) {
        for (final prefix in ['', '\x1b]11;']) {
          for (final suffix in ['', '\x07', '\x1b\\']) {
            expect(
              brightnessFromOsc11('$prefix$payload$suffix'),
              Brightness.light,
              reason: '$prefix$payload$suffix',
            );
          }
        }
      }
      expect(brightnessFromOsc11('rgb:FFFF/0/00'), Brightness.dark);
    });

    test('rejects broken framing and extra terminal content', () {
      for (final reply in [
        '\x1b]11;rgb:ff/ff/ff\x1b',
        '\x1b]11;rgb:ff/ff/ff\x1b/',
        '\x1b]11;rgb:ff/ff/ff\x07\x07',
        '\x1b]11;rgb:ff/ff/ff\x1b\\x',
        '\x1b]11;rgb:ff/ff/ff\x07key',
        'key\x1b]11;rgb:ff/ff/ff\x07',
        '\x1b]11;rgb:ff/ff/ff\x07\x1b]11;rgb:0/0/0\x07',
        '\x1b]11;#ffffff\n',
        ' #ffffff',
        '#ffffff ',
      ]) {
        expect(brightnessFromOsc11(reply), isNull, reason: reply);
      }
    });

    test(
      'rejects missing, overlong and non-hex channels in every position',
      () {
        for (var channel = 0; channel < 3; channel++) {
          for (final invalid in [
            '',
            'fffff',
            '-1',
            '+f',
            '0xF',
            ' f',
            'f ',
            'é',
          ]) {
            final channels = ['ff', 'ff', 'ff']..[channel] = invalid;
            final reply = 'rgb:${channels.join('/')}';
            expect(brightnessFromOsc11(reply), isNull, reason: reply);
          }
        }
      },
    );

    test('COLORFGBG uses only the final trimmed field', () {
      for (final value in ['7', 'bad; 7 ', ';15', '0;;15', '7;15\t']) {
        expect(brightnessFromColorFgBg(value), Brightness.light, reason: value);
      }
      for (final value in ['15;', '7; ', '0;-7', '0;+7', '0;7.0', '0;0x7']) {
        expect(brightnessFromColorFgBg(value), isNull, reason: value);
      }
      expect(brightnessFromColorFgBg('15;255'), Brightness.dark);
    });

    test('dark terminal overrides light environment and invalid fallback', () {
      for (final value in [null, '', '0;15', 'invalid']) {
        expect(
          resolveBackground(Brightness.dark, value),
          const TerminalBackground(Brightness.dark, BrightnessSource.terminal),
        );
      }
      expect(
        resolveBackground(null, '15;0'),
        const TerminalBackground(Brightness.dark, BrightnessSource.colorFgBg),
      );
      expect(
        resolveBackground(brightnessFromOsc11('rgb:bad'), '0;7'),
        const TerminalBackground(Brightness.light, BrightnessSource.colorFgBg),
      );
    });
  });
}
