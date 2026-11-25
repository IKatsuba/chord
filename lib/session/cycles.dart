/// An agent's own cycle: work it does with no turn of the person's running,
/// as Claude Code does when a background task ends and codebuddy with its
/// unasked turns. chord knows one only where the agent marks its end.
library;

import '../acp/schema.dart' as acp;

/// The `_claude/origin` kinds of a cycle Claude Code started on its own, as
/// claude-agent-acp 0.107.0 tells its results apart: a usage update of one
/// ends the cycle.
const _autonomousOrigins = {
  'task-notification',
  'peer',
  'coordinator',
  'observer',
  'observer-activity',
};

/// The `_meta` key codebuddy marks an unasked turn's start with.
const _codebuddyStart = 'codebuddy.ai/unsolicitedTurn';

/// The update codebuddy ends an unasked turn with, which ACP does not have.
const _codebuddyEnd = 'session_end';

/// What an update says of a cycle.
enum CycleMark { start, end }

/// What [update] says of a cycle: that one starts (codebuddy's marker) or
/// ends (Claude's autonomous usage, codebuddy's `session_end`); null for
/// every other update.
CycleMark? cycleMark(acp.SessionUpdate update) {
  final kind = update.kind;
  final meta = update.meta;
  if (kind == 'session_info_update' && meta?[_codebuddyStart] != null) {
    return CycleMark.start;
  }
  if (kind == _codebuddyEnd) return CycleMark.end;
  if (kind == 'usage_update') {
    final origin = meta?['_claude/origin'];
    final of = origin is Map ? origin['kind'] : null;
    return of is String && _autonomousOrigins.contains(of)
        ? CycleMark.end
        : null;
  }
  return null;
}

/// The updates that are the agent at work, which start a cycle of Claude's
/// once its last turn has gone quiet; what only reports its state does not.
const cycleWork = {
  'agent_message_chunk',
  'agent_thought_chunk',
  'tool_call',
  'tool_call_update',
  'plan',
};
