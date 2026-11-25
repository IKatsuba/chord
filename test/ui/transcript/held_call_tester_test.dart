import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: held call visible and selection agreement', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      for (final cycle in [false, true]) {
        testWidgets(
          'matching permission alone retains Waiting, cycle=$cycle at $size',
          (t) async {
            final controller = ScrollController();
            addTearDown(controller.dispose);
            final entry = model.ToolEntry(
              'turn',
              const model.ToolCall(
                'write',
                title: 'Write notes/build.md',
                status: 'pending',
              ),
            );
            final turn = ValueNotifier<model.TurnState>(
              model.AwaitingPermission(
                'turn',
                20,
                const [model.PermissionWait('p', toolCallId: 'write')],
                between: true,
                cycle: cycle,
                cycleSince: cycle ? 10 : null,
              ),
            );
            addTearDown(turn.dispose);
            final sources = TranscriptSources(Object());
            model.Transcript current() =>
                model.Transcript(entries: [entry], turn: turn.value);
            await t.pumpWidget(
              ListenableBuilder(
                listenable: turn,
                builder: (_) =>
                    Transcript(transcript: current(), controller: controller),
              ),
              size: size,
            );
            Future<String> sourceText() async {
              sources.retain([entry]);
              final sourceTester = WidgetTester();
              try {
                await sourceTester.pumpWidget(
                  Column(
                    children: [
                      for (final child
                          in sources
                              .entryAt(current(), 0, width: size.width)
                              .children)
                        Text.fromSelectionSource(child),
                    ],
                  ),
                  size: size,
                );
                return sourceTester.screen.text;
              } finally {
                sourceTester.dispose();
              }
            }

            expect(t.screen, shows('Waiting…'));
            expect(await sourceText(), contains('Waiting…'));
            await t.resize(Size.zero);
            await t.resize(const Size(1, 1));
            await t.resize(size);
            expect(t.screen, shows('Waiting…'));
            turn.value = model.AwaitingPermission(
              'turn',
              20,
              const [model.PermissionWait('other', toolCallId: 'other-call')],
              between: true,
              cycle: cycle,
              cycleSince: cycle ? 10 : null,
            );
            await t.pump();
            expect(t.screen, isNot(shows('Waiting…')));
            expect(await sourceText(), isNot(contains('Waiting…')));
            turn.value = const model.Idle();
            await t.pump();
            expect(t.screen, isNot(shows('Waiting…')));
            expect(await sourceText(), isNot(contains('Waiting…')));
          },
        );
      }
    }
  });
}
