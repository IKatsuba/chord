import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: start page lifecycle boundaries', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets(
        'Unicode selection survives theme and tiny resize then settles once at $size',
        (t) async {
          final plain = ValueNotifier(false);
          final picks = <String>[];
          var cancellations = 0;
          final agents = [
            for (var i = 1; i <= 12; i++)
              ListedAgent(
                name: 'agent-$i',
                title: 'Agent 界👩‍💻e\u0301 $i',
                start: 'unused',
                from: AgentRunner.cli,
              ),
          ];
          try {
            await t.pumpWidget(
              ListenableBuilder(
                listenable: plain,
                builder: (_) => Theme(
                  data: plain.value ? ThemeData.plain() : ThemeData.light(),
                  child: StartPage(
                    version: 'test',
                    directory: '/workspace/界👩‍💻/e\u0301/project',
                    agents: agents,
                    preferred: 'agent-4',
                    onPicked: picks.add,
                    onCanceled: () => cancellations++,
                  ),
                ),
              ),
              size: size,
            );
            await t.press('down');
            plain.value = true;
            await t.pump();
            await t.resize(const Size(0, 0));
            await t.resize(const Size(1, 1));
            expect(picks, isEmpty);
            await t.resize(size);
            expect(t.screen, shows('Agent 界👩‍💻e\u0301 5'));
            await t.press('enter esc 9 ctrl+c');
            expect(picks, ['agent-5']);
            expect(cancellations, 0);
            expect(t.exitRequested, isTrue);
            await t.resize(
              size == const Size(80, 24)
                  ? const Size(120, 40)
                  : const Size(80, 24),
            );
            await t.press('enter 2 esc');
            expect(picks, ['agent-5']);
            expect(cancellations, 0);
          } finally {
            t.dispose();
            plain.dispose();
          }
        },
      );
    }
  });
}
