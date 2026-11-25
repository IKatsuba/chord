import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/plan/plan.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const PlanFixture());

/// A live and interrupted checklist above the prompt, toggled with ctrl+t.
class PlanFixture extends StatefulWidget {
  const PlanFixture({super.key});
  @override
  State<PlanFixture> createState() => _PlanFixtureState();
}

class _PlanFixtureState extends State<PlanFixture> {
  final _draft = TextAreaController();
  var _running = true;
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
      Binding(
        'ctrl+t',
        'Toggle working state',
        () => setState(() => _running = !_running),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          const Expanded(child: SizedBox()),
          if (_running) Text(' ››› Working…'),
          Plan(
            plan: [
              for (final (status, content) in [
                ('completed', 'Read the code'),
                ('in_progress', 'Write the change'),
                ('pending', 'Run the tests'),
              ])
                acp.PlanEntry.fromJson({
                  'content': content,
                  'priority': 'medium',
                  'status': status,
                }),
            ],
            limit: 6,
            running: _running,
          ),
          PromptInput(
            key: const ValueKey('prompt-input'),
            controller: _draft,
            windowRows: constraints.maxHeight,
            onSubmit: (_) => _draft.clear(),
            onOlder: () {},
            onNewer: () {},
          ),
        ],
      ),
    ),
  );
}
