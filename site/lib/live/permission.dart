import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord_tui/chord_tui.dart';

import 'answer.dart';

/// The request the fixture asks: a write with its diff, and three choices.
PermissionWait livePermissionWait() => PermissionWait(
  'live',
  title: 'Write notes.txt',
  options: [
    for (final (id, name, kind) in [
      ('allow', 'Allow once', 'allow_once'),
      ('always', 'Always allow', 'allow_always'),
      ('deny', 'Deny', 'reject_once'),
    ])
      acp.PermissionOption.fromJson({
        'optionId': id,
        'name': name,
        'kind': kind,
      }),
  ],
  content: [
    acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': 'notes.txt',
      'oldText': 'old\n',
      'newText': [
        for (var i = 1; i <= 12; i++) 'proposed line $i',
        '',
      ].join('\n'),
    }),
  ],
);

/// chord's permission prompt, live, as `tool/permission.dart` has it: a
/// choice shows as one line, and `r` asks again.
class LivePermission extends StatefulWidget {
  /// The permission fixture.
  const LivePermission({super.key});

  @override
  State<LivePermission> createState() => _LivePermissionState();
}

class _LivePermissionState extends State<LivePermission> {
  final _scroll = PermissionScroll();
  final _focus = FocusNode();
  String? _answer;
  late PermissionWait _wait = livePermissionWait();

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _answered(String answer) => setState(() => _answer = answer);

  void _again() {
    setState(() {
      _answer = null;
      _wait = livePermissionWait();
    });
    context.owner.afterLayout(_focus.requestFocus);
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    if (answer != null) {
      return Actions(
        bindings: [Binding('r', 'ask again', _again)],
        child: Focus(autofocus: true, child: AnswerLine(answer)),
      );
    }
    return Actions(
      bindings: [
        for (final (key, step) in [
          ('pageup', ScrollStep.pageUp),
          ('pagedown', ScrollStep.pageDown),
        ])
          Binding(key, 'scroll the request', () => _scroll.step(step)),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            PermissionPrompt(
              wait: _wait,
              windowRows: constraints.maxHeight,
              maxRows: constraints.maxHeight,
              scroll: _scroll,
              focusNode: _focus,
              onChoose: (id) => _answered(switch (id) {
                'allow' => 'Allowed once',
                'always' => 'Always allowed',
                _ => 'Denied',
              }),
              onReject: () => _answered('Rejected'),
            ),
          ],
        ),
      ),
    );
  }
}
