import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/start_failure.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart' show StartPhase;
import 'package:test/test.dart';

void main() {
  test('a failed start keeps its sign-in and its facts', () {
    const signIn = SignIn('Authentication required', []);
    const failure = StartFailure(
      step: StartStep.newSession,
      code: -32000,
      pinned: 'memory-acp@1.2.3',
    );
    final state = reduceApp(
      AppState.starting,
      const ConnectFailed('no', signIn: signIn, failure: failure),
    );
    expect(state.start.phase, StartPhase.failed);
    expect(state.start.signIn, same(signIn));
    expect(state.start.failure, same(failure));
  });

  test('a sign-in under a resume is still found', () {
    const signIn = SignIn('Authentication required', []);
    final needed = SignInNeeded(
      signIn,
      StartFailed(
        const StartFailure(step: StartStep.loadSession, code: -32000),
        message: 'Authentication required',
        cause: StateError('x'),
      ),
    );
    expect(signInOf(ResumeError('it cannot resume', cause: needed)), signIn);
    expect(signInOf(const ResumeError('it cannot resume')), isNull);
  });

  test('the offers line counts the ways', () {
    expect(offersLine('codex', 1), 'codex offers this sign-in:');
    expect(offersLine('codex', 2), 'codex offers these sign-ins:');
  });

  test('the window names the pin only for a catalog start', () async {
    final state = Directory.systemTemp.createTempSync('chord-pin-');
    addTearDown(() => state.deleteSync(recursive: true));
    final agent = listAgents().firstWhere((each) => each.pinned != null);
    Launch launch({String? command}) => Launch(
      name: agent.name,
      agent: agent,
      agentCommand: command,
      version: 'test',
      directory: 'project',
    );
    for (final (each, pinned) in [
      (launch(), agent.pinned),
      (launch(command: 'own'), null),
    ]) {
      final connection = startLaunchConnection(
        each,
        cwd: '/w',
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => Future.error(StateError('no')),
        stateDirectory: () => state.path,
      );
      expect(connection.pinned, pinned);
      await connection.close();
    }
  });
}
