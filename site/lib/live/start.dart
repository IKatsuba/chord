import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord_tui/chord_tui.dart';

import 'answer.dart';

/// The agents the start page offers: two found, one not on PATH.
final liveAgents = [
  for (final (name, found) in [
    ('claude', true),
    ('codex', true),
    ('pi', false),
  ])
    ListedAgent(
      name: name,
      title: name,
      start: 'unused',
      from: AgentRunner.cli,
      found: found,
    ),
];

/// chord's start page, live, as `tool/start.dart` has it, with a canned
/// agent list: a pick shows as one line, and `r` asks again.
class LiveStart extends StatefulWidget {
  /// The start fixture, saying [version].
  const LiveStart({super.key, this.version = '0.0.1'});

  /// The version the page says.
  final String version;

  @override
  State<LiveStart> createState() => _LiveStartState();
}

class _LiveStartState extends State<LiveStart> {
  String? _picked;
  var _round = 0;

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    if (picked != null) {
      return Actions(
        bindings: [
          Binding(
            'r',
            'ask again',
            () => setState(() {
              _picked = null;
              _round++;
            }),
          ),
        ],
        child: Focus(autofocus: true, child: AnswerLine('Picked $picked')),
      );
    }
    return StartPage(
      // A fresh page each round, its selection back at the start.
      key: ValueKey(_round),
      version: widget.version,
      directory: '/workspace/demo',
      agents: liveAgents,
      onPicked: (name) => setState(() => _picked = name),
    );
  }
}
