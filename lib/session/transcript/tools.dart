/// A tool call, merged from its `tool_call` and every update to it.
library;

import 'dart:collection';

import '../../acp/schema.dart' as acp;
import '../terminal_text.dart';
import 'entries.dart';
import 'types.dart';

/// The `_meta` key an enricher files an MCP call's server, tool and
/// arguments under.
const mcpCallKey = 'chord/mcp';

/// The `_meta` key an enricher files a Codex Guardian review's status under.
const guardianReviewKey = 'chord/guardian';

const _statusOrder = {
  'pending': 0,
  'in_progress': 1,
  'completed': 2,
  'failed': 2,
};

/// Updates can arrive late, twice, or before their call: a status only
/// moves forward, and once a call has finished nothing moves it back.
String? nextStatus(String? current, String? incoming) {
  if (incoming == null || current == null) {
    return incoming ?? current;
  }

  final from = _statusOrder[current];
  final to = _statusOrder[incoming];

  if (from == null || to == null) {
    return incoming;
  }

  return from == 2 || to < from ? current : incoming;
}

/// [state] with a `tool_call` or `tool_call_update` merged into the latest
/// call of its id, or appended as a new call under [turnId]; throws where
/// the update is malformed.
Transcript mergeToolCall(
  Transcript state,
  String turnId,
  acp.SessionUpdate update,
) {
  // A `tool_call` reads as an update does: every field but the id may be
  // left out, and what is left out is kept.
  final incoming = update as acp.ToolCallUpdate;
  final id = incoming.toolCallId;
  final index = state.entries.lastIndexWhere(
    (entry) => entry is ToolEntry && entry.call.id == id,
  );
  final found = index < 0 ? null : state.entries[index] as ToolEntry;
  final before = found?.call ?? ToolCall(id);
  final title = incoming.title;
  final kind = incoming.toolKind;
  final locations = incoming.locations;
  final content = incoming.content;
  final meta = _record(update.toJson()['_meta']);
  final guardian = meta[guardianReviewKey];
  final json = update.toJson();

  checkLocations(locations);
  checkContent(content);

  final call = ToolCall(
    id,
    title: title == null || title.isEmpty ? before.title : title,
    kind: kind == null || kind.isEmpty ? before.kind : kind,
    status: nextStatus(before.status, incoming.status),
    locations: locations == null
        ? before.locations
        : UnmodifiableListView(locations),
    content: content == null ? before.content : UnmodifiableListView(content),
    rawInput: json.containsKey('rawInput') ? json['rawInput'] : before.rawInput,
    rawOutput: json.containsKey('rawOutput')
        ? json['rawOutput']
        : before.rawOutput,
    guardian: guardian is String ? guardian : before.guardian,
    mcp: _mcpOf(meta) ?? before.mcp,
    review: before.review,
    terminals: foldTerminals(before.terminals, content, meta),
    plan: before.plan,
    asked: before.asked,
    chord: before.chord,
    cut: _cutOf(meta) || before.cut,
  );

  return state.withEntries(
    found == null
        ? appended(state.entries, [ToolEntry(turnId, call)])
        : replacedAt(state.entries, index, ToolEntry(found.turnId, call)),
  );
}

/// Whether the update says the agent cut the call off before it ran:
/// Claude's adapter marks one a steer interrupted
/// `_meta.claudeCode.nonExecutionKind` `interrupted`.
bool _cutOf(Map<String, Object?> meta) =>
    _record(meta['claudeCode'])['nonExecutionKind'] == 'interrupted';

// The views read lazily: what the transcript keeps and the screens read is
// read here, inside the reducer's catch, so a malformed item never reaches
// state. A kind chord does not know is kept as it came.

/// Reads every field the screens read of [locations]; throws where one is
/// malformed.
void checkLocations(List<acp.ToolCallLocation>? locations) {
  for (final location in locations ?? const <acp.ToolCallLocation>[]) {
    (location.path, location.line);
  }
}

/// Reads every field the screens read of [content]'s text and diffs;
/// throws where one is malformed.
void checkContent(List<acp.ToolCallContent>? content) {
  for (final item in content ?? const <acp.ToolCallContent>[]) {
    if (item.content case final block?) {
      (block.type, block.text);
    }
    if (item.diff case final diff?) {
      (diff.path, diff.oldText, diff.newText);
    }
    if (item.type == 'terminal') {
      item.toJson()['terminalId'] as String;
    }
  }
}

/// The terminal fields of a tool call's `_meta`, as Codex's and Claude's
/// adapters send them; ACP v1 has no field of its own for a terminal's
/// output. Each is read alone, so one that is malformed leaves the rest.
({String id, String? cwd})? _info(Object? value) {
  final record = _record(value);
  final id = record['terminal_id'];
  final cwd = record['cwd'];

  return id is String && (cwd is String || !record.containsKey('cwd'))
      ? (id: id, cwd: cwd as String?)
      : null;
}

({String id, String data})? _output(Object? value) {
  final record = _record(value);
  final id = record['terminal_id'];
  final data = record['data'];

  return id is String && data is String ? (id: id, data: data) : null;
}

({String id, num? code, String? signal})? _exit(Object? value) {
  final record = _record(value);
  final id = record['terminal_id'];
  final code = record['exit_code'];
  final signal = record['signal'];

  // The agent's number, carried unchanged; one that is no finite number
  // makes the key malformed, and it alone is left out.
  if (id is! String || (code != null && (code is! num || !code.isFinite))) {
    return null;
  }
  if (signal != null && signal is! String) return null;

  return (id: id, code: code as num?, signal: signal as String?);
}

/// [terminals] with what an update says of them: a terminal its [content]
/// or `terminal_info` names, its output grown by `terminal_output_delta` or
/// replaced by `terminal_output`, and its end by `terminal_exit`, in that
/// order, as an update may carry the last output and the exit together.
/// Read whatever chord declared, as the original does. Null while no
/// terminal was ever named; the identical list when nothing changed.
List<Terminal>? foldTerminals(
  List<Terminal>? terminals,
  List<acp.ToolCallContent>? content,
  Map<String, Object?> meta,
) {
  final info = _info(meta['terminal_info']);
  final delta = _output(meta['terminal_output_delta']);
  // Read as the whole output, as Claude's adapter means it; droid and pi
  // send a delta under this name, which then replaces what was there, one
  // reading for every agent, as the original keeps.
  final whole = _output(meta['terminal_output']);
  final exit = _exit(meta['terminal_exit']);
  var folded = terminals;

  void change(String id, Terminal Function(Terminal terminal) next) {
    final list = folded ?? const <Terminal>[];
    final index = list.indexWhere((terminal) => terminal.id == id);
    final changed = next(index < 0 ? Terminal(id) : list[index]);

    folded = UnmodifiableListView([
      for (final (at, each) in list.indexed) at == index ? changed : each,
      if (index < 0) changed,
    ]);
  }

  for (final item in content ?? const <acp.ToolCallContent>[]) {
    if (item.type == 'terminal') {
      change(item.toJson()['terminalId'] as String, (terminal) => terminal);
    }
  }

  if (info != null) {
    change(
      info.id,
      (terminal) =>
          info.cwd == null ? terminal : _terminal(terminal, cwd: info.cwd),
    );
  }

  if (whole != null) {
    // What it replaces goes whole, with its cursor, its open escape and
    // whatever was cut from it.
    change(
      whole.id,
      (terminal) => _written(terminal, TerminalText.empty, whole.data),
    );
  }

  if (delta != null) {
    change(
      delta.id,
      (terminal) => _written(terminal, _textOf(terminal), delta.data),
    );
  }

  if (exit != null) {
    change(
      exit.id,
      (terminal) => _terminal(
        terminal,
        exited: true,
        exitCode: exit.code,
        signal: exit.signal == null ? null : plainText(exit.signal!),
      ),
    );
  }

  return folded;
}

TerminalText _textOf(Terminal terminal) => TerminalText(
  terminal.output,
  cursor: terminal.cursor,
  escape: terminal.escape,
  truncated: terminal.truncated,
);

/// [terminal] with [data] written over [text], its own output so far or
/// none: only the last [outputLimit] characters stay.
Terminal _written(Terminal terminal, TerminalText text, String data) {
  final next = writeText(text, data, outputLimit);

  return Terminal(
    terminal.id,
    output: next.output,
    cursor: next.cursor,
    escape: next.escape,
    cwd: terminal.cwd,
    exited: terminal.exited,
    exitCode: terminal.exitCode,
    signal: terminal.signal,
    truncated: next.truncated,
  );
}

/// [terminal] with the fields given instead.
Terminal _terminal(
  Terminal terminal, {
  String? cwd,
  bool? exited,
  num? exitCode,
  String? signal,
}) => Terminal(
  terminal.id,
  output: terminal.output,
  cursor: terminal.cursor,
  escape: terminal.escape,
  cwd: cwd ?? terminal.cwd,
  exited: exited ?? terminal.exited,
  exitCode: exitCode ?? terminal.exitCode,
  signal: signal ?? terminal.signal,
  truncated: terminal.truncated,
);

Map<String, Object?> _record(Object? value) =>
    value is Map<String, Object?> ? value : const {};

/// The MCP call chord's enrichers filed under the update's `_meta`, if any.
McpCall? _mcpOf(Map<String, Object?> meta) {
  final filed = _record(meta[mcpCallKey]);
  final tool = filed['tool'];

  if (tool is! String) {
    return null;
  }

  final server = filed['server'];

  return McpCall(
    tool,
    filed['arguments'],
    server: server is String ? server : null,
  );
}
