// In-memory ACP scenario: selected history, held turns and an unsolicited ask.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/session/session.dart';

/// A deterministic agent for resume ownership races, without a child process.
final class ResumeAgent {
  ResumeAgent() {
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit();
        process.closeStdout();
        process.closeStderr();
      },
    );
  }
  late final MemoryAgentProcess process;
  final requests = <Map<String, Object?>>[];
  final permissionAnswered = Completer<void>();
  String id = 'current';
  String? cwd;
  bool holdPrompt = false;
  Object? _prompt;

  SessionOpener get open =>
      ({
        required command,
        env,
        required cwd,
        required onTraffic,
        required onPermission,
        relay,
        cancellationToken,
      }) {
        this.cwd = cwd;
        return connectAgent(
          process,
          onTraffic: (traffic) {
            onTraffic(traffic);
            if (traffic case ChordTraffic(:final message)) {
              if (message['id'] == 'ask' &&
                  message.containsKey('result') &&
                  !permissionAnswered.isCompleted) {
                permissionAnswered.complete();
              }
              if (message['method'] is String && message.containsKey('id')) {
                _react(message);
              }
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
      };
  void _answer(Object? rpcId, Object? result) =>
      process.send({'jsonrpc': '2.0', 'id': rpcId, 'result': result});
  void _react(Map<String, Object?> message) {
    requests.add(message);
    final rpcId = message['id'];
    switch (message['method']) {
      case 'initialize':
        _answer(rpcId, {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
        });
      case 'session/new':
        _answer(rpcId, {'sessionId': id});
      case 'session/load':
        id = (message['params'] as Map)['sessionId'] as String;
        _answer(rpcId, <String, Object?>{});
      case 'session/prompt':
        _prompt = rpcId;
        if (!holdPrompt) finishPrompt();
      case 'session/cancel':
        if (_prompt != null) finishPrompt();
      default:
        _answer(rpcId, <String, Object?>{});
    }
  }

  /// Completes the admitted turn only when the test releases it.
  void finishPrompt() {
    final rpcId = _prompt;
    if (rpcId == null) return;
    _prompt = null;
    process.send({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': id,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Live reply from $id.'},
        },
      },
    });
    _answer(rpcId, {'stopReason': 'end_turn'});
  }

  /// A permission arriving after the saved picker opened has the next keys.
  void askPermission() => process.send({
    'jsonrpc': '2.0',
    'id': 'ask',
    'method': 'session/request_permission',
    'params': {
      'sessionId': id,
      'toolCall': {
        'toolCallId': 'permission-tool',
        'title': 'Approve notes',
        'kind': 'edit',
        'status': 'pending',
        'content': <Object?>[],
      },
      'options': [
        {'optionId': 'allow', 'name': 'Allow once', 'kind': 'allow_once'},
        {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
      ],
    },
  });
}
