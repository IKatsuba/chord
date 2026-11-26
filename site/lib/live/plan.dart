import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/plan/plan.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';

/// The plan the fixture shows: one step done, one under way, one to come.
final livePlanEntries = [
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
];

/// chord's plan checklist above the prompt, live, as `tool/plan.dart` has
/// it: ctrl+t stops and starts the work it shows.
class LivePlan extends StatefulWidget {
  /// The plan fixture.
  const LivePlan({super.key});

  @override
  State<LivePlan> createState() => _LivePlanState();
}

class _LivePlanState extends State<LivePlan> {
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
      Binding(
        'ctrl+t',
        'stop or start the work',
        () => setState(() => _running = !_running),
      ),
    ],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          const Expanded(child: SizedBox()),
          if (_running) Text(' ››› Working…'),
          Plan(plan: livePlanEntries, limit: 6, running: _running),
          PromptInput(
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
