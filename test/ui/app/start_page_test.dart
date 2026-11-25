import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/app/start_layout.dart';
import 'package:chord/ui/header/mark_widget.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<ListedAgent> agents(int count) => [
  for (var i = 0; i < count; i++)
    ListedAgent(
      name: i == 0
          ? 'claude'
          : i == 1
          ? 'codex'
          : 'agent-$i',
      title: i == 0
          ? 'Claude'
          : i == 1
          ? 'Codex'
          : 'Agent $i',
      start: 'unused',
      from: AgentRunner.cli,
      found: i == 2 ? false : true,
    ),
];

StartPage page(
  List<String> picks, {
  int count = 3,
  void Function()? canceled,
}) => StartPage(
  version: '0.0.1',
  directory: '/workspace/packages/terminal/interfaces/example/project',
  agents: agents(count),
  onPicked: picks.add,
  onCanceled: canceled,
);

void main() {
  for (final (size, step) in [
    (const Size(120, 40), StartStep.full),
    (const Size(80, 24), StartStep.compact),
    (const Size(39, 14), StartStep.line),
    (const Size(30, 8), StartStep.none),
  ]) {
    testWidgets('start page $step draws original content at $size', (t) async {
      final picks = <String>[];
      await t.pumpWidget(page(picks), size: size);
      expect(t.screen, shows('Select agent'));
      expect(t.screen, shows('claude'));
      expect(
        t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
        contains('Esc to cancel'),
      );
      expect(
        t.screen,
        step == StartStep.full ? shows(tagline) : isNot(shows(tagline)),
      );
      expect(
        t.screen,
        step == StartStep.none ? isNot(shows('v0.0.1')) : shows('v0.0.1'),
      );
      if (step == StartStep.line) expect(t.screen, shows('chord'));
      await t.press('2');
      expect(picks, ['codex']);
      expect(t.exitRequested, isTrue);
    });
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'agent picker clamps arrows and j k and keeps highlight across art steps at $size',
      (t) async {
        final picks = <String>[];
        await t.pumpWidget(page(picks), size: size);
        await t.press('up k down');
        await t.resize(const Size(39, 14));
        await t.resize(const Size(30, 8));
        await t.resize(size);
        await t.press('enter');
        expect(picks, ['codex']);
      },
    );
    for (final key in ['esc', 'ctrl+c']) {
      testWidgets('$key cancels the empty page cleanly at $size', (t) async {
        var canceled = false;
        await t.pumpWidget(
          page([], count: 0, canceled: () => canceled = true),
          size: size,
        );
        expect(t.screen, shows('No agents available'));
        expect(t.screen, isNot(shows('↑↓ or j/k')));
        await t.press(key);
        expect(canceled, isTrue);
        expect(t.exitRequested, isTrue);
      });
    }
    testWidgets(
      'preferred fourth keeps preceding rows and ignores scroll keys at $size',
      (t) async {
        final picks = <String>[];
        await t.pumpWidget(
          StartPage(
            version: '0.0.1',
            directory: '.',
            agents: agents(29),
            preferred: 'agent-3',
            onPicked: picks.add,
          ),
          size: size,
        );
        expect(t.screen, shows('claude'));
        expect(t.screen, shows('codex'));
        await t.resize(const Size(120, 40));
        await t.resize(const Size(80, 24));
        expect(t.screen, shows('claude'));
        expect(t.screen, shows('codex'));
        final initial = t.screen.lines;
        await t.press('end home pageup pagedown');
        expect(t.screen.lines, initial);
        for (var i = 0; i < 30; i++) {
          await t.press('down');
        }
        expect(t.screen, shows('agent-28'));
        final visible = t.screen.lines
            .where((line) => RegExp(r'\d+\.\s+').hasMatch(line))
            .length;
        expect(t.screen, shows('… +${29 - visible} more'));
        final last = t.screen.lines;
        await t.press('end home pageup pagedown');
        expect(t.screen.lines, last);
        await t.press('enter');
        expect(picks, ['agent-28']);
      },
    );
    testWidgets(
      'long catalog keeps row cap and more count reachable at $size',
      (t) async {
        final picks = <String>[];
        await t.pumpWidget(page(picks, count: 28), size: size);
        expect(t.screen, shows('more'));
        expect(t.screen, shows('not on PATH'));
        for (var i = 0; i < 30; i++) {
          await t.press('down');
        }
        expect(t.screen, shows('agent-27'));
        await t.press('j enter');
        expect(picks, ['agent-27']);
      },
    );
  }
  testWidgets(
    'plain Mark retains the original half-cell shape without explicit colours',
    (t) async {
      await t.pumpWidget(
        Theme(data: ThemeData.plain(), child: const Mark()),
        size: const Size(80, 24),
      );
      expect(t.screen.lines.take(4), ['█▄', '▀██▄', '▄██▀', '█▀']);
      expect(t.screen.styleAt(0, 0).fg, isNull);
      expect(t.screen.styleAt(0, 0).bg, isNull);
    },
  );
}
