import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';

// U4 visual fixture: no agent. ctrl+o expands the thought, ctrl+q quits.
void main(List<String> args) => runApp(_Entries(args));

class _Entries extends StatefulWidget {
  const _Entries(this.args);
  final List<String> args;
  @override
  State<_Entries> createState() => _EntriesState();
}

class _EntriesState extends State<_Entries> {
  var expanded = false;
  late final entries = widget.args.contains('--plan-long')
      ? <model.Entry>[
          model.FinishedPlanEntry('t', [
            acp.PlanEntry.fromJson({
              'content':
                  'A long completed plan step with terminal cells and Unicode 日本語 ' *
                  4,
              'status': 'completed',
              'priority': 'medium',
            }),
          ]),
        ]
      : widget.args.contains('--permission')
      ? <model.Entry>[
          model.PermissionEntry(
            't',
            title: 'Bash ls',
            option: acp.PermissionOption.fromJson({
              'optionId': 'allow',
              'name': 'Allow once',
              'kind': 'allow_once',
            }),
          ),
          const model.PermissionEntry('t'),
        ]
      : widget.args.contains('--markdown')
      ? <model.Entry>[
          const model.UserEntry('t', 'markdown'),
          model.AssistantEntry(
            't',
            TextRun.empty.plus(
              'A **growing** reply with an open code fence.\n\n```dart\nfinal answer = 42;\n',
            ),
          ),
        ]
      : widget.args.contains('--wrap')
      ? <model.Entry>[
          model.UserEntry(
            't',
            List.filled(
              12,
              'A long user prompt with 日本語 and emoji 👩‍💻',
            ).join(' '),
          ),
          model.StoppedEntry(
            't',
            List.filled(12, 'a long stop reason').join(' '),
          ),
        ]
      : <model.Entry>[
          const model.UserEntry('t', 'thought'),
          model.ThoughtEntry(
            't',
            TextRun.empty.plus(
              'First, understand the request.\nThen, answer clearly.',
            ),
          ),
          model.AssistantEntry(
            't',
            TextRun.empty.plus(
              'The answer is **ready**.\n\n- One item\n- Another item',
            ),
          ),
          const model.CancelledEntry('t'),
          const model.StoppedEntry('t', 'max_tokens'),
          const model.WarningEntry('t', 'A warning from the agent.'),
          const model.ErrorEntry('t', 'An error from the agent.'),
          model.FinishedPlanEntry('t', [
            acp.PlanEntry.fromJson({
              'content': 'Read the source',
              'status': 'completed',
              'priority': 'medium',
            }),
            acp.PlanEntry.fromJson({
              'content': 'Finish the change',
              'status': 'completed',
              'priority': 'medium',
            }),
          ]),
        ];

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding(
        'ctrl+o',
        'Toggle transcript details',
        () => setState(() => expanded = !expanded),
      ),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            TranscriptEntry(
              entry,
              expanded: expanded,
              growing: widget.args.contains('--markdown'),
            ),
        ],
      ),
    ),
  );
}
