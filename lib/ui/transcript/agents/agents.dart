/// A subagent's block, and subagents spawned back to back as one tree, from
/// the original's `ui/transcript/agents/Agents.tsx`: what
/// `agents/subagents.dart` reads of them, drawn.
library;

import 'package:chord_tui/chord_tui.dart';

import '../../../session/transcript/types.dart' as model;
import '../../app/context.dart' show hintKeyOf;
import '../../plan/plan.dart' show PlanRecord;
import '../gap.dart';
import '../tools/tool.dart';
import '../tools/tools.dart';
import '../selection.dart' show selectionChild, selectionChildOrNull, workKey;
import '../transcript.dart' show TranscriptEntry;
import 'subagents.dart';

List<model.PermissionWait> _waitsOf(model.TurnState turn) =>
    turn is model.AwaitingPermission ? turn.permissions : const [];

/// The picked code block and a block's copy and run, handed down to work.
typedef _Code = ({
  CodeBlockId? selected,
  void Function(MarkdownCodeBlock block)? copy,
  void Function(MarkdownCodeBlock block)? run,
});

const _Code _noCode = (selected: null, copy: null, run: null);

/// Furniture a selection passes over.
Widget _off(Widget child) => SelectionContainer.disabled(child: child);

/// One subagent's block, or a group of them as a tree.
class Agents extends StatelessWidget {
  const Agents(
    this.agents, {
    super.key,
    required this.turn,
    required this.open,
    this.agent,
    this.selectionSource,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
  });

  final List<model.Subagent> agents;
  final model.TurnState turn;

  /// ctrl+o's view: each one's task and work, whole.
  final bool open;

  /// The agent as the window names it.
  final String? agent;

  /// The group's entry source, whose titles and tasks select; none draws
  /// the whole of it unselectable.
  final SelectionSource? selectionSource;

  /// The code block picked, and what a block's copy and run do, for the
  /// replies in the agents' work, as the session's own have them.
  final CodeBlockId? selectedCodeBlock;
  final void Function(MarkdownCodeBlock block)? onCopyCodeBlock;
  final void Function(MarkdownCodeBlock block)? onRunCodeBlock;

  @override
  Widget build(BuildContext context) {
    final source = selectionSource;
    final code = (
      selected: selectedCodeBlock,
      copy: onCopyCodeBlock,
      run: onRunCodeBlock,
    );
    final drawn = agents.length == 1
        ? _AgentBlock(
            agents.single,
            turn: turn,
            open: open,
            agent: agent,
            source: source,
            code: code,
          )
        : _AgentGroup(
            agents,
            turn: turn,
            open: open,
            agent: agent,
            source: source,
            code: code,
          );
    return source == null ? _off(drawn) : drawn;
  }
}

class _WorkLineText extends StatelessWidget {
  const _WorkLineText(this.line);
  final WorkLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (line.reviewing) {
      return Text(guardianReviewing, style: theme.dim, softWrap: false);
    }
    return Text.rich(
      TextSpan(
        '',
        style: line.failed ? theme.error : null,
        children: [
          headlineSpan(line.headline),
          if (line.waiting) TextSpan(waitingNote, style: theme.dim),
        ],
      ),
      softWrap: false,
      maxLines: 1,
    );
  }
}

class _EndNote extends StatelessWidget {
  const _EndNote(this.subagent);
  final model.Subagent subagent;

  @override
  Widget build(BuildContext context) {
    final note = endNote(subagent);
    if (note == null) return const SizedBox();
    final theme = Theme.of(context);
    return Under(
      first: false,
      child: Text.ansi(note.text, style: note.failed ? theme.error : theme.dim),
    );
  }
}

class _Task extends StatelessWidget {
  const _Task(this.subagent, this.source);
  final model.Subagent subagent;
  final SelectionSource? source;

  @override
  Widget build(BuildContext context) {
    final task = taskOf(subagent);
    final bound = source == null
        ? null
        : selectionChildOrNull(source!, ('agent-task', subagent.id));
    return task == null
        ? const SizedBox()
        : Under(
            first: true,
            child: bound == null
                ? _off(Text.ansi(task))
                : Text.fromSelectionSource(bound),
          );
  }
}

/// A subagent's work as its open block draws it, its calls whole: what
/// the background's detail of a task follows.
class AgentWork extends StatelessWidget {
  /// [subagent]'s work, its calls' waiting read from its owner's [turn],
  /// drawn as [agent]'s.
  const AgentWork(this.subagent, {super.key, required this.turn, this.agent});

  final model.Subagent subagent;
  final model.TurnState turn;
  final String? agent;

  @override
  Widget build(BuildContext context) =>
      _off(_Work(subagent, turn: turn, code: _noCode, agent: agent));
}

class _Work extends StatelessWidget {
  const _Work(
    this.subagent, {
    required this.turn,
    required this.code,
    this.agent,
    this.source,
  });
  final _Code code;
  final model.Subagent subagent;
  final model.TurnState turn;
  final String? agent;

  /// The group's source, holding each item's own where it could.
  final SelectionSource? source;

  @override
  Widget build(BuildContext context) {
    // A task whose record has gone says so where its work would be.
    if (subagent.task?.workLost ?? false) {
      return Text(workLostNote, style: Theme.of(context).dim);
    }
    bool asks(String callId) => _waitsOf(turn).any(
      (wait) => wait.toolCallId == callId && wait.subagentId == subagent.id,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final item in workOf(subagent)) _item(item, asks: asks)],
    );
  }

  Widget _item(WorkItem item, {required bool Function(String) asks}) {
    final bound = source == null
        ? null
        : selectionChildOrNull(source!, workKey(subagent, item));
    final drawn = switch (item) {
      WorkPlan(:final entries) => PlanRecord(entries, selectionSource: bound),
      WorkAgents(:final agents) => Agents(
        agents,
        turn: turn,
        open: false,
        agent: agent,
        selectionSource: bound,
        selectedCodeBlock: code.selected,
        onCopyCodeBlock: code.copy,
        onRunCodeBlock: code.run,
      ),
      WorkEntry(entry: model.ToolEntry(:final call)) => Tool(
        call,
        expanded: true,
        // A call still asked about waits on the person, whether or not
        // the subagent's own work has ended.
        ended: endingOf(subagent.state) != null && !asks(call.id),
        asked: asks(call.id),
        agent: agent,
        selectionSource: bound,
      ),
      WorkEntry(:final entry) => TranscriptEntry(
        entry,
        expanded: true,
        agent: agent,
        selectionSource: bound,
        selectedCodeBlock: code.selected,
        onCopyCodeBlock: code.copy,
        onRunCodeBlock: code.run,
      ),
    };
    return bound == null ? _off(drawn) : drawn;
  }
}

class _AgentBlock extends StatelessWidget {
  const _AgentBlock(
    this.subagent, {
    required this.turn,
    required this.open,
    this.agent,
    this.source,
    this.code = _noCode,
  });
  final model.Subagent subagent;
  final model.TurnState turn;
  final bool open;
  final String? agent;
  final SelectionSource? source;
  final _Code code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fold = blockFold(subagent, _waitsOf(turn));
    final key = hintKeyOf(context, 'app:toggleTranscript');
    final ended = endedLine(subagent);
    final source = this.source;
    return blockGap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToolMarker(agentTone(subagent.state)),
              Expanded(
                child: source == null
                    ? Text.rich(headlineSpan(agentHeadline(subagent)))
                    : Text.fromSelectionSource(
                        selectionChild(source, 'agent-title'),
                      ),
              ),
            ],
          ),
          if (open) ...[
            _Task(subagent, source),
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: _Work(
                subagent,
                turn: turn,
                agent: agent,
                source: source,
                code: code,
              ),
            ),
            if (ended != null) _off(Outcome(ended.text, failed: ended.failed)),
            _off(_EndNote(subagent)),
          ] else
            for (final row in switch (fold) {
              FoldEnded(:final text, :final failed) => [
                Outcome(text, failed: failed),
                // With no call to carry it, this is all that says what broke.
                if (subagent.addressed &&
                    subagent.state == model.SubagentState.failed)
                  _EndNote(subagent),
              ],
              FoldStarting() => [const Outcome('Initializing…')],
              FoldWork(:final lines, :final more) => [
                for (final (index, line) in lines.indexed)
                  Under(first: index == 0, child: _WorkLineText(line)),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Text(
                      '+$more more tool ${more == 1 ? 'use' : 'uses'}'
                      '${key == null ? '' : ' ($key to expand)'}',
                      style: theme.dim,
                      softWrap: false,
                      maxLines: 1,
                    ),
                  ),
              ],
            })
              _off(row),
        ],
      ),
    );
  }
}

class _AgentGroup extends StatelessWidget {
  const _AgentGroup(
    this.agents, {
    required this.turn,
    required this.open,
    this.agent,
    this.source,
    this.code = _noCode,
  });
  final List<model.Subagent> agents;
  final model.TurnState turn;
  final bool open;
  final String? agent;
  final SelectionSource? source;
  final _Code code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = groupHeader(agents);
    final key = hintKeyOf(context, 'app:toggleTranscript');
    final waits = _waitsOf(turn);
    final source = this.source;
    return blockGap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _off(
            Row(
              children: [
                ToolMarker(header.tone),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      header.text,
                      children: [
                        if (!open && key != null)
                          TextSpan(' ($key to expand)', style: theme.dim),
                      ],
                    ),
                    softWrap: false,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          for (final (index, subagent) in agents.indexed)
            LayoutBuilder(
              builder: (context, constraints) {
                final last = index == agents.length - 1;
                // The row's glyphs take three cells after the block's two.
                final rows = groupRow(subagent, constraints.maxWidth - 5);
                final line = rowLine(subagent, waits);
                final ending = endingOf(subagent.state);
                final under = open
                    ? <Widget>[
                        _Task(subagent, source),
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: _Work(
                            subagent,
                            turn: turn,
                            agent: agent,
                            source: source,
                            code: code,
                          ),
                        ),
                        if (ending != null)
                          _off(
                            Under(
                              first: true,
                              child: Text(
                                ending.word,
                                style: ending.failed ? theme.error : theme.dim,
                              ),
                            ),
                          ),
                        _off(_EndNote(subagent)),
                      ]
                    : <Widget>[
                        Under(
                          first: true,
                          child: switch (line) {
                            RowCall(:final line) => _WorkLineText(line),
                            RowStarting() => Text(
                              'Initializing…',
                              style: theme.dim,
                            ),
                            RowEnded(:final ending) => Text(
                              ending.word,
                              style: ending.failed ? theme.error : theme.dim,
                            ),
                          },
                        ),
                        if (subagent.addressed &&
                            subagent.state == model.SubagentState.failed)
                          _EndNote(subagent),
                      ].map(_off).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (at, runs) in rows.indexed)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Row(
                          children: [
                            Gutter(
                              at > 0
                                  ? (last ? ' ' : '│')
                                  : (last ? '└─' : '├─'),
                              width: 3,
                              style: theme.dim,
                            ),
                            // The title selects; chord's counts after it
                            // do not.
                            if (runs.any((run) => !run.counts))
                              switch (source == null
                                  ? null
                                  : selectionChildOrNull(source, (
                                      'agent-row',
                                      subagent.id,
                                      at,
                                    ))) {
                                final bound? => Text.fromSelectionSource(bound),
                                null => _off(
                                  Text.rich(
                                    rowSpan(runs, counts: false),
                                    softWrap: false,
                                    maxLines: 1,
                                  ),
                                ),
                              },
                            Expanded(
                              child: _off(
                                Text.rich(
                                  rowSpan(runs, counts: true),
                                  softWrap: false,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: _Railed(
                        rail: !last,
                        // The original's left border, in its dim border
                        // colour rather than the dim attribute.
                        style: theme.border,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: under,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// [child] one cell in, with the tree's `│` down its left as tall as it
/// is while [rail], every row of a group but the last's.
class _Railed extends StatelessWidget {
  const _Railed({required this.rail, required this.style, required this.child});
  final bool rail;
  final Style style;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Padding(padding: const EdgeInsets.only(left: 1), child: child),
      if (rail)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 1,
          child: _off(
            LayoutBuilder(
              builder: (context, constraints) => Text(
                List.filled(constraints.maxHeight, '│').join('\n'),
                style: style,
              ),
            ),
          ),
        ),
    ],
  );
}
