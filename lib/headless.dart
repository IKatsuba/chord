/// `chord -p`'s words and shapes: the reply as stdout carries it, the lines
/// stderr says, and the one object `--output-format json` prints. Plain
/// Dart, as the original's src/headless.ts.
library;

import 'dart:convert';

import 'package:chord_tui/chord_tui.dart' show stripAnsi;

import 'acp/connection.dart' show openHeadlessAgent;
import 'acp/schema.dart' as acp;
import 'session/session.dart' show SessionOpener;
import 'session/sign_in.dart';
import 'session/start_failure.dart';
import 'session/starting.dart';
import 'session/oneshot.dart';
import 'session/transcript/types.dart' show TurnAnswered, TurnFailed;
import 'session/turn_costs.dart' show Cost;
import 'session/usage.dart';

/// What `--output-format` takes.
const outputFormats = ['text', 'json'];

/// The prompt with piped input after it, joined as Claude Code joins them
/// for `-p`: a line break between, and either left out when empty.
String joinPiped(String prompt, String? piped) =>
    [prompt, ?piped].where((part) => part.isNotEmpty).join('\n');

/// The reply as stdout carries it: the agent's text without its thinking,
/// and a blank line where a tool call came between two stretches of text,
/// which would otherwise run into one another.
class Reply {
  var _text = '';
  var _broken = false;

  /// Each markdown plan's text as stdout has it, by plan id.
  final _plans = <String, String>{};

  /// Each markdown plan's text as the agent last sent it, by plan id.
  final _latest = <String, String>{};

  /// The reply in order: text as taken, and each plan where it first came.
  final _parts = <Object>[];

  /// The reply as the turn left it, for `--output-format json`, which is
  /// written once at the end: each plan as last sent, rewritten or removed,
  /// where stdout could only keep what it had printed.
  String get text => [
    for (final part in _parts)
      part is String ? part : _latest[(part as _Plan).id] ?? '',
  ].join();

  /// What [update] adds to stdout; empty when it adds nothing.
  String take(acp.SessionUpdate update) {
    final json = update.toJson();
    switch (update.kind) {
      case 'tool_call':
        _broken = _text.isNotEmpty;
        return '';
      case 'plan_update':
        final plan = json['plan'];
        if (plan case {
          'type': 'markdown',
          'planId': final String id,
          'content': final String content,
        }) {
          return _plan(id, content);
        }
        return '';
      case 'plan_removed':
        if (json['planId'] case final String id) _latest.remove(id);
        return '';
      case 'agent_message_chunk':
        final content = json['content'];
        if (content case {
          'type': 'text',
          'text': final String text,
        } when text.isNotEmpty) {
          final added = _add(text);
          _parts.add(added);
          return added;
        }
        return '';
    }
    return '';
  }

  /// A markdown plan is the reply an agent would have sent a client that
  /// takes no plan, but each update carries it whole: stdout gets what it
  /// adds to the plan as printed so far. A plan rewritten from the middle
  /// cannot be taken back off stdout, so it adds nothing there.
  String _plan(String id, String content) {
    final printed = _plans[id];
    if (printed == null && content.isEmpty) return '';
    _latest[id] = content;
    if (printed == null) {
      final added = _add(content);
      _plans[id] = content;
      // The break before the plan, if a tool call came first.
      _parts
        ..add(added.substring(0, added.length - content.length))
        ..add(_Plan(id));
      return added;
    }
    if (!content.startsWith(printed) || content == printed) return '';
    _plans[id] = content;
    return _add(content.substring(printed.length));
  }

  String _add(String text) {
    final added = _broken && !_text.endsWith('\n\n')
        ? '${_text.endsWith('\n') ? '\n' : '\n\n'}$text'
        : text;
    _broken = false;
    _text += added;
    return added;
  }

  /// The line break a reply that stopped mid-line still needs.
  String end() => _text.isEmpty || _text.endsWith('\n') ? '' : '\n';
}

final class _Plan {
  const _Plan(this.id);
  final String id;
}

/// Why the turn did not end as a finished answer; null when it did.
String? failureOf(OneshotOutcome outcome) => switch (outcome.result) {
  TurnFailed(:final message) => message,
  TurnAnswered(cancelled: true) => 'The turn was cancelled.',
  TurnAnswered(:final stopReason) =>
    stopReason == 'end_turn' ? null : 'The agent stopped: $stopReason.',
};

String _clean(String text) =>
    stripAnsi(text).replaceAll(RegExp(r'\s+'), ' ').trim();

/// What stderr says of an agent's notice, one line, so stdout keeps the
/// reply alone: the agent's strings cleaned and each run of whitespace
/// folded, as every agent string chord prints is.
String noticeLine({required String title, String? description}) {
  final detail = description == null || description.isEmpty
      ? ''
      : _clean(description);
  return 'chord: ${_clean(title)}${detail.isEmpty ? '' : ': $detail'}\n';
}

/// A tool call's title, else its id, as the permission lines name it.
String _named(Map<String, Object?> toolCall) =>
    (toolCall['title'] as String?) ?? (toolCall['toolCallId'] as String);

/// What stderr says of a permission nobody was there to answer.
String refusalLine(Map<String, Object?> toolCall) =>
    'chord: refused ${_named(toolCall)}: -p cannot ask for permission.\n';

/// What stderr says of a permission `--dangerously-skip-permissions`
/// allowed.
String allowedLine(Map<String, Object?> toolCall) =>
    'chord: allowed ${_named(toolCall)}.\n';

/// What stderr says of a form nobody was there to fill in, a line per
/// question chord read in it, or one for the form's [message].
String skippedLines(
  String agent, {
  required String message,
  List<String>? questions,
}) => [
  for (final text in questions ?? [message])
    'chord: $agent asked: $text — skipped (no one to answer under -p)\n',
].join();

/// The snake_case names Claude Code's `--output-format json` uses.
Map<String, num> _usageJson(TokenUsage usage) => {
  for (final (from, to) in const [
    ('inputTokens', 'input_tokens'),
    ('outputTokens', 'output_tokens'),
    ('cachedReadTokens', 'cache_read_input_tokens'),
    ('cachedWriteTokens', 'cache_creation_input_tokens'),
    ('thoughtTokens', 'thought_tokens'),
    ('totalTokens', 'total_tokens'),
  ])
    to: ?usage[from],
};

/// The cost, and `cost_estimated` when chord worked it out from the tokens.
Map<String, Object?> _costJson(Cost? cost, bool estimated) => cost == null
    ? const {}
    : {
        if (cost.currency == 'USD')
          'total_cost_usd': cost.amount
        else
          'cost': {'amount': cost.amount, 'currency': cost.currency},
        if (estimated) 'cost_estimated': true,
      };

/// The one object `--output-format json` prints, in the names Claude
/// Code's uses where it has the same thing to say.
Map<String, Object?> resultJson(OneshotOutcome outcome, String text) {
  final failure = failureOf(outcome);
  final result = outcome.result;
  return {
    'type': 'result',
    'is_error': failure != null,
    'result': text,
    'session_id': outcome.sessionId,
    if (result is TurnAnswered) 'stop_reason': result.stopReason,
    if (outcome.usage case final usage?) 'usage': _usageJson(usage),
    ..._costJson(outcome.cost, outcome.costEstimated),
    'error': ?failure,
  };
}

/// `chord -p`: one prompt, the reply on stdout, and the exit code a script
/// reads: 0 only when the agent ended its turn.
Future<int> runHeadless({
  required String agent,
  required Object command,
  Map<String, String> env = const {},
  required String cwd,
  required String prompt,
  required String format,
  StartingValue? effort,
  StartingValue? mode,
  bool allowAll = false,
  required Future<void> Function(String text) stdout,
  required Future<void> Function(String text) stderr,
  SessionOpener open = openHeadlessAgent,
  String? pinned,
  List<Map<String, Object?>> mcpServers = const [],
  bool noMcpServers = false,
}) async {
  final reply = Reply();
  final OneshotOutcome outcome;
  try {
    outcome = await runOneshot(
      agent: agent,
      command: command,
      env: env,
      cwd: cwd,
      prompt: prompt,
      open: open,
      pinned: pinned,
      mcpServers: mcpServers,
      noMcpServers: noMcpServers,
      effort: effort,
      mode: mode,
      allowAll: allowAll,
      onUpdate: (update) async {
        // An agent's notice is chord's line on stderr, in text and JSON,
        // so stdout keeps the reply alone.
        if (update.kind == acp.SessionUpdateKind.notice) {
          final json = update.toJson();
          final title = json['title'];
          if (title is String) {
            await stderr(
              noticeLine(
                title: title,
                description: switch (json['description']) {
                  final String text => text,
                  _ => null,
                },
              ),
            );
          }
          return;
        }
        final added = reply.take(update);
        if (format == 'text' && added.isNotEmpty) await stdout(added);
      },
      // The turn still runs, on the agent's own effort and in its own mode.
      onStartingRefused: (refusal) => stderr('chord: could not $refusal\n'),
      onNotice: (paragraphs) =>
          stderr(paragraphs.map((paragraph) => 'chord: $paragraph\n').join()),
      onRefused: (call) => stderr(refusalLine(call.toJson())),
      onAllowed: (call) => stderr(allowedLine(call.toJson())),
      onDeclined: (form) => stderr(
        skippedLines(
          agent,
          message: form.message,
          questions: form.questions?.questions.map((q) => q.text).toList(),
        ),
      ),
    );
  } catch (error) {
    final failure = startFailureOf(error);
    final signIn = signInOf(error);
    await stderr(
      [
        '$agent did not start: ${stepWords(startMessage(error), failure)}',
        // What chord knows of why, then, for a login, the ways in and on.
        ...failureLines(agent, failure),
        if (signIn != null) ...signInLines(agent, signIn),
      ].map((line) => 'chord: $line\n').join(),
    );
    return 1;
  }

  final failure = failureOf(outcome);
  if (format == 'json') {
    await stdout('${jsonEncode(resultJson(outcome, reply.text))}\n');
  } else {
    await stdout(reply.end());
  }
  if (failure != null) {
    await stderr('chord: $failure\n');
    return 1;
  }
  return 0;
}
