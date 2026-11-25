// Compactions as Claude's and Codex's adapters run them, one that fails,
// and Claude's own of an idle session (CHD-624), as the original's
// scenarios/compaction.ts.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../compactions.dart';
import '../client.dart';
import '../options.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';

/// How long a compaction takes between chunks of its summary.
num get _compactStepMs => stepMs * 50;

/// A compaction as both adapters run one: by id to a client that takes
/// it, the [chunks] of its summary streamed, then [ending]; to any other,
/// as the tool call they fall back on.
Future<String> _compact(
  Turn turn,
  List<String> chunks,
  Map<String, Object?> ending,
) async {
  final compactionId = turn.callId('compaction');
  if (!clientTakesCompaction) {
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': compactionId,
      'title': 'Compact conversation',
      'kind': 'think',
      'status': 'in_progress',
    });
    await pause(turn.signal, _compactStepMs * math.max(chunks.length, 4));
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': compactionId,
      'status': ending['status'],
    });
    return 'end_turn';
  }

  await turn.send({
    'sessionUpdate': 'compaction_update',
    'compactionId': compactionId,
    'status': 'in_progress',
  });
  try {
    for (final text in chunks) {
      await pause(turn.signal, _compactStepMs);
      await turn.send({
        'sessionUpdate': 'compaction_summary_chunk',
        'compactionId': compactionId,
        'content': {'type': 'text', 'text': text},
      });
    }
    await pause(turn.signal, _compactStepMs * (chunks.isEmpty ? 8 : 1));
  } catch (_) {
    await turn.client.notify('session/update', {
      'sessionId': turn.sessionId,
      'update': {
        'sessionUpdate': 'compaction_update',
        'compactionId': compactionId,
        'status': 'cancelled',
      },
    });
    rethrow;
  }
  await turn.send({
    'sessionUpdate': 'compaction_update',
    'compactionId': compactionId,
    ...ending,
  });
  return 'end_turn';
}

const _completed = {'status': 'completed'};
const _failed = {'status': 'failed', 'error': compactError};

final Map<String, Play> compaction = {
  'compact': (turn) => _compact(turn, compactSummary, _completed),
  'codexcompact': (turn) => _compact(turn, const [], _completed),
  'compactfail': (turn) => _compact(turn, const [], _failed),
};

/// Longer than chord waits for a turn's tail to go quiet.
const _idleQuiet = 1500;

/// How long an idle compaction runs with no gate to hold it.
const _idleRunMs = 6000;

/// What an idle compaction adds to the session's cost, in USD.
const _idleCompactCost = 0.04;

/// The chunk `idlecompactsays` sends after its compaction, untagged.
const idleChunk = 'Conversation compacted.';

/// Each session's idle compaction while it runs: a prompt waits for it,
/// and a cancel of that prompt cancels it.
final idle = <String, ({Future<void> done, Aborter stop})>{};

/// Waits for [sessionId]'s idle compaction, if one runs, and cancels it if
/// [signal] does first.
Future<void> afterIdleCompaction(String sessionId, Signal signal) async {
  final running = idle[sessionId];
  if (running == null) return;
  final remove = signal.onAbort(running.stop.abort);
  try {
    await running.done;
  } finally {
    remove();
  }
}

/// Holds a running idle compaction: until the gate is released, at most
/// 10 s, where the gate is; else for a while.
Future<void> _held(String sessionId, Signal signal) async {
  final at = p.join(cwds[sessionId] ?? '.', gate);
  if (!Directory(at).existsSync()) {
    await pause(signal, _idleRunMs);
    return;
  }
  final deadline = now() + 10000;
  while (!File(p.join(at, gateRelease)).existsSync() && now() < deadline) {
    await pause(signal, stepMs * 2);
  }
}

/// Ends the turn with a line, then, once it has gone quiet, compacts as
/// claude-agent-acp 0.107 does an idle session.
Play _idleCompact(Map<String, Object?> ending, {bool says = false}) =>
    (turn) async {
      final client = turn.client;
      final sessionId = turn.sessionId;
      Future<void> send(Update update) => client.notify('session/update', {
        'sessionId': sessionId,
        'update': update,
      });

      () async {
        try {
          await turn.over;
          await pause(lifetime.signal, _idleQuiet);
        } catch (_) {
          return;
        }
        final compactionId = const Uuid().v4();
        final stop = Aborter();
        final signal = Signal.any([lifetime.signal, stop.signal]);
        final done = Completer<void>();
        idle[sessionId] = (done: done.future, stop: stop);
        try {
          await send({
            'sessionUpdate': 'compaction_update',
            'compactionId': compactionId,
            'status': 'in_progress',
          });
          try {
            if (ending['status'] == 'completed') {
              for (final text in compactSummary) {
                await send({
                  'sessionUpdate': 'compaction_summary_chunk',
                  'compactionId': compactionId,
                  'content': {'type': 'text', 'text': text},
                });
              }
            }
            await _held(sessionId, signal);
          } catch (_) {
            if (!lifetime.signal.aborted) {
              await send({
                'sessionUpdate': 'compaction_update',
                'compactionId': compactionId,
                'status': 'cancelled',
              });
            }
            return;
          }
          await send({
            'sessionUpdate': 'compaction_update',
            'compactionId': compactionId,
            ...ending,
          });
          if (ending['status'] == 'completed') {
            final cost = (costs[sessionId] ?? costFrom) + _idleCompactCost;
            costs[sessionId] = cost;
            await send({
              'sessionUpdate': 'usage_update',
              'used': 41200,
              'size': 1000000,
            });
            await send({
              'sessionUpdate': 'usage_update',
              'used': 41200,
              'size': 1000000,
              'cost': {'amount': cost, 'currency': 'USD'},
            });
          }
          if (says) {
            await pause(lifetime.signal, 1200);
            await send({
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': idleChunk},
            });
          }
        } catch (_) {
          // The client went first.
        } finally {
          idle.remove(sessionId);
          done.complete();
        }
      }();

      await turn.say(['Done: three tests merged into one table, all green.']);
      return 'end_turn';
    };

final Map<String, Play> idleCompaction = {
  'idlecompact': _idleCompact(_completed),
  'idlecompactfail': _idleCompact(_failed),
  'idlecompactsays': _idleCompact(_completed, says: true),
};
