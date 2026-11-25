// Commands run as Codex's adapter and Claude's run them, with their
// terminals, as the original's scenarios/shell.ts.
import '../../terminals.dart';
import '../client.dart';
import '../options.dart';
import '../sessions.dart';
import '../turn.dart';

/// How long the `shell` scenario's command takes between pieces of output,
/// and how long the `bash` scenario's runs before its output comes.
num get _shellStepMs => stepMs * 100;

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// A command as Codex's adapter runs one, writing [pieces].
Future<String> _codexShell(Turn turn, List<String> pieces) async {
  final toolCallId = turn.callId('shell');
  final terminalId = 'terminal-$toolCallId';
  Future<void> update(Map<String, Object?> meta, [String? status]) =>
      turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': toolCallId,
        'status': ?status,
        '_meta': meta,
      });

  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': 'Run bun dev test',
    'kind': 'execute',
    'status': 'in_progress',
    'rawInput': {
      'command': ['deno', 'task', 'test'],
    },
    'content': [
      {'type': 'terminal', 'terminalId': terminalId},
    ],
    '_meta': {
      'terminal_info': {
        'terminal_id': terminalId,
        'cwd': cwds[turn.sessionId] ?? '',
      },
    },
  });
  for (final data in pieces.sublist(0, pieces.length - 1)) {
    await pause(turn.signal, _shellStepMs);
    await update({
      'terminal_output_delta': {'terminal_id': terminalId, 'data': data},
    });
  }
  await pause(turn.signal, _shellStepMs);
  await update({
    'terminal_output_delta': {'terminal_id': terminalId, 'data': pieces.last},
    'terminal_exit': {
      'terminal_id': terminalId,
      'exit_code': 1,
      'signal': null,
    },
  }, 'failed');
  await turn.say(['The tests failed.']);
  return 'end_turn';
}

/// A command's permission asked as [toolCall], with the options [agent]'s
/// adapter gives: whether it was allowed, or null when cancelled.
Future<bool?> _askToRun(
  Turn turn,
  Map<String, Object?> toolCall,
  String agent,
) async {
  final answer = await turn.client.request('session/request_permission', {
    'sessionId': turn.sessionId,
    'toolCall': toolCall,
    'options': [
      {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
      {
        'optionId': 'always',
        'name': "Yes, and don't ask again for this command",
        'kind': 'allow_always',
      },
      {
        'optionId': 'deny',
        'name': 'No, and tell $agent what to do differently',
        'kind': 'reject_once',
      },
    ],
  });
  final outcome = (answer['outcome'] as Map?) ?? const {};
  return outcome['outcome'] == 'cancelled'
      ? null
      : outcome['optionId'] != 'deny';
}

/// A command Codex's adapter has started that asks for approval part way
/// through and stays `in_progress` while it asks (CHD-404).
Future<bool?> _codexAsksMidRun(Turn turn) async {
  final toolCallId = turn.callId('shell');
  final terminalId = 'terminal-$toolCallId';
  final toolCall = {
    'toolCallId': toolCallId,
    'title': 'Run ./deploy.sh',
    'kind': 'execute',
    'status': 'in_progress',
    'rawInput': {
      'command': ['./deploy.sh'],
    },
  };
  Future<void> output(String data, [int? exit]) => turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    if (exit != null) 'status': exit == 0 ? 'completed' : 'failed',
    '_meta': {
      'terminal_output_delta': {'terminal_id': terminalId, 'data': data},
      if (exit != null)
        'terminal_exit': {
          'terminal_id': terminalId,
          'exit_code': exit,
          'signal': null,
        },
    },
  });

  await turn.send({
    'sessionUpdate': 'tool_call',
    ...toolCall,
    'content': [
      {'type': 'terminal', 'terminalId': terminalId},
    ],
    '_meta': {
      'terminal_info': {
        'terminal_id': terminalId,
        'cwd': cwds[turn.sessionId] ?? '',
      },
    },
  });
  await pause(turn.signal, _shellStepMs);
  await output('building…\n');
  await pause(turn.signal, _shellStepMs);
  await output('built in 1.2s\n');
  final allowed = await _askToRun(turn, toolCall, 'Codex');
  if (allowed == null) return null;
  await pause(turn.signal, _shellStepMs);
  await output(allowed ? 'deployed\n' : 'not deployed\n', allowed ? 0 : 1);
  return allowed;
}

/// A command Claude's adapter asks for first, `pending`, and leaves
/// `pending` once allowed until it completes.
Future<bool?> _claudeAsksFirst(Turn turn) async {
  final toolCallId = turn.callId('bash');
  final takes = clientTerminalOutput != 'none';
  final terminal = [
    {'type': 'terminal', 'terminalId': toolCallId},
  ];
  final toolCall = {
    'toolCallId': toolCallId,
    'title': '`git push`',
    'kind': 'execute',
    'status': 'pending',
    'rawInput': {'command': 'git push'},
  };
  await turn.send({
    'sessionUpdate': 'tool_call',
    ...toolCall,
    'content': takes ? terminal : <Object?>[],
    if (takes)
      '_meta': {
        'terminal_info': {'terminal_id': toolCallId},
      },
  });
  final allowed = await _askToRun(turn, toolCall, 'Claude');
  if (allowed == null) return null;
  if (!allowed) {
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'failed',
    });
    return false;
  }
  await pause(turn.signal, _shellStepMs);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    if (takes) ...{
      'content': terminal,
      '_meta': {
        clientTerminalOutput == 'delta'
            ? 'terminal_output_delta'
            : 'terminal_output': {
          'terminal_id': toolCallId,
          'data': 'pushed\n',
        },
        'terminal_exit': {
          'terminal_id': toolCallId,
          'exit_code': 0,
          'signal': null,
        },
      },
    } else
      'content': [_text('pushed')],
  });
  return true;
}

/// A command as Claude's adapter runs one; its next step after it waits
/// until [untilTold] messages were steered in.
Future<String> _claudeBash(Turn turn, [int untilTold = 0]) async {
  final toolCallId = turn.callId('bash');
  final terminalId = toolCallId;
  final takes = clientTerminalOutput != 'none';
  final terminal = [
    {'type': 'terminal', 'terminalId': terminalId},
  ];
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': '`git status --short`',
    'kind': 'execute',
    'status': 'pending',
    'rawInput': {'command': 'git status --short'},
    'content': takes ? terminal : <Object?>[],
    if (takes)
      '_meta': {
        'terminal_info': {'terminal_id': terminalId},
      },
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'in_progress',
  });
  // The command takes a moment, so its call is seen working with no output.
  await pause(turn.signal, _shellStepMs);

  if (!takes) {
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'completed',
      'content': [_text('```console\n${bashOutput.trimRight()}\n```')],
    });
  } else {
    final output = {'terminal_id': terminalId, 'data': bashOutput};
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      '_meta': clientTerminalOutput == 'delta'
          ? {'terminal_output_delta': output}
          : {'terminal_output': output},
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'completed',
      'content': terminal,
      '_meta': {
        'terminal_exit': {
          'terminal_id': terminalId,
          'exit_code': 0,
          'signal': null,
        },
      },
    });
  }

  // The next step comes once the messages told during the call are in
  // (CHD-467).
  await steeredIn(turn, untilTold);
  await turn.say(['Two files changed.']);
  return 'end_turn';
}

final Map<String, Play> shell = {
  // A command as Codex's adapter runs one, to any client.
  'shell': (turn) => _codexShell(turn, shellOutput),

  'shellcut': (turn) => _codexShell(turn, cutOutput),

  // A permission asked for a command as each adapter asks.
  'bashask': (turn) async {
    final codex = await _codexAsksMidRun(turn);
    if (codex == null) return 'cancelled';
    final claude = await _claudeAsksFirst(turn);
    if (claude == null) return 'cancelled';
    await turn.say([
      'Codex: ${codex ? 'ran' : 'denied'}; Claude: ${claude ? 'ran' : 'denied'}.',
    ]);
    return 'end_turn';
  },

  // A command as Claude's adapter runs one.
  'bash': (turn) => _claudeBash(turn),

  // The same, waiting for two messages steered in (CHD-467).
  'bashtwo': (turn) => _claudeBash(turn, 2),

  // As `bash`, waiting for one held message (CHD-399).
  'bashone': (turn) => _claudeBash(turn, 1),

  // A turn Claude's adapter ends with a command still running and a call
  // that never ran.
  'bashcut': (turn) async {
    final command = turn.callId('bash');
    final read = turn.callId('read');
    final takes = clientTerminalOutput != 'none';
    final terminal = [
      {'type': 'terminal', 'terminalId': command},
    ];
    Update unfinished(String toolCallId, String text, bool exits) => {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'failed',
      'content': [_text(text)],
      if (exits && takes)
        '_meta': {
          'terminal_exit': {
            'terminal_id': command,
            'exit_code': null,
            'signal': null,
          },
        },
    };

    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': command,
      'title': '`bun test`',
      'kind': 'execute',
      'status': 'pending',
      'rawInput': {'command': 'bun test'},
      'content': takes ? terminal : <Object?>[],
      if (takes)
        '_meta': {
          'terminal_info': {'terminal_id': command},
        },
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': command,
      'status': 'in_progress',
    });
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': read,
      'title': 'Read package.json',
      'kind': 'read',
      'status': 'pending',
      'locations': [
        {'path': 'package.json'},
      ],
    });
    try {
      // Long enough to press Esc while the command runs.
      await pause(turn.signal, _shellStepMs * 20);
    } catch (_) {
      for (final update in [
        unfinished(
          command,
          'The turn was cancelled before this tool call returned a result.',
          true,
        ),
        unfinished(read, 'Claude stopped this tool call before it ran.', false),
      ]) {
        await turn.client.notify('session/update', {
          'sessionId': turn.sessionId,
          'update': update,
        });
      }
      rethrow;
    }
    await turn.send(
      unfinished(
        command,
        'Claude ended the turn without returning a result for this tool.',
        true,
      ),
    );
    await turn.send(
      unfinished(read, 'Claude stopped this tool call before it ran.', false),
    );
    await turn.say(['The tests did not report.']);
    return 'end_turn';
  },
};
