import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/session/session.dart';

/// In-memory ACP steering with held turns and outcomes released by the fixture.
final class SteeringAgent {
  SteeringAgent({this.supported = true, this.cutsCalls = false}) {
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit();
        process.closeStdout();
        process.closeStderr();
      },
    );
  }
  final bool supported, cutsCalls;
  late final MemoryAgentProcess process;
  final requests = <Map<String, Object?>>[];
  final pendingSteers = <Map<String, Object?>>[];
  Object? _prompt;
  int _asks = 0;
  String? _permission;
  bool callOpen = false;
  bool get hasPrompt => _prompt != null;
  bool get hasPermission => _permission != null;
  static const id = 'steering-fixture';

  SessionOpener get open =>
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
        onTraffic: (traffic) {
          onTraffic(traffic);
          if (traffic case ChordTraffic(:final message)) {
            if (message['id'] == _permission && message.containsKey('result')) {
              _permission = null;
            }
            if (message['method'] is String) _react(message);
          }
        },
        onPermission: onPermission,
        relay: relay,
        cancellationToken: cancellationToken,
        stop: const StopBounds(
          exit: Duration.zero,
          term: Duration(milliseconds: 10),
          kill: Duration(milliseconds: 100),
        ),
      );

  void _answer(Object? rpcId, Object? result) =>
      process.send({'jsonrpc': '2.0', 'id': rpcId, 'result': result});
  void _react(Map<String, Object?> message) {
    requests.add(message);
    final rpcId = message['id'];
    switch (message['method']) {
      case 'initialize':
        _answer(rpcId, {
          'protocolVersion': 1,
          'agentInfo': {
            'name': cutsCalls
                ? '@agentclientprotocol/claude-agent-acp'
                : 'steering-fixture',
            'version': '1',
          },
          if (supported)
            '_meta': {
              'steering': {'supported': true},
            },
        });
      case 'session/new':
        _answer(rpcId, {'sessionId': id});
        update({
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'review', 'description': 'Review the fixture'},
            {'name': 'rewrite', 'description': 'Rewrite the fixture'},
          ],
        });
      case 'session/prompt':
        _prompt = rpcId;
        chunk('Working');
      case '_session/steering':
        pendingSteers.add(message);
      case 'session/cancel':
        finishPrompt(cancelled: true);
      default:
        if (message.containsKey('id')) _answer(rpcId, <String, Object?>{});
    }
  }

  /// Releases one pending steer with the adapter's real outcome spelling.
  void answerSteer([String outcome = 'injected']) {
    if (pendingSteers.isEmpty) return;
    _answer(pendingSteers.removeAt(0)['id'], {'outcome': outcome});
  }

  /// Finishes the held client prompt without starting another one itself.
  void finishPrompt({bool cancelled = false}) {
    final prompt = _prompt;
    if (prompt == null) return;
    _prompt = null;
    _answer(prompt, {'stopReason': cancelled ? 'cancelled' : 'end_turn'});
  }

  /// A current session update through the normal ACP ingress.
  void update(Map<String, Object?> update) => process.send({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': id, 'update': update},
  });
  void chunk(String text) => update({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  /// A single captured call that can hold Claude-style steering.
  void toggleCall() {
    callOpen = !callOpen;
    update({
      'sessionUpdate': callOpen ? 'tool_call' : 'tool_call_update',
      'toolCallId': 'fixture-call',
      'title': 'Read notes.txt',
      'kind': 'read',
      'status': callOpen ? 'in_progress' : 'completed',
    });
  }

  /// A real pending permission, answered by the window's existing keys.
  void askPermission() {
    if (_permission != null) return;
    _permission = 'fixture-ask-${++_asks}';
    process.send({
      'jsonrpc': '2.0',
      'id': _permission,
      'method': 'session/request_permission',
      'params': {
        'sessionId': id,
        'toolCall': {
          'toolCallId': 'fixture-write',
          'title': 'Approve notes',
          'kind': 'edit',
        },
        'options': [
          {'optionId': 'allow', 'name': 'Allow once', 'kind': 'allow_once'},
          {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
        ],
      },
    });
  }
}
