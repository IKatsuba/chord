import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'resume.dart' show resumeFixtureState;

Future<void> main(List<String> args) async {
  if (args.contains('--resume')) {
    await runApp(
      ResumeStartPage(
        version: '0.0.1',
        directory: 'project',
        agent: 'fake',
        cwd: 'project',
        home: 'home',
        sessions: resumeFixtureState(args).sessions,
        openedAt: 946771200000,
        onPicked: (_) {},
      ),
      theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
      environment: {
        ...Platform.environment,
        if (args.contains('--plain')) 'NO_COLOR': '1',
      },
    );
    return;
  }
  final count = args.contains('--empty')
      ? 0
      : args.contains('--many')
      ? 28
      : 3;
  final names = ['claude', 'codex', 'pi'];
  String? picked;
  await runApp(
    StartPage(
      version: '0.0.1',
      directory: args.contains('--long')
          ? '/workspace/packages/terminal/interfaces/example/project'
          : '/workspace/demo',
      agents: [
        for (var i = 0; i < count; i++)
          ListedAgent(
            name: i < names.length ? names[i] : 'agent-$i',
            title: i < names.length ? names[i] : 'Coding agent $i',
            start: 'unused',
            from: AgentRunner.cli,
            found: i == 2 ? false : true,
          ),
      ],
      onPicked: (value) => picked = value,
    ),
  );
  stdout.writeln(picked == null ? 'Canceled' : 'Picked: $picked');
}
