import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Launch launch({String agent = 'claude', String directory = '~/src/app'}) =>
    Launch(
      name: agent,
      agent: findAgent(agent)!,
      version: '0.0.1',
      directory: directory,
    );

void main() {
  test('a name only an agent command starts is shown as given', () {
    expect(
      windowLine(
        const Launch(
          name: 'my-agent',
          agent: null,
          agentCommand: 'my-agent --acp',
          version: '0.0.1',
          directory: '~/src/app',
        ),
      ),
      'chord v0.0.1 · my-agent · ~/src/app',
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at ${size.width}x${size.height}', () {
      testWidgets(
        'shows the version, the agent and the directory, then the keys',
        (t) async {
          await t.pumpWidget(StartWindow(launch: launch()), size: size);

          expect(t.screen.lines.take(2), [
            ' chord v0.0.1 · Claude Agent · ~/src/app',
            ' ctrl+c or ctrl+d to quit',
          ]);
          expect(t.screen.lines.skip(2).every((line) => line.isEmpty), isTrue);
        },
      );

      testWidgets('draws chord bold and the rest dim, as the original header', (
        t,
      ) async {
        await t.pumpWidget(StartWindow(launch: launch()), size: size);

        final first = t.screen.lines.first;
        for (var x = 1; x < first.length; x++) {
          final style = t.screen.styleAt(x, 0);
          expect(style.isBold, x <= 5, reason: 'cell $x');
          expect(style.isDim, x > 5, reason: 'cell $x');
        }
        for (var x = 1; x < t.screen.lines[1].length; x++) {
          expect(t.screen.styleAt(x, 1).isDim, isTrue, reason: 'cell $x');
        }
      });

      testWidgets('both keys are bound through Actions, described', (t) async {
        await t.pumpWidget(StartWindow(launch: launch()), size: size);

        expect(
          [
            for (final binding in t.focusManager.activeBindings)
              '${binding.chord}: ${binding.description}',
          ],
          ['ctrl+c: quit', 'ctrl+d: quit'],
        );
      });

      for (final key in ['ctrl+c', 'ctrl+d']) {
        testWidgets('$key quits at once', (t) async {
          await t.pumpWidget(StartWindow(launch: launch()), size: size);
          await t.press(key);

          expect(t.exitRequested, isTrue);
        });
      }

      testWidgets('a line too long for the window ends in …', (t) async {
        final directory = '/srv/${'deep/' * 30}app';
        await t.pumpWidget(
          StartWindow(
            launch: launch(agent: 'goose', directory: directory),
          ),
          size: size,
        );

        final line = t.screen.lines.first;
        expect(line, startsWith(' chord v0.0.1 · goose · /srv/deep/'));
        expect(line, endsWith('…'));
        expect(cellWidth(line), size.width - 1);
        expect(t.screen.lines[1], ' ctrl+c or ctrl+d to quit');
      });
    });
  }

  test('the line is the one decisions.md gives', () {
    expect(
      windowLine(launch(agent: 'codex', directory: '~')),
      'chord v0.0.1 · Codex · ~',
    );
  });

  group('tester: interim window boundaries', () {
    for (final size in const [Size(0, 0), Size(1, 1), Size(2, 1)]) {
      testWidgets('tiny ${size.width}x${size.height} remains quittable', (
        t,
      ) async {
        await t.pumpWidget(StartWindow(launch: launch()), size: size);
        expect(t.screen.lines, hasLength(size.height));
        await t.press('ctrl+d');
        expect(t.exitRequested, isTrue);
      });
    }

    testWidgets('resize clips and restores the full line between frames', (
      t,
    ) async {
      final directory = '/workspace/${'nested/' * 9}app';
      final descriptor = launch(directory: directory);
      await t.pumpWidget(
        StartWindow(launch: descriptor),
        size: const Size(120, 40),
      );
      expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.first, endsWith('…'));
      expect(t.screen.lines[1], ' $quitHint');
      await t.resize(const Size(120, 40));
      expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
      expect(t.screen.lines.skip(2).every((line) => line.isEmpty), isTrue);
    });

    for (final suffix in ['界', '😀', 'é', '界😀é']) {
      testWidgets('unicode directory $suffix fits exactly at the right edge', (
        t,
      ) async {
        final descriptor = launch(
          agent: 'goose',
          directory: '/workspace/$suffix',
        );
        final width = cellWidth(windowLine(descriptor)) + 2;
        await t.pumpWidget(
          StartWindow(launch: descriptor),
          size: Size(width, 4),
        );
        expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
        await t.resize(Size(width - 1, 4));
        expect(t.screen.lines.first, endsWith('…'));
        expect(cellWidth(t.screen.lines.first), lessThanOrEqualTo(width - 2));
        await t.resize(Size(width, 4));
        expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
      });
    }

    testWidgets(
      'unbound keys leave the window open and its contents unchanged',
      (t) async {
        await t.pumpWidget(StartWindow(launch: launch()));
        final before = t.screen.text;
        for (final key in [
          'escape',
          'enter',
          'tab',
          'up',
          'down',
          'ctrl+x',
          '?',
        ]) {
          await t.press(key);
          expect(t.exitRequested, isFalse, reason: key);
          expect(t.screen.text, before);
        }
        await t.press('ctrl+c');
        expect(t.exitRequested, isTrue);
      },
    );

    testWidgets(
      'removing and remounting the window removes its old quit bindings',
      (t) async {
        await t.pumpWidget(StartWindow(launch: launch()));
        await t.pumpWidget(Text('replacement'));
        expect(t.focusManager.activeBindings, isEmpty);
        await t.press('ctrl+d');
        expect(t.exitRequested, isFalse);
        await t.pumpWidget(StartWindow(launch: launch(agent: 'codex')));
        expect(t.screen, shows('Codex'));
        expect(t.focusManager.activeBindings, hasLength(2));
        await t.press('ctrl+d');
        expect(t.exitRequested, isTrue);
      },
    );
  });

  group('tester custom name window', () {
    testWidgets(
      'a custom grapheme name survives resize and keeps quit actions',
      (t) async {
        const descriptor = Launch(
          name: 'custom-界😀é',
          agent: null,
          agentCommand: 'missing --acp',
          version: '0.0.1',
          directory: '/workspace/app',
        );
        await t.pumpWidget(
          StartWindow(launch: descriptor),
          size: const Size(120, 40),
        );
        expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
        await t.resize(const Size(80, 24));
        expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
        await t.resize(const Size(1, 1));
        expect(t.focusManager.activeBindings, hasLength(2));
        await t.resize(const Size(120, 40));
        expect(t.screen.lines.first, ' ${windowLine(descriptor)}');
        await t.press('ctrl+d');
        expect(t.exitRequested, isTrue);
      },
    );
  });
}
