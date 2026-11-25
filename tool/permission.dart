import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord_tui/chord_tui.dart';

/// A standalone agent-free permission state for visual inspection.
PermissionWait permissionFixture({String mode = 'diff'}) => PermissionWait(
  'fixture',
  title: 'Write notes.txt',
  options: [
    for (final (id, name, kind) in [
      ('allow', 'Allow once', 'allow_once'),
      ('always', 'Always allow', 'allow_always'),
      ('deny', 'Deny', 'reject_once'),
    ])
      acp.PermissionOption.fromJson({
        'optionId': id,
        'name': mode == 'long'
            ? '$name, and do not ask again for files - write_file commands in this project'
            : name,
        'kind': kind,
      }),
  ],
  content: [
    acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': 'notes.txt',
      'oldText': 'old\n',
      'newText': [
        for (var i = 1; i <= 60; i++) 'proposed line $i',
        '',
      ].join('\n'),
    }),
  ],
  review: mode == 'review' || mode == 'held' || mode == 'one'
      ? const PermissionReview(
          'caution',
          'This command could overwrite files outside the project. Review the proposed changes before allowing it.',
        )
      : mode == 'failed'
      ? const PermissionReview('failed', 'The reviewer did not respond')
      : null,
  deadlineAt: 300000,
);

void main(List<String> args) =>
    runApp(permissionPreview(args.isEmpty ? 'diff' : args.first));

/// The same preview used by the terminal fixture, for headless key checks.
Widget permissionPreview(String mode) => _Fixture(mode);

class _Fixture extends StatefulWidget {
  const _Fixture(this.mode);
  final String mode;

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final scroll = PermissionScroll();
  final focus = FocusNode();
  var answered = '';
  late var held = widget.mode == 'held';

  @override
  void dispose() {
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      for (final (key, step) in [
        ('pageup', ScrollStep.pageUp),
        ('pagedown', ScrollStep.pageDown),
        ('shift+pageup', ScrollStep.pageUp),
        ('shift+pagedown', ScrollStep.pageDown),
      ])
        Binding(key, 'Scroll request', () => scroll.step(step), enabled: !held),
      Binding('ctrl+x a', 'Answer waiting request', () {
        setState(() => held = false);
        context.owner.afterLayout(focus.requestFocus);
      }),
      Binding('ctrl+c', 'Quit', () => exitApp(context)),
    ],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permission fixture: ${widget.mode}'),
          Expanded(child: Text('Transcript')),
          PermissionPrompt(
            wait: permissionFixture(mode: widget.mode),
            windowRows: constraints.maxHeight,
            maxRows: widget.mode == 'one' ? 15 : constraints.maxHeight - 3,
            scroll: scroll,
            focusNode: focus,
            held: held,
            between: widget.mode == 'held',
            onChoose: (value) => setState(() => answered = value),
            onReject: () => setState(() => answered = 'Rejected'),
          ),
          Focus(autofocus: held, child: Text('Answer: $answered')),
        ],
      ),
    ),
  );
}
