import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/prompt/prompt.dart' show endOf;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'prompt_keys_test.dart' show read;

void main() {
  group('tester: rebound prompt editing boundaries', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      Future<(TextAreaController, List<String>, List<String>)> mount(
        WidgetTester t,
        Map<String, Object?> keys, {
        String text = '',
      }) async {
        final c = TextAreaController(text: text)..cursor = endOf(text);
        final sent = <String>[], history = <String>[];
        await t.pumpWidget(
          Column(
            children: [
              PromptInput(
                controller: c,
                windowRows: size.height,
                keymap: read(keys),
                onSubmit: sent.add,
                onOlder: () => history.add('older'),
                onNewer: () => history.add('newer'),
              ),
            ],
          ),
          size: size,
        );
        return (c, sent, history);
      }

      testWidgets('moved submit retains backslash continuation $size', (
        t,
      ) async {
        final (c, sent, _) = await mount(t, {
          'enter': null,
          'ctrl+s': 'chat:submit',
        }, text: 'abc\\');
        await t.press('ctrl+s');
        expect(sent, isEmpty);
        expect(c.text, 'abc\n');
        await t.paste('界👩‍💻é');
        await t.press('ctrl+s');
        expect(sent, ['abc\n界👩‍💻é']);
        await t.press('enter');
        expect(sent, hasLength(1));
        expect(c.text, 'abc\n界👩‍💻é');
      });

      testWidgets('unbound Enter neither sends nor inserts a newline $size', (
        t,
      ) async {
        final (c, sent, _) = await mount(t, {'enter': null}, text: 'draft');
        await t.press('enter');
        expect(c.text, 'draft');
        expect(sent, isEmpty);
        await t.press('shift+enter');
        expect(c.text, 'draft\n');
      });

      testWidgets(
        'remapped newline edits at a grapheme boundary after resize $size',
        (t) async {
          final (c, sent, _) = await mount(t, {
            'x': 'chat:newline',
          }, text: '界👩‍💻é');
          await t.press('left');
          await t.resize(const Size(12, 8));
          await t.resize(size);
          await t.press('x');
          expect(c.text, '界👩‍💻\né');
          expect(sent, isEmpty);
        },
      );

      testWidgets(
        'history chord owns editing-key prefix without cutting $size',
        (t) async {
          final (c, sent, history) = await mount(t, {
            'ctrl+k p': 'history:previous',
          }, text: 'first\nsecond');
          await t.press('ctrl+a');
          await t.press('ctrl+k p');
          expect(history, ['older']);
          expect(c.text, 'first\nsecond');
          expect(sent, isEmpty);
          await t.pumpWidget(Text('removed'), size: size);
          await t.press('ctrl+k p');
          expect(history, ['older']);
        },
      );
    }
  });
}
