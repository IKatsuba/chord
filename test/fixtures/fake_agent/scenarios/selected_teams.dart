// Fake-only selected compositions travel through the ordinary MCP surface,
// as the original's scenarios/selected_teams.ts.
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../options.dart';
import '../rpc.dart';
import '../turn.dart';
import 'agents.dart';
import 'chord_tools.dart';

/// Fails the turn as the original's `assert` from node:assert/strict does
/// under bun, whose message for a falsy value is `false == true`.
void _check(bool holds) {
  if (!holds) throw StateError('false == true');
}

/// These fixtures follow their fixed saved instructions, never interpret
/// prose.
Future<String> _discoveredTeam(Turn turn, bool select) async {
  final client = await chordClient(turn);
  if (client == null) return 'end_turn';
  try {
    await client.listTools();

    final listed = await callChord(turn, client, 'list_teams', {});
    _check(listed != null);

    final answer = jsonDecode(listed!) as Map;
    Map<Object?, Object?>? definition;
    for (final one in (answer['teams'] as List?) ?? const []) {
      if (one is Map && one['name'] == 'fixture') {
        definition = one;
        break;
      }
    }
    _check(definition != null && definition.containsKey('lead'));

    if (select) {
      await callChord(turn, client, 'list_agents', {});
      final agents = <Object?>{
        (definition!['lead'] as Map)['agent'],
        for (final member in definition['members'] as List)
          (member as Map)['agent'],
      }.toList();
      await callChord(turn, client, 'get_budgets', {'agents': agents});
      await callChord(turn, client, 'get_budgets', {'agents': agents});
    }

    await callChord(turn, client, 'run_team', {
      'team': 'fixture',
      'job': 'selectedidle',
      if (select)
        'selection': {
          'reason':
              'Preserve every saved role, instruction and permission; '
              'capacity is unknown.',
          'lead': {'model': 'fake-small', 'mode': 'plan'},
        },
    });
    await turn.say([
      select
          ? 'Ordinary budget-aware handoff completed.'
          : 'Ordinary saved-composition handoff completed.',
    ]);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> selectedTeams = {
  'budgetawareteam': (turn) => _discoveredTeam(turn, true),
  'savedteamplain': (turn) => _discoveredTeam(turn, false),

  'selectedteam': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return 'end_turn';
    final scenario = environment['CHORD_FAKE_SELECTION_CASE'] ?? 'normal';
    try {
      await callChord(turn, client, 'get_budgets', {});
      await callChord(turn, client, 'run_team', {
        'team': 'fixture',
        'job': scenario == 'members' ? 'selectedlead' : 'selectedidle',
        'selection': {
          'reason': scenario == 'long'
              ? ('Preserve every role instruction and exact permission '
                            'requirement. Capacity is unknown until '
                            'get_budgets is read, and external activity may '
                            'be missing. ' *
                        3)
                    .trim()
              : 'Preserve all instructions and exact permission '
                    'requirements; capacity is unknown.',
          'lead': {
            'agent': const ['refused', 'soft'].contains(scenario)
                ? 'claude'
                : 'codex',
            'model': 'fake-small',
            'mode': 'plan',
            if (scenario == 'soft') 'effort': 'high',
          },
          'members': {
            'reviewer': {'model': 'fake-small', 'mode': 'plan'},
          },
        },
      });
      await turn.say(['Selection attempt recorded; no automatic retry.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  'selectedlate': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return 'end_turn';
    final input = <String, Object?>{
      'team': 'fixture',
      'job': 'selectedidle',
      'selection': {
        'reason':
            'Preserve all instructions and exact permissions; capacity is '
            'unknown.',
        'lead': {'agent': 'codex', 'model': 'fake-small', 'mode': 'plan'},
      },
    };
    final toolCallId = turn.callId('run_team');
    try {
      final abort = mcp.BasicAbortController();
      turn.signal.onAbort(() => abort.abort(turn.signal.reason));
      final pending = asOriginal(
        () => client.callTool(
          mcp.CallToolRequest(name: 'run_team', arguments: input),
          options: mcp.RequestOptions(
            timeout: const Duration(milliseconds: 45000),
            signal: abort.signal,
          ),
        ),
      );
      // Held while the turn says it waits: a failure first must still fail
      // only the await below.
      pending.ignore();

      await turn.say([
        'Selected startup waits for the start gate (bounded to 30 seconds).',
      ]);

      final result = await pending;

      await turn.say([
        'Selected receipt revised; ACP link waits for the link gate (at most '
            '10 seconds).',
      ]);
      await gateOpened(turn, 'link');
      // This is the fake provider's delayed notification for its actual
      // request.
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': toolCallId,
        'title': 'mcp__chord__run_team',
        'kind': 'other',
        'status': 'pending',
        'rawInput': input,
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': toolCallId,
        'status': result.isError ? 'failed' : 'completed',
        'content': [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': stringify(result.structuredContent ?? {}),
            },
          },
        ],
      });
      await turn.say(['Late ACP link completed.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  'selectedlead': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return 'end_turn';
    try {
      await callChord(turn, client, 'open_agent', {
        'member': 'reviewer',
        'prompt': 'selectedidle',
      });
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  'selectedidle': (turn) async {
    await turn.say(['The selected fake role received its first job.']);
    return 'end_turn';
  },
};
