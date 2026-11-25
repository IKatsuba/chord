import 'package:chord_tui/chord_tui.dart'
    show cellWidth, truncate, KeyCombo, Binding, VimMode;

import '../../notify.dart' show InputAsk;
import '../../session/elapsed.dart';
import '../../session/waits.dart';
import '../../session/transcript/types.dart';
import '../agents/glyphs.dart';
import '../shortcuts/keys.dart' show shortcuts;

/// Semantic tones resolved by the status widgets.
enum StatusTone {
  plain,
  plan,
  edits,
  auto,
  bypass,
  low,
  waits,
  bash,
  failed,

  /// An agent of the window that exited or failed, as the list marks it.
  ended,
}

/// One independently styled fact on the status line.
class StatusPart {
  const StatusPart(this.text, [this.tone = StatusTone.plain]);
  final String text;
  final StatusTone tone;
}

/// How the line marks each of vim's modes.
const vimMarks = {
  VimMode.insert: '-- INSERT --',
  VimMode.normal: '-- NORMAL --',
};

/// Read-only facts reported by the agent and an optional notice.
class StatusFacts {
  const StatusFacts({
    this.model,
    this.effort,
    this.mode,
    this.modeName,
    this.usage,
    this.notice,
    this.failed = false,
    this.hint,
    this.cycleKey,
    this.waits,
    this.bash = false,
    this.vim,
  });
  final bool bash;

  /// Vim mode's mark, first on the left while `/vim` has it on.
  final String? vim;
  final String? model;
  final String? effort;
  final String? mode;
  final String? modeName;
  final Usage? usage;
  final String? notice;
  final bool failed;

  /// A discoverability hint, below a reported mode in priority.
  final String? hint;

  /// The active mode-cycle key, absent when no mode change is available.
  final String? cycleKey;
  final WaitsNotice? waits;
}

/// A request's notice and its shorter words when the status row is tight.
class WaitsNotice {
  const WaitsNotice(
    this.text,
    this.short, {
    this.key,
    this.answer = false,
    this.tone = StatusTone.waits,
  });
  final String text;
  final String short;
  final String? key;
  final bool answer;
  final StatusTone tone;
}

/// The front session's request between turns, still without the keys.
WaitsNotice betweenNotice(String on, String? key) =>
    WaitsNotice('● $on asked between turns', '● $on', key: key, answer: true);

/// One of the window's agents not shown, by its own name: `docs`, or
/// `main` while a child is picked.
typedef AgentWaiting = ({String name, AgentWait wait});

/// A failure's words after a name, `parser's turn failed`.
String _failedNamed(Failure failure, String name) => switch (failure) {
  Failure.exited => '$name exited',
  Failure.start => '$name failed to start',
  Failure.turn => "$name's turn failed",
};

/// A failure's words in a count, `2 turns failed`.
String _failedCounted(Failure failure, int count) => switch (failure) {
  Failure.exited => '$count exited',
  Failure.start => '$count failed to start',
  Failure.turn => '$count ${count == 1 ? 'turn' : 'turns'} failed',
};

/// The notice for the window's agents not shown, [key] the one bound to
/// `session:attention`; none when none wants the person. A permission or
/// form outranks a failure; within each, the one waiting longest is named,
/// or the count once there are more. A reply says nothing here, as the
/// list under the prompt shows it. Many failures count each kind on its
/// own, gravest first, so an agent still open is never said to have ended.
/// One waiting on a task of its own is named by the task, as [taskOf] gives
/// it as the task's box names it, `Agent(Fix the tokenizer) · fake`; where
/// that does not fit, by whose task it is.
WaitsNotice? agentsWaitsNotice(
  List<AgentWaiting> agents,
  String? key, {
  String? Function(AgentWaiting agent)? taskOf,
}) {
  List<AgentWaiting> oldest(num? Function(AgentWaiting agent) since) => [
    for (final agent in agents)
      if (since(agent) != null) agent,
  ]..sort((a, b) => since(a)!.compareTo(since(b)!));
  final asking = oldest((agent) => agent.wait.asking?.since);
  final failed = oldest(
    (agent) => agent.wait.unseen?.kind == UnseenKind.failed
        ? agent.wait.unseen!.since
        : null,
  );
  WaitsNotice notice(String text, StatusTone tone) =>
      WaitsNotice(text, text, key: key, tone: tone);
  final asked = WaitGlyph.asking.glyph, gone = WaitGlyph.failed.glyph;
  if (asking.isNotEmpty) {
    if (asking.length > 1) {
      return notice('$asked ${asking.length} agents wait', StatusTone.waits);
    }
    final first = asking.first;
    final does = first.wait.asking!.on is InputAsk
        ? 'asks for input'
        : 'needs your permission';
    // A task by the name its box gives it, which may be long: where that
    // does not fit, by whose task it is.
    final task = taskOf?.call(first);
    return task == null
        ? notice('$asked ${first.name} $does', StatusTone.waits)
        : WaitsNotice(
            '$asked $task $does',
            "$asked ${first.name}'s task $does",
            key: key,
          );
  }
  if (failed.length > 1) {
    final counts = [
      for (final failure in Failure.values)
        if (failed.where((agent) => failureOf(agent.wait) == failure).length
            case final count when count > 0)
          _failedCounted(failure, count),
    ];
    return notice('$gone ${counts.join(' · ')}', StatusTone.ended);
  }
  if (failed.isEmpty) return null;
  final ended = failed.single;
  return notice(
    '$gone ${_failedNamed(failureOf(ended.wait) ?? Failure.turn, ended.name)}',
    StatusTone.ended,
  );
}

/// A notice's words, retaining the answer verb even in the short form.
List<StatusPart> waitsParts(WaitsNotice waits, bool wide) => [
  StatusPart(
    (wide ? waits.text : waits.short) +
        (waits.key == null
            ? ''
            : '$statusSeparator${waits.key}${waits.answer
                  ? ' to answer'
                  : wide
                  ? ' to go'
                  : ''}'),
    waits.tone,
  ),
];

/// The two sides selected to fit a single status row.
class StatusLineView {
  const StatusLineView(this.left, this.right);
  final List<StatusPart> left;
  final List<StatusPart> right;
}

/// Separates model, effort and context usage.
const statusSeparator = ' · ';

/// The note while ctrl+c holds a draft, the original's `DRAFT_HELD`.
const draftHeldNote = 'The prompt holds a draft · ctrl+c clears it';

/// Context used, as the complement of free context rounded down.
int contextUsed(Usage usage) {
  if (usage.size <= 0) return 100;
  final left = ((usage.size - usage.used) / usage.size) * 100;
  return 100 - left.floor().clamp(0, 100);
}

/// Whether the context figures are chord's estimate, from the model's
/// window or the turn's tokens, rather than what the agent said.
bool contextEstimated(Usage usage) =>
    usage.estimated.any((field) => field != 'cost');

/// The mark ahead of a figure chord worked out itself.
const estimateMark = '~';

/// Claude's known mode wording, or the agent's own name in plain tone.
StatusPart? modePart(String mode, [String? name]) => switch (mode) {
  'default' => null,
  'plan' => const StatusPart('⏸ plan mode on', StatusTone.plan),
  'acceptEdits' => const StatusPart('⏵⏵ accept edits on', StatusTone.edits),
  'auto' => const StatusPart('⏵⏵ auto mode on', StatusTone.auto),
  'bypassPermissions' => const StatusPart(
    '⏵⏵ bypass permissions on',
    StatusTone.bypass,
  ),
  _ => StatusPart(
    '⏵⏵ ${(name == null || name.isEmpty ? mode : name).toLowerCase()} mode on',
  ),
};

List<StatusPart> _right(
  StatusFacts facts,
  bool short,
  String? model,
  String? effort,
) => [
  if (model != null && model.isNotEmpty) StatusPart(model),
  if (effort != null && effort.isNotEmpty)
    StatusPart(short ? effort : '$effort effort'),
  if (facts.usage case final usage? when usage.size > 0)
    StatusPart(
      '${contextEstimated(usage) ? estimateMark : ''}'
      '${contextUsed(usage)}% ${short ? 'used' : 'context used'}',
      contextUsed(usage) > 80 ? StatusTone.low : StatusTone.plain,
    ),
];

/// The cell width of joined status parts.
int partsWidth(List<StatusPart> parts, [String separator = statusSeparator]) =>
    cellWidth(parts.map((part) => part.text).join(separator));

bool _fits(List<StatusPart> left, List<StatusPart> right, int width) =>
    partsWidth(left, ' ') +
        (left.isNotEmpty && right.isNotEmpty ? 2 : 0) +
        partsWidth(right) <=
    width;

/// Shorten the notice before cutting the model; retain the key to answer.
StatusLineView statusLine(StatusFacts facts, int width) {
  final mode = facts.mode == null
      ? null
      : modePart(facts.mode!, facts.modeName);
  final noticed = facts.notice != null && facts.notice!.isNotEmpty;
  final bases = <({List<StatusPart> parts, bool cut})>[
    if (noticed)
      (
        parts: [
          StatusPart(
            facts.notice!,
            facts.failed ? StatusTone.failed : StatusTone.plain,
          ),
        ],
        cut: true,
      )
    else if (facts.bash)
      (parts: [const StatusPart('! for bash mode', StatusTone.bash)], cut: true)
    else if (mode != null) ...[
      if (facts.cycleKey != null)
        (parts: [mode, StatusPart('(${facts.cycleKey} to cycle)')], cut: false),
      (parts: [mode], cut: true),
    ] else ...[
      if (facts.hint != null && facts.hint!.isNotEmpty)
        (parts: [StatusPart(facts.hint!)], cut: true),
      (parts: [], cut: true),
    ],
  ];
  final waits = facts.waits;
  final sides = <({List<StatusPart> parts, bool cut})>[
    for (final base in bases)
      if (waits != null && !noticed)
        for (final wide in [true, false])
          (
            parts: [
              ...waitsParts(waits, wide),
              if (base.parts.isNotEmpty) ...[
                const StatusPart('·'),
                ...base.parts,
              ],
            ],
            cut:
                base.cut &&
                !wide &&
                !base.parts.any((p) => p.text == facts.hint),
          )
      else
        base,
  ];
  // Vim's mark, ahead of whatever else the line says, so the mode the
  // keys are in is never the part that goes.
  if (facts.vim case final mark?) {
    for (var i = 0; i < sides.length; i++) {
      sides[i] = (
        parts: [StatusPart(mark), ...sides[i].parts],
        cut: sides[i].cut,
      );
    }
  }
  for (final side in sides) {
    final found = _shortened(facts, side.parts, side.cut, width);
    if (found != null) return found;
  }
  final left = sides.last.parts;
  final right = _right(facts, true, null, null);
  while (left.isNotEmpty && right.isNotEmpty && !_fits(left, right, width)) {
    right.removeLast();
  }
  return StatusLineView(left, right);
}

StatusLineView? _shortened(
  StatusFacts facts,
  List<StatusPart> left,
  bool cut,
  int width,
) {
  for (final (short, effort) in [
    (false, facts.effort),
    (true, facts.effort),
    (true, null),
  ]) {
    final right = _right(facts, short, facts.model, effort);
    if (_fits(left, right, width)) return StatusLineView(left, right);
  }
  final model = facts.model;
  if (cut && model != null && model.isNotEmpty) {
    final bare = _right(facts, true, null, null);
    final room =
        width -
        partsWidth(left, ' ') -
        (left.isEmpty ? 0 : 2) -
        partsWidth(bare) -
        (bare.isEmpty ? 0 : statusSeparator.length);
    if (room >= 6) {
      return StatusLineView(
        left,
        _right(
          facts,
          true,
          truncate(model, room, preferTruncationOnSpace: true),
          null,
        ),
      );
    }
  }
  return null;
}

/// The current wait and elapsed time displayed above the prompt.
class WorkingLine {
  const WorkingLine(this.label, this.detail);
  final String label;
  final String detail;
}

/// The running turn's wording, [compacting] when the agent compacts the
/// conversation within the turn, or the wait on a form or link [input]
/// asked at its `at`; no line while idle with nothing asked.
WorkingLine? workingLine(
  TurnState turn,
  num now, {
  String? cancelKey = 'esc',
  bool plan = false,
  bool compacting = false,
  ({num? at})? input,
}) {
  // A plan shown says so, even with a later permission waiting behind it.
  if (plan) {
    final since = switch (turn) {
      Idle() => now,
      Cancelling(:final since) ||
      AwaitingPermission(:final since) ||
      Working(:final since) => since,
    };
    return WorkingLine(
      'Waiting for your answer to the plan…',
      formatElapsed(now - since),
    );
  }
  // A form or link waits on the person: Esc answers it rather than
  // interrupting the turn, and its time counts from when it was asked.
  if (input != null && turn is! AwaitingPermission && turn is! Cancelling) {
    return WorkingLine(
      'Waiting for your input…',
      formatElapsed(
        now -
            (input.at ??
                switch (turn) {
                  Working(:final since) => since,
                  _ => now,
                }),
      ),
    );
  }
  return switch (turn) {
    Idle() => null,
    Cancelling(:final since) => WorkingLine(
      'Interrupting…',
      formatElapsed(now - since),
    ),
    AwaitingPermission(:final since, :final permissions) => WorkingLine(
      // chord's own question asks no permission.
      permissions.isNotEmpty && permissions.first.save != null
          ? 'Waiting for you…'
          : 'Waiting for permission…',
      permissions.isNotEmpty && permissions.first.deadlineAt != null
          ? '${formatElapsed(now - (permissions.first.at ?? since))} · denied in ${formatElapsed(permissions.first.deadlineAt! - now)}'
          : formatElapsed(now - since),
    ),
    Working(:final since) => WorkingLine(
      compacting ? 'Compacting conversation…' : 'Working…',
      '${formatElapsed(now - since)}${cancelKey == null ? '' : ' · $cancelKey to interrupt'}',
    ),
  };
}

/// The spinner lights each of three marks, then rests.
const spinnerSteps = 4;

/// A spinner's color source, optionally with a light-to-dark gradient.
class MarkTones {
  const MarkTones({this.tone, this.stops});
  final String? tone;
  final List<String>? stops;
}

/// A single spinner mark's color and dimness.
class SpinnerMark {
  const SpinnerMark(this.colour, this.dim);
  final String? colour;
  final bool dim;
}

/// Three marks at a frame, using a gradient when the theme supplies one.
List<SpinnerMark> spinnerMarks(int step, [MarkTones? mark]) => [
  for (var i = 0; i < 3; i++)
    if (mark?.stops case final stops?)
      SpinnerMark(stops[i == step % spinnerSteps ? 0 : 2], false)
    else
      SpinnerMark(mark?.tone, i != step % spinnerSteps),
];

/// One follow-up key offered while the leader is pending.
final class LeaderItem {
  const LeaderItem(this.keys, this.words);
  final String keys;
  final String words;
}

/// Held keys and complete follow-up items, reduced to the status width.
final class LeaderLineView {
  const LeaderLineView(this.held, this.items);
  final String held;
  final List<LeaderItem> items;
}

/// Space between held keys and the first possible continuation.
const leaderGap = '  ';

/// The leader line's full cell width, including its wider first gap.
int leaderWidth(LeaderLineView view) => cellWidth(
  '${view.held}$leaderGap${view.items.map((item) => item.words.isEmpty ? item.keys : '${item.keys} ${item.words}').join(statusSeparator)}',
);

/// What the panel says an action does, without its `to` or `for`.
String _doesOf(String action) =>
    (shortcuts
                .where((shortcut) => shortcut.actions.contains(action))
                .firstOrNull
                ?.does ??
            action)
        .replaceFirst(RegExp('^(to|for) '), '');

/// What the status line says after a chord's first keys, [held]: each key
/// that can follow and what it does, from [bindings], by their actions, so
/// a rebound or removed one shows as it is. The code block and what waits
/// come first, then any other in the order bound. Too wide, the line takes
/// shorter words; still too wide, it drops items from its end.
LeaderLineView leaderLine(
  List<KeyCombo> held,
  List<Binding> bindings,
  int width,
) {
  // The key after the held ones that runs each action, the first bound.
  final next = <String, String>{};
  for (final binding in bindings) {
    final id = binding.id;
    if (id == null ||
        !binding.enabled ||
        !binding.chord.startsWith(held) ||
        next.containsKey(id)) {
      continue;
    }
    next[id] = binding.chord.combos.skip(held.length).join(' ');
  }
  List<LeaderItem> items(bool short) => [
    if (next['codeBlock:pick'] case final pick?)
      LeaderItem(pick, short ? 'block' : 'a code block'),
    if (next['session:attention'] case final attention?)
      LeaderItem(attention, short ? 'waits' : 'the one that waits'),
    for (final MapEntry(key: action, value: keys) in next.entries)
      if (action != 'session:attention' && action != 'codeBlock:pick')
        LeaderItem(keys, _doesOf(action)),
    if (!short) const LeaderItem('esc', 'never mind'),
  ];
  final label = '${held.join(' ')} …';
  final full = LeaderLineView(label, items(false));
  if (leaderWidth(full) <= width) return full;
  final short = items(true);
  while (short.isNotEmpty &&
      leaderWidth(LeaderLineView(label, short)) > width) {
    short.removeLast();
  }
  return LeaderLineView(label, short);
}
