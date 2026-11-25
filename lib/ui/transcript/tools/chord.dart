/// chord's own tools as calls, kept out of the widget: a verb in the
/// `Read(path)` style for each, and what was said or answered under `⎿`,
/// read from the request chord served rather than from the adapter's title
/// (`mcp__chord__spawn_task`) or the answer's JSON, which ctrl+o still
/// shows. From the original's `ui/transcript/tools/chord.ts`.
library;

import '../../../session/elapsed.dart';
import '../../../settings.dart' show shownSettingPath;
import '../../../session/monitors.dart' show timeoutWords;
import '../../../session/transcript/types.dart';
import '../message.dart' show messageLines;
import 'resource_lines.dart';
import 'selection_lines.dart';
import 'tools.dart' show Headline;

/// How many names a list of runtimes or models gives before `+N more`.
const _named = 4;

Map<String, Object?> _record(Object? value) =>
    value is Map<String, Object?> ? value : const {};

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// `List agents(codex)`, `→ to @main · queued`, `Agent(name) · codex`; a
/// message's recipient bare, and drawn `@main`.
Headline chordHeadline(ChordCall call) {
  final input = call.input;
  final answer = _record(call.answer);
  // The name chord answered with, whatever the agent called it by.
  final answered =
      _text(answer['name']) ??
      _text(answer['to']) ??
      _text(answer['closed']) ??
      _text(answer['ended']) ??
      _text(answer['cleared']);
  // The effort asked for until chord answers with the one it started on,
  // which a refusal leaves at the runtime's own.
  final effort = call.answer == null
      ? _text(input['effort'])
      : _text(answer['effort']);
  final runtime = [?_text(input['agent']), ?_text(input['model']), ?effort];
  final after = runtime.isEmpty ? null : ' · ${runtime.join(' · ')}';
  // A team agent's runtime, model and mode are its file's, which chord
  // answered with; the mode only on a member's row, where the file set it.
  String? opened(bool mode) {
    final parts = [
      ?_text(answer['agent']),
      ?_text(answer['model']),
      ?_text(answer['effort']),
      if (mode) ?_text(answer['mode']),
    ];
    return parts.isEmpty ? after : ' · ${parts.join(' · ')}';
  }

  return switch (call.tool) {
    ChordTool.getBudgets => const Headline('Resources'),
    ChordTool.listAgents => Headline('List agents', arg: _text(input['agent'])),
    ChordTool.listSessions => const Headline('List sessions'),
    ChordTool.listTeams => const Headline('List teams'),
    // The proposal or change is named once chord has served it.
    ChordTool.proposeTeam => Headline(
      'Team',
      arg: _text(input['name']),
      note: call.answer == null
          ? null
          : answer['proposal'] == 'change'
          ? ' · change'
          : ' · proposal',
    ),
    ChordTool.runTeam => Headline(
      'Team',
      arg: answered ?? _text(input['team']),
      note: opened(false),
    ),
    ChordTool.settings => _settingsHeadline(call),
    ChordTool.spawnTask => Headline(
      'Agent',
      arg: _text(input['name']) ?? _text(input['prompt'])?.split('\n').first,
      note: after,
    ),
    ChordTool.openAgent when _text(input['member']) == null => Headline(
      'Open',
      arg: answered ?? _text(input['name']) ?? _text(input['agent']),
      note: after,
    ),
    ChordTool.openAgent => Headline(
      'Open',
      arg: answered ?? _text(input['member']),
      note: opened(true),
    ),
    ChordTool.sendMessage => Headline(
      answered ?? _text(input['to']) ?? 'main',
      sent: true,
      note: call.queued ? ' · queued' : null,
    ),
    ChordTool.closeAgent => Headline(
      'Close',
      arg: answered ?? _text(input['to']) ?? _text(input['id']),
    ),
    ChordTool.clearAgent => Headline(
      'Clear',
      arg: answered ?? _text(input['to']),
    ),
    ChordTool.monitor => Headline('Monitor', arg: _text(input['description'])),
    ChordTool.stopMonitor => Headline(
      'Stop monitor',
      arg: _text(answer['description']) ?? _text(input['id']),
    ),
    ChordTool.listMonitors => const Headline('List monitors'),
  };
}

/// What a call of chord's that the agent cut off before it reached chord
/// says after its body: that it did nothing, and that chord tells the
/// agent.
String cutLine(ChordTool tool) => tool == ChordTool.sendMessage
    ? 'Not delivered: cut off before it reached chord. chord tells the agent '
          'at its next turn.'
    : 'Cut off before it reached chord, so it did nothing. chord tells the '
          'agent at its next turn.';

/// What a `send_message` sent, as it was sent, so its markdown reads as a
/// received message's does, a leading indent's code block included; none
/// for another call or an empty text.
String? sentText(ChordCall call) {
  final sent = call.tool == ChordTool.sendMessage ? call.input['text'] : null;
  return sent is String && _text(sent) != null ? sent : null;
}

/// `a, b, c, d, +3 more`.
String _names(List<String> all) => [
  ...all.take(_named),
  if (all.length > _named) '+${all.length - _named} more',
].join(', ');

String _plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? [for (final each in value) _record(each)] : const [];

/// The lines under the call, before folding: chord's refusal, what was
/// sent, or what the answer comes to. None while a listing has no answer.
/// A selected run's receipt lines follow its job or its refusal; [expanded]
/// opens its saved definition.
List<String> chordLines(ChordCall call, {bool expanded = false}) {
  if (call.error case final error?) {
    return [
      error,
      if (call.tool == ChordTool.runTeam)
        ...selectionLines(_record(call.answer)['receipt'], expanded: expanded),
    ];
  }
  final input = call.input;
  final answer = _record(call.answer);
  final listing =
      call.tool == ChordTool.getBudgets ||
      call.tool == ChordTool.listAgents ||
      call.tool == ChordTool.listSessions ||
      call.tool == ChordTool.listMonitors ||
      call.tool == ChordTool.listTeams;
  if (listing && call.answer == null) return const [];
  switch (call.tool) {
    case ChordTool.getBudgets:
      return resourceLines(call.answer);
    case ChordTool.listAgents:
      final agents = _rows(answer['agents']);
      if (_text(input['agent']) != null) {
        final row = agents.firstOrNull ?? const <String, Object?>{};
        final models = row['models'];
        return models is List
            ? [
                '${_plural(models.length, 'model', 'models')} · '
                    '${_names([for (final model in models) '${_record(model)['id'] ?? ''}'])}',
              ]
            : [_text(row['note']) ?? 'No models'];
      }
      final runtimes = [for (final row in agents) '${row['name'] ?? ''}'];
      return [
        '${_plural(runtimes.length, 'runtime', 'runtimes')} · '
            '${_names(runtimes)}',
      ];
    case ChordTool.listSessions:
      final sessions = _rows(answer['sessions']);
      // By runtime, and its agents counted.
      return [
        '${sessions.length} open · ${sessions.map((session) {
          final agents = session['agents'];
          final count = agents is List ? agents.length : 0;
          return '${session['runtime']}'
              '${session['you'] == true ? ' (you)' : ''}'
              '${count == 0 ? '' : ', ${_plural(count, 'agent', 'agents')}'}';
        }).join(', ')}',
      ];
    case ChordTool.spawnTask:
      return (_text(input['prompt']) ?? '')
          .split('\n')
          .take(messageLines)
          .toList();
    // Whole, as ctrl+o shows what was handed over; the row folds it. One
    // the person opened with /new was handed nothing.
    case ChordTool.openAgent:
      final typed = _text(input['typed']);
      return typed == null
          ? (_text(input['prompt']) ?? '').split('\n')
          : ['opened with $typed'];
    // Drawn as a table by its own widget once served.
    case ChordTool.proposeTeam:
      return const [];
    case ChordTool.runTeam:
      return [
        ...(_text(input['job']) ?? '').split('\n'),
        ...selectionLines(answer['receipt'], expanded: expanded),
      ];
    case ChordTool.listTeams:
      final teams = [
        for (final team in _rows(answer['teams'])) '${team['name'] ?? ''}',
      ];
      return ['${_plural(teams.length, 'team', 'teams')} · ${_names(teams)}'];
    // None for an empty text, so the row says the call's state instead.
    case ChordTool.sendMessage:
      return _text(input['text'])?.split('\n') ?? const [];
    case ChordTool.closeAgent:
      return [_text(answer['ended']) == null ? 'Closed' : 'Already ended'];
    // Its rows are its own, drawn beside the call.
    case ChordTool.settings:
      return const [];
    // The id it keeps, and the messages to it that were dropped.
    case ChordTool.clearAgent:
      final id = _text(answer['id']);
      return [
        'Fresh session${id == null ? '' : ' · id $id'}',
        ?_text(answer['dropped']),
      ];
    case ChordTool.monitor:
      final (id, timeout) = (answer['id'], answer['timeout_ms']);
      return [
        '\$ ${_text(input['command']) ?? ''}',
        if ((id, timeout) case (final String id, final int timeout))
          '$id · times out after ${timeoutWords(timeout)}',
      ];
    case ChordTool.stopMonitor:
      return switch ((answer['ran_ms'], answer['events'])) {
        (final int ran, final int events) => [
          'Stopped after ${formatElapsed(ran)} · '
              '${events == 0 ? 'no events' : _plural(events, 'event', 'events')}',
        ],
        _ => const [],
      };
    case ChordTool.listMonitors:
      final monitors = _rows(answer['monitors']);
      return monitors.isEmpty
          ? const ['None running']
          : [
              '${monitors.length} running · '
                  '${_names([for (final m in monitors) '${m['description'] ?? ''}'])}',
            ];
  }
}

/// The path a `settings` call asked for, none where an agent sent no list
/// of keys.
List<String> settingsPathOf(ChordCall call) => switch (call.input['path']) {
  final List<Object?> path when path.every((key) => key is String) =>
    path.cast<String>(),
  _ => const [],
};

/// `Settings(path)`, its note named once served: what it did; a refusal
/// has none.
Headline _settingsHeadline(ChordCall call) {
  final path = settingsPathOf(call);
  final answer = _record(call.answer);
  final note = call.input['action'] == 'read'
      ? 'read'
      : answer['unchanged'] == true
      ? 'unchanged'
      : !answer.containsKey('after')
      ? 'remove'
      : !answer.containsKey('before')
      ? 'set'
      : 'change';
  return Headline(
    'Settings',
    arg: path.isEmpty ? null : shownSettingPath(path),
    note: call.answer == null ? null : ' · $note',
  );
}
