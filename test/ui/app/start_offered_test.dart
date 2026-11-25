// The offeredAgents setting on the start page: the original's
// tests/ui/app/start_layout_test.ts note cases and Start_test.tsx's
// offered-list cases.
import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/app/start_layout.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final _agents = [
  for (var at = 1; at <= 15; at++)
    ListedAgent(
      name: 'offered-$at',
      title: null,
      start: 'fixture',
      from: AgentRunner.settings,
    ),
];

String _flat(WidgetTester t) => t.screen.text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('tester: CTUI-29 offered agent lifecycle and keys', () {
    test(
      'a thousand repeated names preserve first-occurrence order and independent results',
      () {
        final names = [
          for (var i = 0; i < 1000; i++) ...['offered-9', '界😀é', 'offered-2'],
        ];
        final first = offeredFrom(_agents, names);
        expect(first.agents.map((a) => a.name), ['offered-9', 'offered-2']);
        expect(first.unknown, ['界😀é']);
        final second = offeredFrom(_agents, ['offered-1']);
        expect(second.agents.single.name, 'offered-1');
        expect(second.unknown, isEmpty);
        expect(first.unknown, ['界😀é']);
      },
    );

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final cancel in ['esc', 'ctrl+c']) {
        testWidgets(
          'unknown-only catalog ignores selection keys and cancels once with $cancel at $size',
          (t) async {
            final picks = <String>[];
            var cancelled = 0;
            await t.pumpWidget(
              StartPage(
                version: 'test',
                directory: '.',
                agents: _agents,
                offered: const ['界😀é', 'missing'],
                onPicked: picks.add,
                onCanceled: () => cancelled++,
              ),
              size: size,
            );
            for (final key in [
              'enter',
              '1',
              '9',
              'up',
              'down',
              'j',
              'k',
              'home',
              'end',
              'pageup',
              'pagedown',
            ]) {
              await t.press(key);
            }
            expect(picks, isEmpty);
            expect(t.exitRequested, isFalse);
            await t.press(cancel);
            expect(cancelled, 1);
            expect(t.exitRequested, isTrue);
            expect(picks, isEmpty);
          },
        );
      }
      testWidgets(
        'selection survives zero and one cell then accepts the intended row at $size',
        (t) async {
          final picks = <String>[];
          await t.pumpWidget(
            StartPage(
              version: 'test',
              directory: '.',
              agents: _agents,
              offered: const ['offered-9', '界😀é', 'offered-2'],
              preferred: 'offered-9',
              onPicked: picks.add,
            ),
            size: size,
          );
          await t.press('j');
          await t.resize(const Size(0, 0));
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(_flat(t), contains('❯ 2. offered-2'));
          expect(_flat(t), contains('Unknown in offeredAgents: 界😀é'));
          await t.press('k');
          await t.press('enter');
          expect(picks, ['offered-9']);
        },
      );
    }
  });
  group('unknownNote', () {
    test('every name that fits shows, whole and in order', () {
      expect(
        unknownNote(['cdex', 'codx'], 60),
        'Unknown in offeredAgents: cdex, codx',
      );
    });

    test('the rest is counted, with room kept for the count', () {
      const names = ['aaaa', 'bbbb', 'cccc', 'dddd'];
      const all = 'Unknown in offeredAgents: aaaa, bbbb, cccc, dddd';
      expect(unknownNote(names, all.length), all);
      expect(
        unknownNote(names, all.length - 1),
        'Unknown in offeredAgents: aaaa, bbbb, +2 more',
      );
      expect(
        unknownNote(names, 'Unknown in offeredAgents: aaaa, +3 more'.length),
        'Unknown in offeredAgents: aaaa, +3 more',
      );
    });

    test('at least one name shows, however narrow, for the row to cut', () {
      expect(
        unknownNote(['aaaa', 'bbbb'], 5),
        'Unknown in offeredAgents: aaaa, +1 more',
      );
      expect(unknownNote(['aaaa'], 5), 'Unknown in offeredAgents: aaaa');
    });
  });

  group('noteLayout', () {
    test('the original\'s cases', () {
      for (final (columns, rows, lines, hint, step, listRows, note, top) in [
        (120, 40, 3, 1, StartStep.full, 3, true, 9),
        (120, 40, 14, 1, StartStep.full, 14, true, 4),
        (80, 24, 3, 1, StartStep.compact, 3, true, 4),
        (80, 24, 11, 1, StartStep.compact, 11, true, 0),
        (80, 24, 12, 1, StartStep.compact, 12, false, 1),
        (59, 40, 3, 1, StartStep.compact, 3, true, 12),
        (39, 24, 3, 2, StartStep.line, 3, true, 6),
        (39, 12, 3, 2, StartStep.line, 3, false, 1),
        (30, 12, 3, 3, StartStep.line, 3, false, 0),
        (30, 8, 3, 3, StartStep.none, 1, false, 0),
      ]) {
        final page = noteLayout(
          columns: columns,
          rows: rows,
          lines: lines,
          hintRows: hint,
          noteRows: 2,
        );
        expect(
          (page.step, page.listRows, page.note, page.top),
          (step, listRows, note, top),
          reason: '${columns}x$rows, $lines lines',
        );
      }
    });

    test('a note never changes the step or costs a row of the list', () {
      for (final columns in [30, 39, 40, 59, 60, 80, 120]) {
        for (final rows in [5, 8, 12, 17, 18, 24, 31, 32, 40]) {
          for (final lines in [1, 3, 11, 12, 14, 15, 28]) {
            final without = startLayout(
              columns: columns,
              rows: rows,
              lines: lines,
              hintRows: 1,
            );
            final withNote = noteLayout(
              columns: columns,
              rows: rows,
              lines: lines,
              hintRows: 1,
              noteRows: 2,
            );
            expect(withNote.step, without.step);
            expect(withNote.listRows, without.listRows);
          }
        }
      }
    });
  });

  test('the setting picks its names in its order, each once, and counts '
      'the rest unknown', () {
    final picked = offeredFrom(_agents, [
      'unknown-first',
      'offered-7',
      'offered-2',
      'offered-7',
      'unknown-first',
      'typo',
    ]);
    expect(picked.agents.map((a) => a.name), ['offered-7', 'offered-2']);
    expect(picked.unknown, ['unknown-first', 'typo']);
    final missing = ListedAgent(
      name: 'gone',
      title: 'Gone',
      start: 'gone',
      from: AgentRunner.cli,
      found: false,
    );
    expect(offeredAgents([missing]), isEmpty);
    expect(offeredFrom([missing], ['gone']).agents, [missing]);
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    StartPage page(List<String> offered, List<String> picks) => StartPage(
      version: '0.65.0',
      directory: '/tmp/chord-qa',
      agents: _agents,
      offered: offered,
      preferred: 'outside-the-list',
      onPicked: picks.add,
    );

    testWidgets('one known row still waits for a choice, the unknown named '
        'under the hint, at $size', (t) async {
      final picks = <String>[];
      await t.pumpWidget(
        page([
          'unknown-first',
          'offered-7',
          'offered-7',
          'unknown-first',
        ], picks),
        size: size,
      );
      expect(_flat(t), contains('❯ 1. offered-7'));
      expect(_flat(t), isNot(contains('2.')));
      final hint = t.screen.lines.indexWhere((l) => l.contains('Esc to'));
      expect(t.screen.lines[hint + 1].trim(), '');
      expect(
        t.screen.lines[hint + 2].trim(),
        'Unknown in offeredAgents: unknown-first',
      );
      await t.press('2');
      expect(picks, isEmpty);
      await t.press('1');
      expect(picks, ['offered-7']);
    });

    testWidgets('a list naming no agent chord knows says so, with nothing to '
        'pick, at $size', (t) async {
      final picks = <String>[];
      await t.pumpWidget(page(['nope', 'typo'], picks), size: size);
      final at = t.screen.lines.indexWhere(
        (l) => l.contains('No agents available'),
      );
      expect(at, greaterThan(0));
      expect(
        t.screen.lines[at + 1].trim(),
        'offeredAgents in settings.json names no agent chord knows.',
      );
      expect(_flat(t), contains('Esc to cancel'));
      expect(_flat(t), isNot(contains('Unknown in offeredAgents')));
    });
  }

  testWidgets('the note gives way to rows and comes back as the window '
      'grows', (t) async {
    final picks = <String>[];
    await t.pumpWidget(
      StartPage(
        version: '0.65.0',
        directory: '/tmp/chord-qa',
        agents: _agents,
        offered: const ['offered-9', 'offered-2', 'typo'],
        onPicked: picks.add,
      ),
      size: const Size(80, 24),
    );
    await t.press('j');
    expect(_flat(t), contains('❯ 2. offered-2'));
    expect(_flat(t), contains('Unknown in offeredAgents: typo'));
    await t.resize(const Size(30, 8));
    expect(_flat(t), isNot(contains('Unknown in offeredAgents')));
    await t.resize(const Size(80, 24));
    expect(_flat(t), contains('❯ 2. offered-2'));
    expect(_flat(t), contains('Unknown in offeredAgents: typo'));
  });
  testWidgets('a narrow page cuts the sentence and the note in the middle, '
      'as the original\'s truncate does', (t) async {
    final picks = <String>[];
    StartPage at(List<String> offered) => StartPage(
      version: '0.65.0',
      directory: '/tmp/chord-qa',
      agents: _agents,
      offered: offered,
      onPicked: picks.add,
    );
    await t.pumpWidget(at(['nope']), size: const Size(40, 24));
    expect(
      t.screen.lines.map((l) => l.trim()),
      contains('offeredAgents in...gent chord knows.'),
    );
    await t.pumpWidget(
      at(['offered-1', 'a-very-long-unknown-name', 'another-long-one']),
      size: const Size(40, 24),
    );
    final note = t.screen.lines
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('Unknown in'));
    expect(note, contains('...'));
    expect(note, endsWith('more'));
  });
}
