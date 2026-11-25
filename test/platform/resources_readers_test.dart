// The official readers as a window reaches them: a runtime started with the
// person's own command is never read, through the host's place. No
// installed provider is ever reached.
@TestOn('posix')
library;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resources.dart';
import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/budgets.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:test/test.dart';

import '../fixtures/runtimes.dart';

/// Collectors that record what they were asked, reading nothing.
final class _Recording implements ResourceCollectors {
  final asked = <String>[];

  @override
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  ) async {
    asked.add('resolve:$provider:$customCommand');
    // The official resolution, which answers a custom command without
    // looking anything up.
    return customCommand
        ? officialCollectors.resolve(provider, cwd, true, cancelled)
        : const ExecutableUnavailable('not read here');
  }

  @override
  Future<ProviderLimits> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  ) => throw TestFailure('read $provider');
}

void main() {
  test("a runtime the person starts with a command of their own is never "
      'read; one chord starts is resolved as official', () async {
    final runtimes = TestRuntimes();
    addTearDown(runtimes.dispose);
    final connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    final collectors = _Recording();
    final host = AgentsHost(
      runtimeNames: const ['claude', 'codex'],
      startupOf: (runtime) => switch (runtime) {
        'codex' => const SessionStart(
          command: 'my-codex --acp',
          agentCommand: 'my-codex --acp',
        ),
        _ => const SessionStart(command: 'npx claude-agent-acp'),
      },
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) => throw TestFailure('nothing opens'),
      agents: connection.agents,
      opened: (_) {},
      resources: createResources(GivenCollectors(collectors)).read,
    );
    final budgets = (await host.budgets(
      Caller(role: Role.person, key: 1, window: host),
      null,
      CancellationToken(),
    ))!;
    expect(
      [for (final provider in budgets.providers) provider.toJson()],
      [
        {'agent': 'claude', 'unavailable': 'not read here'},
        {
          'agent': 'codex',
          'unavailable':
              'Custom ACP command has no verified association with the '
              'official native provider authentication.',
        },
      ],
    );
    expect(collectors.asked, ['resolve:claude:false', 'resolve:codex:true']);
  });
}
