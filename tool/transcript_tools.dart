import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart';

// U5 visual fixture, no agent: ctrl+o expands, ctrl+q quits.
void main(List<String> args) => runApp(_Tools(args));

class _Tools extends StatefulWidget {
  const _Tools(this.args);
  final List<String> args;
  @override
  State<_Tools> createState() => _ToolsState();
}

class _ToolsState extends State<_Tools> {
  var expanded = false;
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  late final calls = <model.ToolCall>[
    if (widget.args.contains('--review')) ...[
      const model.ToolCall(
        'review-terminal',
        title: 'Run checks',
        review: PermissionReview('caution', 'check'),
        terminals: [model.Terminal('t', output: 'output')],
      ),
      model.ToolCall(
        'review-diff',
        title: 'Edit a.ts',
        review: const PermissionReview('caution', 'check'),
        content: [
          acp.ToolCallContent.fromJson({
            'type': 'diff',
            'path': 'a.ts',
            'oldText': 'a',
            'newText': 'b',
          }),
        ],
      ),
    ],
    model.ToolCall(
      'read',
      title: widget.args.contains('--wrap')
          ? 'Read ${'src/very_long_directory/' * 8}main.ts'
          : 'Read src/main.ts',
      kind: 'read',
      status: 'completed',
      content: [
        acp.ToolCallContent.fromJson({
          'type': 'content',
          'content': {'type': 'text', 'text': 'one\ntwo\nthree\nfour\nfive'},
        }),
      ],
    ),
    const model.ToolCall(
      'terminal',
      title: 'Run bun dev test',
      kind: 'execute',
      status: 'failed',
      terminals: [
        model.Terminal(
          't',
          output: 'test\nstart\n3/3\nok | 2 passed\nFAILED | 1 failed\n',
          exited: true,
          exitCode: 1,
        ),
      ],
    ),
    model.ToolCall(
      'edit',
      title: 'Edit src/greet.ts',
      status: 'completed',
      content: [
        acp.ToolCallContent.fromJson({
          'type': 'diff',
          'path': widget.args.contains('--wrap')
              ? '${'src/very_long_directory/' * 8}greet.ts'
              : 'src/greet.ts',
          'oldText': 'export function greet() {\n  return "hello";\n}',
          'newText': 'export function greet() {\n  return "hello, world";\n}',
        }),
      ],
    ),
    const model.ToolCall('guardian', guardian: 'inProgress'),
    const model.ToolCall(
      'running',
      title: 'Bash echo working',
      status: 'in_progress',
    ),
    const model.ToolCall('failed', title: 'Read missing.txt', status: 'failed'),
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
      ...scrollBindings(scroll),
    ],
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: widget.args.contains('--narrow') ? 22 : unbounded,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: ListView.builder(
            controller: scroll,
            itemCount: calls.length,
            itemVersion: (i) => (calls[i], expanded),
            itemBuilder: (context, i) => Tool(calls[i], expanded: expanded),
          ),
        ),
      ),
    ),
  );
}
