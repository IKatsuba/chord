import 'dart:io';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/status/status_line.dart';
import 'package:chord/ui/status/working.dart';
import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) => runApp(
  const StatusFixture(),
  theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
  environment: {
    ...Platform.environment,
    if (args.contains('--plain')) 'NO_COLOR': '1',
  },
);

/// Status and working states, using the original app palette in each theme.
class StatusFixture extends StatefulWidget {
  const StatusFixture({super.key});
  @override
  State<StatusFixture> createState() => _StatusFixtureState();
}

class _StatusFixtureState extends State<StatusFixture> {
  final _draft = TextAreaController();
  final _since = DateTime.now().millisecondsSinceEpoch - 12000;
  int _turn = 0;
  int _mode = 0;
  static const _modes = [
    'plan',
    'acceptEdits',
    'auto',
    'bypassPermissions',
    'read-only',
    'default',
  ];
  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    child: Actions(
      bindings: [
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        Binding(
          'ctrl+t',
          'Cycle working state',
          () => setState(() => _turn = (_turn + 1) % 4),
        ),
        Binding(
          'ctrl+g',
          'Cycle mode',
          () => setState(() => _mode = (_mode + 1) % _modes.length),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            const Expanded(child: SizedBox()),
            Working(
              turn: switch (_turn) {
                0 => model.Working('turn', _since),
                1 => model.Cancelling('turn', _since, _since + 10000),
                2 => model.AwaitingPermission('turn', _since, const [
                  model.PermissionWait('ask'),
                ]),
                _ => const model.Idle(),
              },
            ),
            PromptInput(
              key: const ValueKey('prompt-input'),
              controller: _draft,
              windowRows: constraints.maxHeight,
              onSubmit: (_) => _draft.clear(),
              onOlder: () {},
              onNewer: () {},
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: StatusLine(
                facts: StatusFacts(
                  model: 'Fake Large with a 1M context window',
                  effort: 'medium',
                  mode: _modes[_mode],
                  modeName: _mode == 4 ? 'Read Only' : null,
                  usage: const model.Usage(1200, 200000),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
