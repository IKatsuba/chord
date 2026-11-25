import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/initial_options.dart';
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _claude = '@agentclientprotocol/claude-agent-acp';

acp.InitializeResponse _init({
  String? name = _claude,
  Object? options = true,
}) => acp.InitializeResponse.fromJson({
  'protocolVersion': 1,
  'agentCapabilities': {
    'sessionCapabilities': {'options': ?options},
  },
  if (name != null) 'agentInfo': {'name': name, 'version': '1'},
});

void main() {
  test('the table\'s agent with options takes model, effort and mode, in '
      'that order, as entries', () {
    expect(
      initialEntries(_init(), (model: 'opus', effort: 'high', mode: 'plan')),
      [
        {'configId': 'model', 'value': 'opus'},
        {'configId': 'effort', 'value': 'high'},
        {'configId': 'mode', 'value': 'plan'},
      ],
    );
    expect(initialEntries(_init(), (model: null, effort: null, mode: 'plan')), [
      {'configId': 'mode', 'value': 'plan'},
    ]);
  });

  test('no entries without the options capability or for an agent the '
      'table lacks', () {
    const values = (model: 'opus', effort: null, mode: null);
    for (final init in [
      _init(options: null),
      _init(options: false),
      _init(name: 'codex-acp'),
      _init(name: null),
    ]) {
      expect(initialEntries(init, values), isEmpty);
    }
  });

  test('session/new carries the entries where the agent takes them, and '
      'nothing else where it does not', () {
    for (final (name, expected) in [
      (
        _claude,
        [
          {'configId': 'mode', 'value': 'plan'},
        ],
      ),
      ('other', null),
    ]) {
      fakeAsync((async) {
        late final MemoryAgentProcess process;
        process = MemoryAgentProcess(
          onSignal: (_) {
            process.exit(const Exit(143, 'SIGTERM'));
            process.closeStdout();
            process.closeStderr();
          },
        );
        Map<String, Object?> last(String method) =>
            process.stdin.messages.lastWhere((m) => m['method'] == method);
        void answer(Object? id, Map<String, Object?> result) =>
            process.send({'jsonrpc': '2.0', 'id': id, 'result': result});
        Session? session;
        openSession(
          agent: 'memory',
          command: 'memory',
          cwd: '/w',
          initial: (model: null, effort: null, mode: 'plan'),
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) => connectAgent(
                process,
                onTraffic: onTraffic,
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              ),
        ).then((s) => session = s);
        async.flushMicrotasks();
        answer(last('initialize')['id'], _init(name: name).toJson());
        async.flushMicrotasks();
        final request = last('session/new');
        expect(
          (request['params'] as Map)['configOptions'],
          expected,
          reason: name,
        );
        answer(request['id'], {'sessionId': 's1'});
        async.flushMicrotasks();
        session!.close();
        async.elapse(const Duration(seconds: 5));
      });
    }
  });
}
