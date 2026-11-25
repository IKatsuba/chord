import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/message.dart';
import 'package:chord/ui/transcript/tools/tools.dart' show Tone;
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'package:chord/ui/transcript/agent_colours.dart';

/// A message that came in, as the conversation transcribes it.
UserEntry _came(MessageFrom from, [String text = 'Fixed.']) =>
    UserEntry('t', text, from: from);

List<String> _rows(WidgetTester t) => [
  for (final row in t.screen.lines) row.trimRight(),
];

void main() {
  test('a team part draws as one line: whose instructions, for whom, and '
      'how long', () {
    expect(
      teamPartLine(
        (team: 'bugfix', member: 'tester', text: 'a\nb\nc'),
        false,
        'ctrl+o',
      ),
      "bugfix's instructions for tester · 3 lines (ctrl+o to expand)",
    );
    expect(
      teamPartLine((team: 'bugfix', member: null, text: 'a'), true, 'ctrl+o'),
      "bugfix's instructions for the lead · 1 line",
    );
    expect(
      teamPartLine((team: 'bugfix', member: null, text: 'a'), false, null),
      "bugfix's instructions for the lead · 1 line",
    );
  });
  _testerMessageEdges();
  _monitorTests();
  _testerMonitorEdges();
  test(
    'self-started notice follows original cli end cutoff including boundary spaces',
    () {
      expect(selfStartedLine(0), '');
      expect(selfStartedLine(1), '…');
      expect(selfStartedLine(5), 'Inte…');
      expect(selfStartedLine(25), 'Interrupted · the agent …');
      expect(selfStartedLine(28), 'Interrupted · the agent sta…');
      expect(
        selfStartedLine(73),
        'Interrupted · the agent started this on its own; your message goes as th…',
      );
      expect(selfStartedLine(115), SelfStartedEntry.message);
      expect(selfStartedLine(120), SelfStartedEntry.message);
    },
  );

  test("a turn started on its own with another's message names its sender", () {
    expect(
      selfStartedLine(120, const MessageFrom('main', reachable: true)),
      "Interrupted · the agent started this on its own; @main's message goes "
      'as the next turn',
    );
    expect(
      selfStartedLine(120, const MessageFrom('chord')),
      "Interrupted · the agent started this on its own; chord's message goes "
      'as the next turn',
    );
  });

  test('@ goes on a sender send_message reaches, told by who sent it, not '
      'its name', () {
    expect(
      queuedMessage(
        const MessageFrom('docs', runtime: 'claude', reachable: true),
        'Hi',
      ),
      (header: 'from @docs · claude: ', text: 'Hi'),
    );
    expect(queuedMessage(const MessageFrom('Fix it', runtime: 'codex'), 'Hi'), (
      header: 'from Fix it · codex: ',
      text: 'Hi',
    ));
  });

  test('a held message says what it waits on; a long one its first line', () {
    const main = MessageFrom('main', reachable: true);
    const text = 'Then the docs, once the tests pass.';
    expect(
      queuedMessage(main, text, QueueHold.calls).header,
      'from @main · after the running calls: ',
    );
    expect(
      queuedMessage(main, text, QueueHold.answer).header,
      'from @main · after your answer: ',
    );
    expect(queuedMessage(main, 'one\ntwo').text, 'one …');
  });

  test("arrows: a failed report's in error, chord's own dim, a sent one's "
      'by its call', () {
    expect(
      inArrow(const MessageFrom('Fix', note: MessageNote.failed)),
      ArrowTone.failed,
    );
    expect(inArrow(const MessageFrom('chord')), ArrowTone.dim);
    expect(
      inArrow(const MessageFrom('Fix', note: MessageNote.report)),
      ArrowTone.plain,
    );
    expect(outArrow(Tone.pending), ArrowTone.dim);
    expect(outArrow(Tone.running), ArrowTone.dim);
    expect(outArrow(Tone.failed), ArrowTone.failed);
    expect(outArrow(Tone.done), ArrowTone.plain);
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      Future<void> draw(WidgetTester t, Entry entry) => t.pumpWidget(
        // Inset as the window's transcript body is, so rows read as the
        // original's captures do.
        Theme(
          data: themeData('dark'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: TranscriptEntry(entry),
          ),
        ),
        size: size,
      );

      testWidgets('a message that came in is ← from, its sender and what it '
          'said', (t) async {
        await draw(
          t,
          _came(
            const MessageFrom('parser', runtime: 'fake', reachable: true),
            'Ran bun dev test tests/parse: 2 failures, both in '
            'tests/parse/printer_test.ts.',
          ),
        );
        expect(_rows(t)[1], ' ← from @parser · fake');
        if (size.width == 120) {
          expect(
            _rows(t)[2],
            '   ⎿  Ran bun dev test tests/parse: 2 failures, both in '
            'tests/parse/printer_test.ts.',
          );
        }
        await draw(
          t,
          _came(
            const MessageFrom(
              'Fix the tokenizer',
              runtime: 'fake',
              note: MessageNote.report,
            ),
          ),
        );
        expect(_rows(t)[1], ' ← from Fix the tokenizer · fake · report');
        await draw(t, _came(const MessageFrom('chord')));
        expect(_rows(t)[1], ' ← from chord');
      });

      testWidgets('the captured report wraps whole, no fold', (t) async {
        const text =
            'The tokenizer dropped a closing quote when a string ended the '
            'line. Fixed in src/parse/tokenize.ts, with two cases added to '
            'tests/parse/tokenize_test.ts. bun dev test passes.';
        await draw(
          t,
          _came(
            const MessageFrom(
              'Fix the tokenizer',
              runtime: 'fake',
              note: MessageNote.report,
            ),
            text,
          ),
        );
        final rows = _rows(t);
        final body = rows.skip(2).takeWhile((row) => row.isNotEmpty).toList();
        if (size.width == 120) {
          expect(body, [
            '   ⎿  The tokenizer dropped a closing quote when a string ended '
                'the line. Fixed in src/parse/tokenize.ts, with two',
            '      cases added to tests/parse/tokenize_test.ts. bun dev test '
                'passes.',
          ]);
        }
        expect(
          body.map((row) => row.substring(6)).join().replaceAll(' ', ''),
          text.replaceAll(' ', ''),
        );
        expect(t.screen.text, isNot(contains('to expand')));
      });

      testWidgets('← as the text is, from dim, the sender bold, the rest '
          'dim, the body dim', (t) async {
        await draw(
          t,
          _came(const MessageFrom('parser', runtime: 'fake', reachable: true)),
        );
        final s = t.screen;
        expect((s.styleAt(1, 1).isDim, s.styleAt(1, 1).isBold), (false, false));
        expect(s.styleAt(1, 1).fg, isNull);
        for (var x = 3; x < 8; x++) {
          expect(s.styleAt(x, 1).isDim, isTrue, reason: 'from, cell $x');
        }
        for (var x = 8; x < 15; x++) {
          expect(s.styleAt(x, 1).isBold, isTrue, reason: '@parser, cell $x');
          expect(s.styleAt(x, 1).isDim, isFalse, reason: '@parser, cell $x');
        }
        for (var x = 15; x < 22; x++) {
          expect(s.styleAt(x, 1).isDim, isTrue, reason: 'rest, cell $x');
        }
        expect(s.styleAt(6, 2).isDim, isTrue);
      });

      testWidgets("a failed report's arrow and body are in the error colour, "
          "chord's own arrow dim", (t) async {
        final theme = themeData('dark');
        await draw(
          t,
          _came(
            const MessageFrom(
              'Fix the tokenizer',
              runtime: 'codex',
              note: MessageNote.failed,
            ),
            'Stopped: the agent exited before it reported.',
          ),
        );
        expect(_rows(t)[1], ' ← from Fix the tokenizer · codex · failed');
        expect(t.screen.styleAt(1, 1).fg, theme.error.fg);
        expect(t.screen.styleAt(6, 2).fg, theme.error.fg);
        expect(t.screen.styleAt(6, 2).isDim, isFalse);
        await draw(t, _came(const MessageFrom('chord')));
        expect(t.screen.styleAt(1, 1).isDim, isTrue);
        expect(t.screen.styleAt(8, 1).isBold, isTrue);
      });

      testWidgets("the self-started close names another's message", (t) async {
        await draw(
          t,
          const SelfStartedEntry(
            't',
            from: MessageFrom('main', reachable: true),
          ),
        );
        expect(
          t.screen.text,
          contains("Interrupted · the agent started this on its own; @main's"),
        );
      });
    });
  }
}

void _testerMessageEdges() {
  group('CTUI-35 tester: message repaint and cell edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'recipient colours change and disappear without changing words at $size',
        (t) async {
          final colours = ValueNotifier<Map<String, Color>>({
            'docs': const RgbColor(180, 40, 20),
          });
          addTearDown(colours.dispose);
          await t.pumpWidget(
            Theme(
              data: themeData('dark'),
              child: ListenableBuilder(
                listenable: colours,
                builder: (_) => AgentColours(
                  colours: colours.value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: TranscriptEntry(
                      _came(
                        const MessageFrom('docs', reachable: true),
                        'Unchanged body.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            size: size,
          );
          final row = t.screen.lines.indexWhere(
            (l) => l.contains('← from @docs'),
          );
          expect(row, isNonNegative);
          expect(t.screen.styleAt(1, row).fg, colours.value['docs']);
          colours.value = {'docs': const RgbColor(20, 40, 180)};
          await t.pump();
          expect(t.screen.styleAt(1, row).fg, colours.value['docs']);
          expect(t.screen.styleAt(8, row).fg, colours.value['docs']);
          colours.value = {};
          await t.pump();
          expect(t.screen.styleAt(1, row).fg, isNull);
          expect(t.screen.styleAt(8, row).fg, isNull);
          expect(t.screen, shows('Unchanged body.'));
        },
      );

      testWidgets(
        'wide graphemes and escapes survive tiny rooms then resize at $size',
        (t) async {
          const text =
              '界🙂e\u0301 \x1b[31mred\x1b[0m\n\n> quoted\n\n    indented code';
          final widget = Theme(
            data: themeData('dark'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TranscriptEntry(
                _came(const MessageFrom('界🙂e\u0301', reachable: true), text),
              ),
            ),
          );
          for (final small in [
            const Size(0, 0),
            const Size(1, 1),
            const Size(2, 1),
            const Size(12, 24),
          ]) {
            await t.pumpWidget(widget, size: small);
            expect(t.screen.text, isNot(contains('\x1b')));
          }
          await t.resize(size);
          await t.pump();
          expect(t.screen, shows('red'));
          expect(t.screen, shows('quoted'));
          expect(t.screen, shows('indented code'));
          expect(t.screen.text, isNot(contains('\x1b')));
        },
      );
    }
  });
}

/// A monitor's event, as the conversation transcribes it.
UserEntry _event(
  String text, {
  MonitorEnd? end,
  String name = 'dev server errors',
}) => UserEntry(
  't',
  text,
  from: MessageFrom(name, monitor: (id: 'm1', end: end)),
);

void _monitorTests() {
  test("a monitor's end colours its arrow by how it ended", () {
    ArrowTone arrow(MonitorEnd? end) =>
        inArrow(MessageFrom('ci', monitor: (id: 'm1', end: end)));
    expect(arrow(null), ArrowTone.plain);
    expect(arrow(const MonitorExited(0)), ArrowTone.plain);
    expect(arrow(const MonitorExited(1)), ArrowTone.failed);
    expect(arrow(const MonitorKilled('SIGKILL')), ArrowTone.failed);
    expect(arrow(const MonitorFlooded(FloodBy.lines)), ArrowTone.failed);
    expect(arrow(const MonitorTimedOut(600000)), ArrowTone.dim);
    expect(arrow(const MonitorStopped()), ArrowTone.dim);
  });

  test('a long line of an event wraps after its own indent, with no space '
      'left at the break', () {
    expect(
      monitorMessage(
        'ERROR one two three\n    at four five six',
        ended: false,
        expanded: false,
        width: 14,
      ).lines,
      ['ERROR one two', 'three', '    at four', 'five six'],
    );
    expect(
      monitorMessage(
        'The person stopped it after 4s.',
        ended: true,
        expanded: false,
        width: 76,
      ),
      (
        lines: const <String>[],
        hidden: 0,
        sentence: 'The person stopped it after 4s.',
      ),
    );
    expect(
      queuedMessage(
        const MessageFrom('dev server errors', monitor: (id: 'm1', end: null)),
        'WARN',
      ),
      (header: 'from dev server errors · monitor: ', text: 'WARN'),
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('a monitor at $size', () {
      Future<void> draw(WidgetTester t, Entry entry, {bool expanded = false}) =>
          t.pumpWidget(
            Theme(
              data: themeData('dark'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: TranscriptEntry(entry, expanded: expanded),
              ),
            ),
            size: size,
          );

      testWidgets("an event is ← from its description · monitor, its lines as "
          'printed, not markdown', (t) async {
        await draw(t, _event('a *b* _c_\n    at x (y.ts:1:2)'));
        expect(_rows(t).sublist(1, 4), [
          ' ← from dev server errors · monitor',
          '   ⎿  a *b* _c_',
          '          at x (y.ts:1:2)',
        ]);
      });

      testWidgets("an end says it in the header, its lines first and chord's "
          'sentence last, never folded', (t) async {
        final lines = [for (var i = 1; i <= 9; i++) 'line $i'];
        await draw(
          t,
          _event(
            [...lines, 'Exited with code 1 after 6m 3s.'].join('\n'),
            end: const MonitorExited(1),
          ),
        );
        expect(_rows(t).sublist(1, 11), [
          ' ← from dev server errors · monitor · exit code 1',
          '   ⎿  line 1',
          '      line 2',
          '      line 3',
          '      line 4',
          '      line 5',
          '      line 6',
          '      … +3 lines (ctrl+o to expand)',
          '      Exited with code 1 after 6m 3s.',
          '',
        ]);
        await draw(
          t,
          _event(
            [...lines, 'Exited with code 1 after 6m 3s.'].join('\n'),
            end: const MonitorExited(1),
          ),
          expanded: true,
        );
        expect(_rows(t)[10], '      line 9');
        expect(_rows(t)[11], '      Exited with code 1 after 6m 3s.');
      });

      testWidgets("a stop with nothing unsent is chord's sentence alone, dim, "
          'its arrow dim', (t) async {
        await draw(
          t,
          _event(
            'The person stopped it after 4s.',
            end: const MonitorStopped(),
          ),
        );
        expect(_rows(t).sublist(1, 3), [
          ' ← from dev server errors · monitor · stopped',
          '   ⎿  The person stopped it after 4s.',
        ]);
        expect(t.screen.styleAt(1, 1).isDim, isTrue);
        expect(t.screen.styleAt(6, 2).isDim, isTrue);
      });

      testWidgets("an event's lines select as drawn; the fold and chord's "
          'sentence do not', (t) async {
        final entry = _event(
          [
            for (var i = 1; i <= 8; i++) 'line $i',
            'Exited with code 1 after 1s.',
          ].join('\n'),
          end: const MonitorExited(1),
        );
        final source = entrySelectionSource(
          entry,
          id: 'e',
          revision: 0,
          width: size.width,
        );
        final selection = SelectionController();
        addTearDown(selection.dispose);
        await t.pumpWidget(
          Theme(
            data: themeData('dark'),
            child: SelectionArea(
              controller: selection,
              selectionStyle: const Style(inverse: true),
              child: TranscriptEntry(entry, selectionSource: source),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.skip(1).take(10).map((l) => l.trimRight()), [
          '← from dev server errors · monitor · exit code 1',
          '  ⎿  line 1',
          '     line 2',
          '     line 3',
          '     line 4',
          '     line 5',
          '     line 6',
          '     … +2 lines (ctrl+o to expand)',
          '     Exited with code 1 after 1s.',
          '',
        ]);
        for (final (kind, at) in [
          (MouseEventKind.press, const Offset(5, 2)),
          (MouseEventKind.move, const Offset(40, 9)),
          (MouseEventKind.release, const Offset(40, 9)),
        ]) {
          t.host.handleMouse(
            MouseEvent(kind, position: at, button: MouseButton.primary),
          );
        }
        expect(
          selection.snapshot()!.text,
          'line 1\nline 2\nline 3\nline 4\nline 5\nline 6',
        );
      });

      testWidgets("an event that failed draws its arrow in the error "
          'colour', (t) async {
        await draw(
          t,
          _event(
            'boom\nKilled by SIGKILL after 1s.',
            end: const MonitorKilled('SIGKILL'),
          ),
        );
        expect(t.screen.styleAt(1, 1).fg, themeData('dark').error.fg);
      });
    });
  }
}

void _testerMonitorEdges() {
  group('CTUI-36 tester: monitor message boundaries', () {
    test('a wrapped end sentence remains outside the six-line fold', () {
      final text = [
        for (var i = 0; i < 9; i++) 'log $i',
        'Exited with code 127 after 1s.',
      ].join('\n');
      for (final width in [1, 8, 75, 115]) {
        final folded = monitorMessage(
          text,
          ended: true,
          expanded: false,
          width: width,
        );
        final full = monitorMessage(
          text,
          ended: true,
          expanded: true,
          width: width,
        );
        expect(folded.sentence, full.sentence);
        expect(folded.sentence, isNotEmpty);
        expect(folded.hidden, isPositive);
        expect(full.hidden, 0);
        expect(folded.lines.length, lessThanOrEqualTo(messageLines));
      }
    });

    test('blank trailing log rows do not inflate the fold', () {
      final event = monitorMessage(
        'a\n\n\n',
        ended: false,
        expanded: false,
        width: 20,
      );
      expect(event.lines, ['a']);
      expect(event.hidden, 0);
      expect(event.sentence, isNull);
      final end = monitorMessage(
        'a\n\n\nStopped.',
        ended: true,
        expanded: false,
        width: 20,
      );
      expect(end.lines, ['a']);
      expect(end.hidden, 0);
      expect(end.sentence, 'Stopped.');
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'literal Unicode log survives tiny rooms and resize at $size',
        (t) async {
          const text = '界🙂e\u0301 *literal* _log_\n    at 界🙂e\u0301';
          final widget = Theme(
            data: themeData('dark'),
            child: TranscriptEntry(_event(text, name: '界🙂e\u0301')),
          );
          for (final small in const [
            Size(0, 0),
            Size(1, 1),
            Size(2, 1),
            Size(12, 24),
          ]) {
            await t.pumpWidget(widget, size: small);
            expect(t.screen.text, isNot(contains('\uFFFD')));
          }
          await t.resize(size);
          await t.pump();
          expect(t.screen.text, contains('界🙂e\u0301 *literal* _log_'));
          expect(t.screen.text, contains('    at 界🙂e\u0301'));
          await t.pumpWidget(Text('removed'), size: size);
          await t.pump(const Duration(seconds: 1));
          expect(t.screen, shows('removed'));
        },
      );
    }
  });
}
