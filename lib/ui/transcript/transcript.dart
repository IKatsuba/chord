import 'dart:math' as math;
import '../teams/recorded_receipt.dart' show RecordedReceipt, recordedReceipts;
import '../teams/teams_view.dart' show TeamEntry;

import 'package:chord_tui/chord_tui.dart' hide Folded;

import '../agents/agents.dart' show leftOpenLine;
import '../app/context.dart' show hintKeyOf;

import '../../session/transcript/types.dart' as model;
import '../dialogs/form.dart' show AnsweredRow, answeredRows, answeredText;
import '../dialogs/permission.dart';
import '../dialogs/questions.dart' show answeredQuestions, askedHeaders;
import '../../session/questions.dart' show Questions;
import '../app/sign_in.dart' show SignInBlock;
import '../plan/plan.dart';
import 'agent_colours.dart';
import 'gap.dart';
import 'message.dart';
import 'notice.dart';
import 'code_pick.dart' show runnableCodeLanguages;
import 'compaction.dart';
import 'agents/agents.dart';
import 'agents/subagents.dart' show agentGroup;
import '../../session/elapsed.dart';
import '../../session/monitors.dart' show leftRunningLine;
import '../prompt/bash.dart';
import '../theme/theme.dart';
import 'tools/tool.dart';
import 'tools/tools.dart';
import 'tools/paths.dart';
import 'scroll.dart';
import 'state.dart';
import 'selection.dart';

/// One M1 transcript entry other than a tool, drawn from folded state.
class TranscriptEntry extends StatelessWidget {
  /// An entry with the window's detail setting and streaming flag.
  const TranscriptEntry(
    this.entry, {
    super.key,
    this.expanded = false,
    this.growing = false,
    this.selectionSource,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
    this.shellStopKey,
    this.agent,
    this.windowRows = 40,
  });

  /// The agent as the window names it, who asked a form or link.
  final String? agent;

  /// The window's rows, which decide how much `/team show` keeps folded.
  final int windowRows;

  /// The reducer's immutable entry.
  final model.Entry entry;

  /// Whether thought text is shown in full.
  final bool expanded;

  /// Whether this is the running turn's last assistant block.
  final bool growing;

  /// Same immutable current snapshot used by the lazy selection delegate.
  final SelectionSource? selectionSource;

  /// Current app-owned code emphasis and shared copy action.
  final CodeBlockId? selectedCodeBlock;
  final void Function(MarkdownCodeBlock)? onCopyCodeBlock;

  /// Puts a current runnable descriptor into the prompt without executing.
  final void Function(MarkdownCodeBlock)? onRunCodeBlock;

  /// The currently bound shell stop hint; null until an action is available.
  final String? shellStopKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = entry;
    final drawn = switch (value) {
      model.HistoryOmittedEntry() => blockGap(
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: selectionSource == null
              ? Text(model.HistoryOmittedEntry.message)
              : Text.fromSelectionSource(
                  selectionChild(selectionSource!, 'omitted'),
                ),
        ),
      ),
      model.ShellEntry() => _Shell(
        run: value.run,
        source: selectionSource,
        stopKey: shellStopKey,
      ),
      model.UserEntry(:final from?) => _Message.from(
        from,
        expanded: expanded,
        text: value.text,
        source: selectionSource,
        selectedCodeBlock: selectedCodeBlock,
        onCopyCodeBlock: onCopyCodeBlock,
        onRunCodeBlock: onRunCodeBlock,
      ),
      model.UserEntry() => blockGap(
        _marked(
          '›',
          selectionSource == null
              ? Text(value.text)
              : Text.fromSelectionSource(
                  selectionChild(selectionSource!, 'user'),
                ),
          style: theme.dim,
        ),
      ),
      model.SelfStartedEntry() => _selfStarted(
        value,
        theme.dim,
        selectionSource,
      ),
      model.AssistantEntry() => blockGap(
        _marked(
          '⏺',
          selectionSource == null
              ? Markdown(
                  stripAnsi(value.text.text),
                  growing: growing,
                  selectedCodeBlock: selectedCodeBlock,
                  onCopyCodeBlock: onCopyCodeBlock,
                  runCodeBlockLanguages: onRunCodeBlock == null
                      ? const {}
                      : runnableCodeLanguages,
                  onRunCodeBlock: onRunCodeBlock,
                )
              : Markdown.fromSelectionSource(
                  selectionChild(selectionSource!, 'assistant'),
                  growing: growing,
                  selectedCodeBlock: selectedCodeBlock,
                  onCopyCodeBlock: onCopyCodeBlock,
                  runCodeBlockLanguages: onRunCodeBlock == null
                      ? const {}
                      : runnableCodeLanguages,
                  onRunCodeBlock: onRunCodeBlock,
                ),
        ),
      ),
      model.ThoughtEntry() => blockGap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marked(
              '∴',
              SelectionContainer.disabled(
                child: Text('Thinking…', style: theme.dim.merge(Style.italic)),
              ),
              style: theme.dim,
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: selectionSource != null
                    ? Text.fromSelectionSource(
                        selectionChild(selectionSource!, 'thought'),
                        style: theme.dim.merge(Style.italic),
                      )
                    : Text.ansi(
                        value.text.text.trim(),
                        style: theme.dim.merge(Style.italic),
                      ),
              ),
          ],
        ),
      ),
      model.NotedEntry() => blockGap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marked('›', Text('/${value.command}'), style: theme.dim),
            if (value.failed)
              _marked(
                '⏺',
                Text.ansi(value.text, style: theme.error),
                style: theme.error,
              )
            else
              Outcome(value.text),
          ],
        ),
      ),
      model.TypedCallEntry(:final turnId, :final command, :final call) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            blockGap(_marked('›', Text('/$command'), style: theme.dim)),
            Tool(
              model.ToolCall(turnId, status: 'completed', chord: call),
              expanded: expanded,
              ended: true,
              agent: agent,
            ),
          ],
        ),
      model.TeamShownEntry(:final command, :final shown) => blockGap(
        TeamEntry(
          command: command,
          shown: shown,
          expanded: expanded,
          rows: windowRows,
        ),
      ),
      // A team's instructions went in without their lines in the way: one
      // dim line, its text under ctrl+o.
      model.TeamPartEntry(:final part) => blockGap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: _marked(
                '⏺',
                Text(
                  teamPartLine(
                    part,
                    expanded,
                    hintKeyOf(context, 'app:toggleTranscript'),
                  ),
                  style: theme.dim,
                ),
                style: theme.dim,
              ),
            ),
            // The instructions select, as the original's do; the line
            // above is furniture.
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: selectionSource == null
                    ? Text.rich(
                        TextSpan(
                          '',
                          style: theme.dim,
                          children: [parseAnsi(part.text)],
                        ),
                      )
                    : Text.fromSelectionSource(
                        selectionChild(selectionSource!, 'team-instructions'),
                        style: theme.dim,
                      ),
              ),
          ],
        ),
      ),
      // A record's names and runtimes keep their own colours inside the
      // dim line, as the original's <Ansi> draws them; a reset goes back
      // to dim, not to plain.
      model.LeftOpenEntry(:final agents) => blockGap(
        _marked(
          '⏺',
          Text.rich(
            TextSpan(
              '',
              style: theme.dim,
              children: [parseAnsi(leftOpenLine(agents))],
            ),
          ),
          style: theme.dim,
        ),
      ),
      // Where a fork parted, one dim line cut at its end.
      model.ForkedEntry(:final from, :final at) => blockGap(
        LayoutBuilder(
          builder: (context, constraints) => Text(
            forkedLine(from, at, constraints.maxWidth),
            style: theme.dim,
            softWrap: false,
          ),
        ),
      ),
      // The descriptions keep their own colours inside the dim line, as the
      // original's <Ansi> draws them.
      model.MonitorsLeftEntry(:final monitors) => blockGap(
        _marked(
          '⏺',
          Text.rich(
            TextSpan(
              '',
              style: theme.dim,
              children: [parseAnsi(leftRunningLine(monitors))],
            ),
          ),
          style: theme.dim,
        ),
      ),
      model.ReportEntry() => blockGap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marked('›', Text('/${value.command}'), style: theme.dim),
            for (var i = 0; i < value.rows.length; i++)
              Under(
                first: i == 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (value.rows[i].label.isNotEmpty)
                      SizedBox(
                        width:
                            value.rows.fold(
                              0,
                              (n, row) => cellWidth(row.label) > n
                                  ? cellWidth(row.label)
                                  : n,
                            ) +
                            1,
                        child: Text(value.rows[i].label, style: theme.dim),
                      ),
                    Expanded(child: Text.ansi(value.rows[i].text)),
                  ],
                ),
              ),
          ],
        ),
      ),
      model.PermissionEntry() => _permission(value),
      model.CancelledEntry() => const Outcome(
        'Interrupted by user',
        failed: true,
      ),
      model.StoppedEntry() => Outcome('Stopped: ${value.reason}'),
      // A prompt refused for want of a login: its block in the turn's place.
      model.ErrorEntry(:final message, signIn: final signIn?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Failure('${agent ?? 'agent'} needs a sign-in: $message'),
          SignInBlock(agent: agent ?? 'agent', signIn: signIn),
        ],
      ),
      model.ErrorEntry() => Failure(value.message),
      model.WarningEntry() => Failure(value.message, warning: true),
      model.NoticeEntry() => Notice(value),
      model.ElicitationEntry() => _ElicitationRecord(
        value,
        agent: agent ?? 'agent',
        expanded: expanded,
      ),
      // Drawn by the list, with the subagents beside it.
      model.SubagentEntry() => const SizedBox(),
      model.AgentMessageEntry() => _Message(
        arrow: value.toSubagent ? '→' : '←',
        // The name in its agent's colour by that name, as the original
        // looks it up, while the arrow stays as the text is.
        header: (theme, colours) {
          final name = value.title == null ? 'Agent' : 'Agent(${value.title})';
          return [
            TextSpan(value.toSubagent ? 'to ' : 'from ', style: theme.dim),
            TextSpan(name, style: Style(fg: colours[name], bold: true)),
          ];
        },
        text: value.text,
        folds: value.toSubagent && value.launch && !expanded,
        source: selectionSource,
        selectedCodeBlock: selectedCodeBlock,
        onCopyCodeBlock: onCopyCodeBlock,
        onRunCodeBlock: onRunCodeBlock,
      ),
      model.ChildMessageEntry() => _Message(
        arrow: '←',
        header: (theme, _) => [
          TextSpan('from ', style: theme.dim),
          TextSpan(
            value.byAgent ? (agent ?? 'agent') : value.from,
            style: Style.bold,
          ),
        ],
        text: value.text,
        folds: false,
        source: selectionSource,
        selectedCodeBlock: selectedCodeBlock,
        onCopyCodeBlock: onCopyCodeBlock,
        onRunCodeBlock: onRunCodeBlock,
      ),
      model.ItemEndedEntry() => _ItemEnded(value),
      model.CompactionEntry() => _CompactionRecord(
        value.compaction,
        expanded: expanded,
        source: selectionSource,
        selectedCodeBlock: selectedCodeBlock,
        onCopyCodeBlock: onCopyCodeBlock,
        onRunCodeBlock: onRunCodeBlock,
      ),
      model.FinishedPlanEntry() => PlanRecord(
        value.entries,
        selectionSource: selectionSource,
      ),
      model.ToolEntry() => throw ArgumentError(
        'Tool entries are drawn by Tool',
      ),
    };
    return switch (value) {
      model.SelfStartedEntry() ||
      model.NotedEntry() ||
      model.TypedCallEntry() ||
      model.TeamShownEntry() ||
      model.LeftOpenEntry() ||
      model.MonitorsLeftEntry() ||
      model.ForkedEntry() ||
      model.ReportEntry() ||
      model.PermissionEntry() ||
      model.CancelledEntry() ||
      model.StoppedEntry() ||
      model.ErrorEntry() ||
      model.WarningEntry() ||
      model.NoticeEntry() ||
      model.ItemEndedEntry() ||
      model.ElicitationEntry() => SelectionContainer.disabled(child: drawn),
      _ => drawn,
    };
  }
}

Widget _marked(String marker, Widget child, {Style? style}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Gutter(marker, style: style),
    Expanded(child: child),
  ],
);

Widget _selfStarted(
  model.SelfStartedEntry entry,
  Style style,
  SelectionSource? source,
) {
  final text = source == null
      ? LayoutBuilder(
          builder: (context, constraints) => Text(
            selfStartedLine(constraints.maxWidth, entry.from),
            style: style,
            softWrap: false,
            maxLines: 1,
          ),
        )
      : Text.fromSelectionSource(
          selectionChild(source, 'self-started'),
          style: style,
        );
  return entry.alone
      ? blockGap(_marked('⏺', text, style: style))
      : Under(first: true, child: text);
}

/// A compaction: `✻ Compacting conversation…` while it runs outside a turn,
/// as no spinner is there to say it, then how it ended hung under what asked
/// for it, and in ctrl+o's view the summary the agent kept under that.
class _CompactionRecord extends StatelessWidget {
  const _CompactionRecord(
    this.compaction, {
    required this.expanded,
    this.source,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
  });
  final model.Compaction compaction;
  final bool expanded;
  final SelectionSource? source;
  final CodeBlockId? selectedCodeBlock;
  final void Function(MarkdownCodeBlock)? onCopyCodeBlock;
  final void Function(MarkdownCodeBlock)? onRunCodeBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = compactionLine(
      compaction,
      expanded,
      hintKeyOf(context, 'app:toggleTranscript'),
    );
    final style = switch (line.tone) {
      CompactionTone.running => theme.accent,
      CompactionTone.done => theme.dim,
      CompactionTone.failed => theme.error,
    };
    // The line is furniture; the summary is the agent's, selectable and
    // with its code blocks picked, copied and run as a reply's are.
    final text = SelectionContainer.disabled(
      child: source == null
          ? Text.ansi(line.text, style: style)
          : Text.fromSelectionSource(
              selectionChild(source!, 'compaction'),
              style: style,
            ),
    );
    if (line.tone == CompactionTone.running) {
      return blockGap(_marked('✻', text, style: style));
    }
    final summary = compaction.summary.trim();
    final runs = onRunCodeBlock == null
        ? const <String>{}
        : runnableCodeLanguages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Under(first: true, child: text),
        if (expanded && summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: source == null
                ? Markdown(
                    stripAnsi(summary),
                    selectedCodeBlock: selectedCodeBlock,
                    onCopyCodeBlock: onCopyCodeBlock,
                    runCodeBlockLanguages: runs,
                    onRunCodeBlock: onRunCodeBlock,
                  )
                : Markdown.fromSelectionSource(
                    selectionChild(source!, 'summary'),
                    selectedCodeBlock: selectedCodeBlock,
                    onCopyCodeBlock: onCopyCodeBlock,
                    runCodeBlockLanguages: runs,
                    onRunCodeBlock: onRunCodeBlock,
                  ),
          ),
      ],
    );
  }
}

/// How a form or link was answered: what the agent asked, as a
/// permission's answer is drawn, then the answer under `⎿`. ctrl+o shows
/// the values an accepted form sent. A request out of a tool call hangs
/// under that call.
class _ElicitationRecord extends StatelessWidget {
  const _ElicitationRecord(
    this.entry, {
    required this.agent,
    required this.expanded,
  });
  final model.ElicitationEntry entry;
  final String agent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wait = entry.wait;
    if (wait case model.FormWait(:final questions?)) {
      return _questionsRecord(theme, questions, hangs: wait.toolCallId != null);
    }
    final accepted = entry.outcome == model.ElicitationOutcome.accepted;
    final opened = accepted && wait is model.LinkWait;
    final text = accepted && wait is model.LinkWait
        ? 'Opened ${wait.url}'
        : accepted
        ? answeredText(entry.content)
        : entry.outcome == model.ElicitationOutcome.declined
        ? 'Declined'
        : 'Cancelled';
    final tone = opened
        ? theme.link
        : accepted
        ? theme.success
        : theme.error;
    final rows = expanded && accepted && wait is model.FormWait
        ? answeredRows(wait.schema, entry.content ?? const {})
        : const <AnsweredRow>[];
    final labelWidth = rows.fold(
      0,
      (n, row) => math.max(n, cellWidth(row.label)),
    );
    final record = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wait.toolCallId == null)
          _marked('⏺', Text.ansi('$agent asked: ${wait.message}')),
        Under(first: true, child: Text.ansi(text, style: tone)),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth + 2,
                  child: Text.ansi(row.label, softWrap: false),
                ),
                Expanded(
                  child: Text.ansi(row.value, softWrap: false, maxLines: 1),
                ),
              ],
            ),
          ),
      ],
    );
    return wait.toolCallId == null ? blockGap(record) : record;
  }

  /// How an agent's questions were answered: a row per question, its
  /// header and the answer, or how the box ended. Out of a tool call it
  /// hangs under the call; out of none, right under the turn's prompt,
  /// saying who asked. One not answered names its questions before how it
  /// ended.
  Widget _questionsRecord(
    ThemeData theme,
    Questions questions, {
    required bool hangs,
  }) {
    final asked = hangs ? '' : '$agent asked · ';
    final ended = switch (entry.outcome) {
      model.ElicitationOutcome.accepted => null,
      model.ElicitationOutcome.declined => 'Skipped',
      model.ElicitationOutcome.cancelled => 'Cancelled',
      model.ElicitationOutcome.timedOut => 'Timed out',
    };
    if (ended != null) {
      return Under(
        first: true,
        child: Text.rich(
          TextSpan(
            '$asked${askedHeaders(questions)} · ',
            children: [TextSpan(ended, style: theme.error)],
          ),
        ),
      );
    }
    final rows = answeredQuestions(questions, entry.content ?? const {});
    final labelWidth = rows.fold(
      0,
      (n, row) => math.max(n, cellWidth(row.label)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : cellWidth(asked)),
            child: Under(
              first: index == 0,
              child: Row(
                children: [
                  if (index == 0 && asked != '') Text(asked),
                  SizedBox(
                    width: labelWidth + 2,
                    child: Text.ansi(row.label, softWrap: false),
                  ),
                  Expanded(
                    child: Text.ansi(row.value, softWrap: false, maxLines: 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// What was said between agents: `→ to` or `← from` and who, then what
/// it said under `⎿`, dim, or a failed report's in the error colour; a
/// launch's prompt folds after six rows behind ctrl+o.
class _Message extends StatelessWidget {
  const _Message({
    required this.arrow,
    required this.header,
    required this.text,
    required this.folds,
    this.tone = ArrowTone.plain,
    this.peer,
    this.failed = false,
    this.cut = false,
    this.source,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
    this.monitorEnded,
    this.expanded = false,
  });

  /// A message another agent, or chord, sent the session: `from ` dim,
  /// the sender bold and, as its arrow, in its colour, the rest dim, the whole header one row cut at its
  /// end, and the text whole.
  factory _Message.from(
    model.MessageFrom from, {
    required String text,
    bool expanded = false,
    SelectionSource? source,
    CodeBlockId? selectedCodeBlock,
    void Function(MarkdownCodeBlock)? onCopyCodeBlock,
    void Function(MarkdownCodeBlock)? onRunCodeBlock,
  }) {
    final (:word, :name, :rest) = messageHeader(from);
    return _Message(
      arrow: '←',
      tone: inArrow(from),
      peer: from.name,
      header: (theme, colours) => [
        TextSpan(word, style: theme.dim),
        TextSpan(
          '',
          style: Style(fg: colours[from.name], bold: true),
          children: [parseAnsi(name)],
        ),
        TextSpan('', style: theme.dim, children: [parseAnsi(rest)]),
      ],
      text: text,
      folds: false,
      failed: from.note == model.MessageNote.failed,
      cut: true,
      monitorEnded: switch (from.monitor) {
        null => null,
        (:final end, id: _) => end != null,
      },
      expanded: expanded,
      source: source,
      selectedCodeBlock: selectedCodeBlock,
      onCopyCodeBlock: onCopyCodeBlock,
      onRunCodeBlock: onRunCodeBlock,
    );
  }

  final String arrow;
  final ArrowTone tone;

  /// The agent at the message's other end, whose colour a plain arrow
  /// takes; none leaves the arrow as the text is.
  final String? peer;

  /// The row after the arrow, in the theme's styles and the agents'
  /// colours.
  final List<TextSpan> Function(ThemeData theme, Map<String, Color> colours)
  header;
  final String text;
  final bool folds;
  final bool failed;

  /// Whether a header wider than the row is cut, as the original's one-row
  /// header is; else it is clipped.
  final bool cut;
  final CodeBlockId? selectedCodeBlock;
  final void Function(MarkdownCodeBlock)? onCopyCodeBlock;
  final void Function(MarkdownCodeBlock)? onRunCodeBlock;

  /// The entry's selection source, whose words the body draws; none draws
  /// the message unselectable.
  final SelectionSource? source;

  /// A monitor's event: whether it is its end; null for any other message.
  final bool? monitorEnded;

  /// Whether ctrl+o shows a monitor's event whole.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final message = _message(context);
    return source == null
        ? SelectionContainer.disabled(child: message)
        : message;
  }

  Widget _message(BuildContext context) {
    final theme = Theme.of(context);
    final colours = AgentColours.of(context);
    final source = this.source;
    return blockGap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Row(
              children: [
                Arrow(arrow, tone, colour: colours[peer]),
                Expanded(
                  child: Text.rich(
                    TextSpan('', children: header(theme, colours)),
                    softWrap: false,
                    maxLines: 1,
                    overflow: cut ? TextOverflow.middle : TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),
          if (monitorEnded case final ended?)
            LayoutBuilder(
              builder: (context, constraints) =>
                  _monitorBody(theme, constraints.maxWidth, ended),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final hidden = messageHidden(
                  text,
                  constraints.maxWidth,
                  folds: folds,
                );
                // A folded launch's code has no controls, as the original
                // hands its blocks none while they hide.
                final copy = hidden > 0 ? null : onCopyCodeBlock;
                final run = hidden > 0 ? null : onRunCodeBlock;
                final Widget body = DefaultTextStyle(
                  style: failed ? theme.error : theme.dim,
                  child: source == null
                      ? Markdown(
                          stripAnsi(text),
                          quoteBars: false,
                          selectedCodeBlock: selectedCodeBlock,
                          onCopyCodeBlock: copy,
                          runCodeBlockLanguages: run == null
                              ? const {}
                              : runnableCodeLanguages,
                          onRunCodeBlock: run,
                        )
                      : Markdown.fromSelectionSource(
                          selectionChild(source, 'message'),
                          selectedCodeBlock: selectedCodeBlock,
                          onCopyCodeBlock: copy,
                          onRunCodeBlock: run,
                        ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Under(
                      first: true,
                      child: hidden == 0
                          ? body
                          : SizedBox(
                              height: messageLines,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    height: messageLines + hidden,
                                    child: body,
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (hidden > 0) Folded(hidden),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

extension on _Message {
  /// A monitor's event under its `←`: the lines it printed, verbatim and
  /// folded, then chord's sentence on its end, dim and never folded.
  Widget _monitorBody(ThemeData theme, int width, bool ended) {
    final (:lines, :hidden, :sentence) = monitorMessage(
      text,
      ended: ended,
      expanded: expanded,
      width: math.max(width - 5, 1),
    );
    final source = this.source;
    Widget part(String key, String text, Style style) => source == null
        ? Text(text, style: style, softWrap: false)
        : Text.fromSelectionSource(selectionChild(source, key), style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lines.isNotEmpty)
          Under(
            first: true,
            child: part(
              'monitor-lines',
              [for (final line in lines) line.isEmpty ? ' ' : line].join('\n'),
              failed ? theme.error : theme.dim,
            ),
          ),
        if (hidden > 0) Folded(hidden),
        if (sentence != null)
          Under(
            first: lines.isEmpty,
            child: SelectionContainer.disabled(
              child: Text(sentence, style: theme.dim, softWrap: false),
            ),
          ),
      ],
    );
  }
}

/// An agent item that ended after its turn,
/// `✓ <name> · agent · done in 2s`, or a task stopped after its turn, with
/// who stopped it: `■ <name> · task · stopped with esc after 3s`.
class _ItemEnded extends StatelessWidget {
  const _ItemEnded(this.entry);
  final model.ItemEndedEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final took = entry.startedAt == null || entry.endedAt == null
        ? null
        : formatElapsed(math.max(0, entry.endedAt! - entry.startedAt!));
    final after = took == null ? '' : ' after $took';
    final (marker, tone, end) = switch (entry.end) {
      model.ItemEnd.done => (
        '✓',
        theme.success,
        'done${took == null ? '' : ' in $took'}',
      ),
      model.ItemEnd.failed => ('✗', theme.error, 'failed$after'),
      model.ItemEnd.disconnected => ('✗', theme.error, 'disconnected$after'),
      model.ItemEnd.stopped => (
        '■',
        theme.dim,
        'stopped${switch (entry) {
          model.ItemEndedEntry(byPerson: true) => ' with x',
          model.ItemEndedEntry(byEsc: true) => ' with esc',
          model.ItemEndedEntry(:final byAgent?) => ' by $byAgent',
          _ => '',
        }}$after',
      ),
      model.ItemEnd.ended => (
        '■',
        theme.dim,
        '${entry.byPerson ? 'stopped with x' : 'ended'}$after',
      ),
    };
    final reason = (entry.error ?? '').split('\n').first.trim();
    return blockGap(
      Row(
        children: [
          Gutter(marker, style: tone),
          Expanded(
            child: Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan(entry.name),
                  TextSpan(' · ${entry.item.name} · ', style: theme.dim),
                  TextSpan(end, style: tone),
                  if (reason.isNotEmpty) TextSpan(': $reason', style: tone),
                ],
              ),
              softWrap: false,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _permission(model.PermissionEntry entry) {
  final result = permissionOutcome(entry);
  return Outcome(result.text, failed: !result.allowed);
}

/// The M1 transcript list and its keyboard actions above the focused input.
class Transcript extends StatefulWidget {
  /// Draws a transcript with the caller-owned bottom-following controller.
  const Transcript({
    super.key,
    required this.transcript,
    required this.controller,
    this.paths,
    this.chordServer,
    this.footer,
    this.bodyPadding = 0,
    this.header,
    this.intro,
    this.expanded,
    this.bindKeys = true,
    this.selectionNamespace,
    this.headerSelectionSource,
    this.selectionSources,
    this.selectedCodeBlock,
    this.onCopyCodeBlock,
    this.onRunCodeBlock,
    this.shellStopKey,
    this.expandKey = 'ctrl+o',
    this.agent,
    this.windowRows = 40,
    this.resumed = false,
  });

  /// Whether the session is a resumed one: its recorded receipts are then
  /// historical observations.
  final bool resumed;

  /// The agent as the window names it, for a plan's words.
  final String? agent;

  /// The window's rows, which decide how much `/team show` keeps folded.
  final int windowRows;

  /// An optional first item, scrolling with the transcript.
  final Widget? header;

  /// Nonselectable opening furniture after the header, outside recorded entries.
  final Widget? intro;

  /// Controlled details state, or the original internal state when absent.
  final bool? expanded;

  /// Whether this standalone transcript registers its own app keys.
  final bool bindKeys;

  /// Current session/clear identity enabling the logical lazy source provider.
  final Object? selectionNamespace;

  /// Same current snapshot used by the bound startup header widget.
  final SelectionSource? headerSelectionSource;

  /// Shared current snapshots for both mounted entries and the lazy code catalog.
  final TranscriptSources? selectionSources;

  /// App-owned frame emphasis, without a geometry/source revision change.
  final CodeBlockId? selectedCodeBlock;

  /// The window's one copy path for current complete Markdown blocks.
  final void Function(MarkdownCodeBlock)? onCopyCodeBlock;

  /// Puts a current runnable descriptor into the prompt without executing.
  final void Function(MarkdownCodeBlock)? onRunCodeBlock;

  /// The live key bound to stopping local commands, when available.
  final String? shellStopKey;

  /// The key that expands folded output; none when nothing is bound to it.
  final String? expandKey;

  /// Entries and turn state folded by the session reducer.
  final model.Transcript transcript;

  /// The framework owns all scrolling; the window applies event effects.
  final ScrollController controller;

  /// Session path spellings for tool edit headlines.
  final PathView? paths;

  /// The name the session gave chord's own server, by which a call to it
  /// reads as chord's.
  final String? chordServer;

  /// Horizontal inset for the scroll body, independent of its footer.
  final int bodyPadding;

  /// The input, within the transcript action scope's focus path.
  final Widget? footer;

  @override
  State<Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<Transcript> {
  var _view = const ViewWindow();
  TranscriptSources? _sources;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(Transcript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionNamespace != widget.selectionNamespace) {
      _sources = null;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_scrolled);
      widget.controller.addListener(_scrolled);
    }
  }

  void _scrolled() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _content(context, constraints.maxWidth),
  );

  Widget _content(BuildContext context, int width) {
    final entries = List<model.Entry>.unmodifiable(widget.transcript.entries);
    final turn = widget.transcript.turn;
    final expanded = widget.expanded ?? _view.expanded;
    final headerCount = widget.header == null ? 0 : 1;
    final introCount = widget.intro == null ? 0 : 1;
    final prefixCount = headerCount + introCount;
    // After the entries: each receipt whose run has no row of its own.
    final receipts = recordedReceipts(widget.transcript);
    final itemCount = prefixCount + entries.length + receipts.length;
    model.ChordCall? receiptAt(int index) {
      final at = index - prefixCount - entries.length;
      return at < 0 ? null : receipts[at];
    }

    final store =
        widget.selectionSources ??
        (widget.selectionNamespace == null
            ? null
            : (_sources ??= TranscriptSources(widget.selectionNamespace!)));
    store?.retain(entries);
    final itemWidth = (width - 2 * widget.bodyPadding).clamp(0, unbounded);
    SelectionSource sourceAt(int index) {
      if (headerCount == 1 && index == 0) {
        return widget.headerSelectionSource ??
            (throw StateError('A selectable header needs its current source.'));
      }
      if (introCount == 1 && index == headerCount) {
        return SelectionSource.group(
          id: (store!.namespace, 'intro'),
          revision: widget.intro!,
          children: const [],
        );
      }
      if (receiptAt(index) case final call?) {
        return SelectionSource.group(
          id: (store!.namespace, ('receipt', call.asked)),
          revision: call,
          children: const [],
        );
      }
      store!.settingsStyles = (
        warning: Theme.of(context).warning,
        success: Theme.of(context).success,
      );
      return store.entryAt(
        widget.transcript,
        index - prefixCount,
        width: itemWidth,
        expanded: expanded,
        copyCodeBlocks: widget.onCopyCodeBlock != null,
        runCodeBlocks: widget.onRunCodeBlock != null,
        shellStopKey: widget.shellStopKey,
        expandKey: widget.expandKey,
        paths: widget.paths,
        agent: widget.agent,
        chordServer: widget.chordServer,
        agentColours: AgentColours.of(context),
      );
    }

    final ids = [
      if (headerCount == 1) widget.headerSelectionSource?.id,
      if (introCount == 1) (store?.namespace, 'intro'),
      if (store != null) ...[
        for (final entry in entries) store.id(entry),
        for (final call in receipts) (store.namespace, ('receipt', call.asked)),
      ],
    ];
    final indices = {for (final (i, id) in ids.indexed) id: i};
    final selectionDelegate = store == null
        ? null
        : SelectionChildDelegate(
            itemCount: itemCount,
            idAt: (i) => ids[i]!,
            indexOfId: (id) => indices[id],
            sourceAt: sourceAt,
          );
    return Actions(
      bindings: [
        if (widget.bindKeys) ...[
          ...scrollBindings(widget.controller, keys: chordScrollKeys),
          Binding(
            'ctrl+o',
            'Toggle transcript details',
            () => setState(() => _view = toggled(_view)),
          ),
        ],
      ],
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.bodyPadding),
              child: Stack(
                children: [
                  ListView.builder(
                    key: const ValueKey('transcript-list'),
                    controller: widget.controller,
                    selectionDelegate: selectionDelegate,
                    itemCount: itemCount,
                    itemVersion: (index) {
                      if (headerCount == 1 && index == 0) {
                        return widget.headerSelectionSource == null
                            ? widget.header
                            : (
                                widget.headerSelectionSource!.id,
                                widget.headerSelectionSource!.revision,
                              );
                      }
                      if (introCount == 1 && index == headerCount) {
                        return widget.intro;
                      }
                      if (receiptAt(index) case final call?) {
                        return (call, widget.resumed);
                      }
                      final i = index - prefixCount;
                      return (
                        entries[i],
                        entries[i] is model.ToolEntry &&
                            asksFor(
                              turn,
                              (entries[i] as model.ToolEntry).call.id,
                            ),
                        expanded,
                        turnEnded(turn, entries[i].turnId),
                        inSpinner(entries[i], turn),
                        // A group draws the subagents after it too, and
                        // the waits of the turn.
                        entries[i] is model.SubagentEntry
                            ? (
                                Object.hashAll(
                                  agentGroup(entries, i) ?? const [],
                                ),
                                turn,
                              )
                            : null,
                        i == entries.length - 1 &&
                            !turnEnded(turn, entries[i].turnId),
                        widget.paths,
                        widget.chordServer,
                        widget.agent,
                        // `/team show` folds its body by the window's rows.
                        entries[i] is model.TeamShownEntry
                            ? widget.windowRows
                            : null,
                        widget.onCopyCodeBlock != null,
                        widget.onRunCodeBlock != null,
                        widget.shellStopKey,
                        widget.expandKey,
                        widget.selectedCodeBlock != null &&
                                store != null &&
                                store.ownsCodeBlock(
                                  widget.selectedCodeBlock!,
                                  entries[i],
                                )
                            ? widget.selectedCodeBlock
                            : null,
                      );
                    },
                    itemBuilder: (context, index) {
                      if (headerCount == 1 && index == 0) return widget.header!;
                      if (introCount == 1 && index == headerCount) {
                        return SelectionContainer.disabled(
                          child: widget.intro!,
                        );
                      }
                      // chord's own report, not an agent's words.
                      if (receiptAt(index) case final call?) {
                        return SelectionContainer.disabled(
                          child: RecordedReceipt(
                            call,
                            historical: widget.resumed,
                          ),
                        );
                      }
                      final i = index - prefixCount;
                      final entry = entries[i];
                      final source = store == null ? null : sourceAt(index);
                      // The spinner says it while it runs in the turn.
                      if (inSpinner(entry, turn)) return const SizedBox();
                      if (entry is model.SubagentEntry) {
                        final group = agentGroup(entries, i) ?? const [];
                        return group.isEmpty
                            ? const SizedBox()
                            : Agents(
                                group,
                                turn: turn,
                                open: expanded,
                                agent: widget.agent,
                                selectionSource: source,
                                selectedCodeBlock: widget.selectedCodeBlock,
                                onCopyCodeBlock: widget.onCopyCodeBlock,
                                onRunCodeBlock: widget.onRunCodeBlock,
                              );
                      }
                      if (entry is model.ToolEntry) {
                        return Tool(
                          entry.call,
                          expanded: expanded,
                          // A call still asked about waits on the person,
                          // its turn over or not.
                          ended:
                              turnEnded(turn, entry.turnId) &&
                              !asksFor(turn, entry.call.id),
                          asked: asksFor(turn, entry.call.id),
                          paths: widget.paths,
                          selectionSource: source,
                          agent: widget.agent,
                          chordServer: widget.chordServer,
                        );
                      }
                      return TranscriptEntry(
                        entry,
                        expanded: expanded,
                        selectionSource: source,
                        selectedCodeBlock: widget.selectedCodeBlock,
                        onCopyCodeBlock: widget.onCopyCodeBlock,
                        onRunCodeBlock: widget.onRunCodeBlock,
                        shellStopKey: widget.shellStopKey,
                        agent: widget.agent,
                        windowRows: widget.windowRows,
                        growing:
                            entry is model.AssistantEntry &&
                            i == entries.length - 1 &&
                            !turnEnded(turn, entry.turnId),
                      );
                    },
                  ),
                  if (!widget.controller.isFollowing)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 1,
                      child: SelectionContainer.disabled(
                        child: Below(widget.controller.state),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

/// The styled one-row rule covering the transcript's last visible row.
class Below extends StatelessWidget {
  /// A rule for the framework's measured scroll state.
  const Below(this.scroll, {super.key});

  /// Current content, viewport, top, following and news facts.
  final ScrollState scroll;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final segments = indicator(
        scroll,
        constraints.maxWidth,
        hintKeyOf(context, 'scroll:bottom'),
      );
      return Text.rich(
        TextSpan(
          '',
          children: [
            for (final segment in segments)
              TextSpan(
                segment.text,
                style: segment.accent
                    ? theme.accent.merge(Style.bold)
                    : theme.dim,
              ),
          ],
        ),
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.middle,
      );
    },
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.run, this.source, this.stopKey});
  final model.ShellRun run;
  final SelectionSource? source;
  final String? stopKey;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), view = shellView(run, true, stopKey);
    final stdout = view.lines.where((line) => !line.stderr).toList();
    final stderr = view.lines.where((line) => line.stderr).toList();
    Widget text(String key, String value, {Style? style}) => source == null
        ? Text(value, style: style)
        : Text.fromSelectionSource(selectionChild(source!, key), style: style);
    return blockGap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _marked(
            '!',
            text('shell-command', run.command),
            style: chordThemeOf(context).bash,
          ),
          if (stdout.isNotEmpty)
            Under(
              first: true,
              child: text(
                'shell-stdout',
                stdout.map((line) => line.text).join('\n'),
              ),
            ),
          if (stderr.isNotEmpty)
            Under(
              first: stdout.isEmpty,
              child: text(
                'shell-stderr',
                stderr.map((line) => line.text).join('\n'),
                style: theme.error,
              ),
            ),
          if (view.note case final note?)
            SelectionContainer.disabled(
              child: Under(
                first: view.lines.isEmpty,
                child: text(
                  'shell-note',
                  note.text,
                  style: note.failed ? theme.error : theme.dim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
