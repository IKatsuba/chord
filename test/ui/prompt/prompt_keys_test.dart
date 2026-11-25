// The prompt's own keys follow the keybindings file, from the original's
// tests/ui/shortcuts/bindings_test.ts: send, newline, history and the text
// area's editing keys.
import 'dart:convert';

import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Keybindings read(Map<String, Object?> chat) => readKeybindings(
  jsonEncode({
    'bindings': [
      {'context': 'Chat', 'bindings': chat},
    ],
  }),
).keymap;

void main() {
  test('with no file the text area keeps every key of its own', () {
    expect(textareaKeysOff(defaultKeymap), isEmpty);
  });

  test('keys follow the file: send, newline, history and the editor', () {
    final keymap = read({
      'enter': 'chat:newline',
      'ctrl+s': 'chat:submit',
      'ctrl+p': 'history:previous',
      'ctrl+g': null,
      'ctrl+e': 'chat:externalEditor',
    });
    expect(textareaKeysOff(keymap), {'enter', 'ctrl+e'});
    // The text area breaks the line on its own keys; Enter is the prompt's.
    expect(promptKeys(keymap, 'chat:newline', textareaKeysOff(keymap)), [
      'enter',
    ]);
    expect(promptKeys(keymap, 'history:previous', textareaKeysOff(keymap)), [
      'ctrl+p',
    ]);
  });

  test('a key moved elsewhere, or the start of a chord, is turned off', () {
    expect(
      textareaKeysOff(read({'ctrl+k': 'chat:externalEditor'})),
      contains('ctrl+k'),
    );
    final chord = read({'ctrl+k ctrl+e': 'chat:externalEditor'});
    expect(
      textareaKeysOff(chord, [Chord.parse('ctrl+k ctrl+e')]),
      contains('ctrl+k'),
    );
    // ↑ and ↓ always move between lines.
    expect(textareaKeysOff(read({'up': null})), isNot(contains('up')));
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the prompt sends, breaks lines and walks history on the '
        "file's keys, at $size", (t) async {
      final c = TextAreaController();
      final sent = <String>[];
      var older = 0;
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              onSubmit: sent.add,
              onOlder: () => older++,
              onNewer: () {},
              keymap: read({
                'enter': 'chat:newline',
                'ctrl+s': 'chat:submit',
                'ctrl+p': 'history:previous',
                'ctrl+k': 'chat:imagePaste',
              }),
            ),
          ],
        ),
        size: size,
      );
      await t.type('hi');
      await t.press('enter');
      await t.type('there');
      expect(c.text, 'hi\nthere');
      expect(sent, isEmpty);
      // ctrl+k is the window's now, and cuts nothing.
      await t.press('home');
      await t.press('ctrl+a');
      await t.press('ctrl+k');
      expect(c.text, 'hi\nthere');
      await t.press('ctrl+s');
      expect(sent, ['hi\nthere']);
      await t.press('ctrl+p');
      expect(older, 1);
    });

    Future<(List<String>, List<String>)> prompt(
      WidgetTester t,
      Map<String, Object?> chat, {
      String text = '',
    }) async {
      final c = TextAreaController(text: text)..cursor = text.length;
      final sent = <String>[];
      final walked = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            PromptInput(
              controller: c,
              windowRows: size.height,
              onSubmit: sent.add,
              onOlder: () => walked.add('older'),
              onNewer: () => walked.add('newer'),
              walking: true,
              keymap: read(chat),
            ),
          ],
        ),
        size: size,
      );
      return (sent, walked);
    }

    testWidgets('an arrow given to sending mounts and sends, at $size', (
      t,
    ) async {
      final (sent, walked) = await prompt(t, {'up': 'chat:submit'}, text: 'hi');
      await t.press('up');
      expect(sent, ['hi']);
      expect(walked, isEmpty);
    });

    testWidgets('an arrow history no longer has moves between rows and '
        'recalls nothing, at $size', (t) async {
      final (_, walked) = await prompt(t, {
        'up': null,
        'down': null,
      }, text: 'one\ntwo');
      await t.press('up');
      await t.press('up');
      await t.type('X');
      await t.press('down');
      await t.press('down');
      expect(walked, isEmpty);
      expect(t.screen.text, contains('oneX'));
    });

    testWidgets('a printable key the prompt binds types nothing, at $size', (
      t,
    ) async {
      final (sent, _) = await prompt(t, {'x': 'chat:submit'});
      await t.type('hi');
      await t.press('x');
      expect(sent, ['hi']);
    });

    testWidgets('a chord the prompt binds on an editing key mounts, cuts '
        'nothing and sends, at $size', (t) async {
      final (sent, _) = await prompt(t, {'ctrl+k ctrl+s': 'chat:submit'});
      await t.type('abc');
      await t.press('left');
      await t.press('ctrl+k');
      await t.press('ctrl+s');
      expect(sent, ['abc']);
    });

    testWidgets('a shifted character that is no letter does the prompt '
        "binding it names, at $size", (t) async {
      final (sent, _) = await prompt(t, {'#': 'chat:submit'});
      await t.type('hi');
      t.host.handleKey(const KeyEvent('#', shift: true));
      await t.pump();
      expect(sent, ['hi']);
    });
  }
}
