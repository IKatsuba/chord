// Agent-free resume frame and scope fixture.
import 'dart:io';

import 'package:chord/session/sessions.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord_tui/chord_tui.dart';

/// Stable local/all/empty/tall rows; no filesystem or agent is reached.
ResumePickerState resumeFixtureState(List<String> args) => ResumePickerState(
  cwd: 'project',
  opening: 'fixture',
  openedAt: 946771200000,
  everywhere: args.contains('--all'),
  sessions: [
    for (var i = 0; i < (args.contains('--many') ? 30 : 4); i++)
      EarlierSession(
        resume: Resume(
          sessionId: 'saved-$i',
          cwd: args.contains('--empty') || i.isOdd
              ? 'home/projects/界😀/another-directory-$i'
              : 'project',
        ),
        lastUsedAt: i == 0 ? '2000-01-02T00:00:00Z' : '2000-01-01T00:00:00Z',
        prompt: args.contains('--tall') && i == 0
            ? [
                for (var line = 1; line <= 40; line++) 'Saved title line $line',
              ].join('\n')
            : i == 0
            ? 'Inspect the saved notes and retain this descriptive title across wrapped lines.'
            : 'Saved session $i · 界😀 with a long title and an_unbroken_title_tail',
      ),
  ],
);

/// Interactive scope remounting, frozen ages and acceptance without IO.
class ResumeFixture extends StatefulWidget {
  const ResumeFixture(this.args, {super.key});
  final List<String> args;
  @override
  State<ResumeFixture> createState() => _ResumeFixtureState();
}

class _ResumeFixtureState extends State<ResumeFixture> {
  late ResumePickerState _picker = resumeFixtureState(widget.args);
  String _chosen = '';
  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(child: Text(_chosen)),
          ResumePicker(
            key: ValueKey((_picker.opening, _picker.everywhere)),
            picker: _picker,
            agent: 'fake',
            home: 'home',
            rows: 6,
            room: widget.args.contains('--zero')
                ? 6
                : constraints.maxHeight - 1,
            starting: widget.args.contains('--starting'),
            onToggleScope: () => setState(
              () => _picker = toggledResumeScope(_picker, _picker.openedAt),
            ),
            onSelected: (session) => setState(
              () => _chosen = 'Selected ${session.resume.sessionId}',
            ),
            onCanceled: () => exitApp(context),
          ),
        ],
      ),
    ),
  );
}

Future<void> main(List<String> args) => runApp(
  ResumeFixture(args),
  theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
  environment: {
    ...Platform.environment,
    if (args.contains('--plain')) 'NO_COLOR': '1',
  },
);
