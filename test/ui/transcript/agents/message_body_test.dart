// A message between the agent and a subagent draws its words as the
// original's MessageBody does: Markdown, dim, its quotes read as the rest of
// it, a code block with its copy; a launch's prompt folds after six rows,
// its code then without controls, and opens whole under ctrl+o.
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../app/code_pick_window_test.dart' show clickAt, pressBounded;
import '../../app/selection_window_test.dart';

model.AgentMessageEntry _message(String text, {bool launch = false}) =>
    model.AgentMessageEntry(
      't',
      'm1',
      toSubagent: launch,
      agentId: 'a',
      title: 'layer',
      text: text,
      launch: launch,
    );

Future<List<String>> _window(
  WidgetTester t,
  Size size,
  List<model.Entry> entries,
) async {
  final connection = selectionConnection(appended([], entries));
  addTearDown(connection.close);
  final writes = <String>[];
  await t.pumpWidget(
    TranscriptWindow(
      launch: selectionLaunch,
      connection: connection,
      copyOnSelect: false,
      copy: (text, _) {
        writes.add(text);
        return const copy.CopyResult.sent();
      },
    ),
    size: size,
  );
  return writes;
}

void main() {
  test("a message and a subagent's work are revised with their entry", () {
    // Their entry revised for something else, the same words make no new
    // nested source of the same revision (the window crashed on it).
    final message = _message('Run this:\n\n```sh\nbun test\n```', launch: true);
    final agent = model.SubagentEntry(
      't',
      model.Subagent(
        'a',
        title: 'layer',
        entries: [model.AssistantEntry('t', TextRun.empty.plus('Found it.'))],
      ),
    );
    final entries = appended([], [message, agent]);
    final cache = TranscriptSources(Object())..retain(entries);
    final transcript = model.Transcript(entries: entries);
    for (final index in [0, 1]) {
      final first = cache.entryAt(transcript, index, width: 80, expanded: true);
      final working = cache.entryAt(
        model.Transcript(entries: entries, turn: const model.Working('t', 0)),
        index,
        width: 80,
        expanded: true,
      );
      expect(working.id, first.id);
    }
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a message body is dim Markdown, its quote plain text and '
        'its code block copied by its button $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _message(
          'The **layer** is in `render.dart`.\n\n'
          '> Quoted from the notes.\n\n'
          '```sh\nbun test\n```',
        ),
      ]);
      final text = t.screen.text;
      expect(text, contains('⎿  The layer is in render.dart.'));
      expect(text, isNot(contains('**')));
      expect(text, contains('     Quoted from the notes.'));
      expect(text, isNot(contains('│ Quoted')));
      final bold = cellOf(t, 'layer is');
      expect(t.screen.styleAt(bold.x, bold.y).isBold, isTrue);
      expect(t.screen.styleAt(bold.x, bold.y).isDim, isTrue);
      final quote = cellOf(t, 'Quoted from');
      expect(t.screen.styleAt(quote.x, quote.y).isItalic, isFalse);
      expect(t.screen.styleAt(quote.x, quote.y).isDim, isTrue);
      await clickAt(t, cellOf(t, '[copy]'));
      expect(writes, ['bun test']);
      await select(t, 'Quoted from the notes.');
      await t.press('ctrl+shift+c');
      expect(writes.last, 'Quoted from the notes.');
    });

    testWidgets('a launch folds after six rows with no code controls, and '
        'opens whole under ctrl+o $size', (t) async {
      final lines = [for (var i = 1; i <= 8; i++) 'Step $i.'];
      await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _message('${lines.join('\n\n')}\n\n```sh\nbun test\n```', launch: true),
      ]);
      final folded = t.screen.text;
      expect(folded, contains('Step 3.'));
      expect(folded, isNot(contains('Step 4.')));
      // Eight steps and the code box, a blank between each, are nineteen
      // rows; six are shown.
      expect(folded, contains('… +13 lines (ctrl+o to expand)'));
      expect(folded, isNot(contains('[copy]')));
      await t.press('ctrl+o');
      expect(t.screen.text, contains('Step 8.'));
      expect(t.screen.text, contains('[copy]'));
    });

    testWidgets('a folded launch\'s code, drawn in its first rows, is no '
        'pick, copy or run until ctrl+o opens it $size', (t) async {
      final writes = await _window(t, size, [
        const model.UserEntry('t', 'look'),
        _message(
          'Run this first.\n\n```sh\nbun test\n```\n\n'
          '${[for (var i = 1; i <= 8; i++) 'Step $i.'].join('\n\n')}',
          launch: true,
        ),
      ]);
      expect(t.screen.text, contains('bun test'));
      expect(t.screen.text, contains('… +'));
      await pressBounded(t, 'ctrl+x b');
      expect(t.screen.text, contains('No code block to pick'));
      await pressBounded(t, 'c');
      await pressBounded(t, 'r');
      expect(writes, isEmpty);
      // Nor is it run: the prompt takes nothing.
      expect(t.screen.text, isNot(contains('! bun test')));
      // Its words still select by drag.
      await select(t, 'Run this first.');
      await t.press('ctrl+shift+c');
      expect(writes, ['Run this first.']);
      await t.press('ctrl+o');
      await pressBounded(t, 'ctrl+x b');
      expect(t.screen.text, isNot(contains('No code block to pick')));
      await pressBounded(t, 'c');
      expect(writes.last, 'bun test');
    });
  }
}
