// The bytes that set the terminal's `chord_session` user variable, pinned to
// the original's tests/notify_test.ts 457-475.
import 'dart:convert';

import 'package:chord/notify.dart';
import 'package:test/test.dart';

const _id = '0199f1c2-7c1e-7d43-9a3b-5f0e2c1d4b6a';

void main() {
  group('CTUI-159: sessionVarBytes as the original pins it', () {
    test("an id goes as iTerm2's SetUserVar, base64 of its UTF-8, ended by "
        'BEL', () {
      expect(
        sessionVarBytes(_id, tmux: false),
        '\x1b]1337;SetUserVar=chord_session='
        'MDE5OWYxYzItN2MxZS03ZDQzLTlhM2ItNWYwZTJjMWQ0YjZh\x07',
      );
    });

    test('none goes as the empty value: nothing to resume', () {
      expect(
        sessionVarBytes(null, tmux: false),
        '\x1b]1337;SetUserVar=chord_session=\x07',
      );
    });

    test(
      "inside tmux it goes through tmux's passthrough, each ESC doubled",
      () {
        expect(
          sessionVarBytes(_id, tmux: true),
          '\x1bPtmux;\x1b\x1b]1337;SetUserVar=chord_session='
          'MDE5OWYxYzItN2MxZS03ZDQzLTlhM2ItNWYwZTJjMWQ0YjZh\x07\x1b\\',
        );
        expect(
          sessionVarBytes(null, tmux: true),
          '\x1bPtmux;\x1b\x1b]1337;SetUserVar=chord_session=\x07\x1b\\',
        );
      },
    );

    test('an odd id goes through encoded and decodes back whole', () {
      const odd = 'sess;=\x07\x1b]é 名 👩‍💻\n';
      const head = '\x1b]1337;SetUserVar=chord_session=';
      final bytes = sessionVarBytes(odd, tmux: false);
      expect(bytes, startsWith(head));
      expect(bytes, endsWith('\x07'));
      final value = bytes.substring(head.length, bytes.length - 1);
      expect(value, matches(RegExp(r'^[A-Za-z0-9+/=]*$')));
      expect(utf8.decode(base64.decode(value)), odd);
    });
  });
}
