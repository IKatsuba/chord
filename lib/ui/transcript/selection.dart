import 'dart:math' as math;

import '../header/compact.dart' show helpRow;
import '../header/resumed.dart';
import 'package:chord_tui/chord_tui.dart';

import '../../session/sign_in.dart'
    show SignIn, accountReported, offersLine, wayOn;
import '../../session/transcript/types.dart' as model;
import '../pickers/mcp.dart' show cutPath;
import '../../acp/schema.dart' as acp;
import '../plan/plan_rows.dart';
import '../prompt/bash.dart';
import 'tools/diff.dart';
import 'agent_colours.dart' show coloursKey;
import 'message.dart';
import 'code_pick.dart' show runnableCodeLanguages;
import 'compaction.dart';
import 'notice.dart' show noticeDescription;
import 'tools/paths.dart';
import 'tools/tools.dart';
import 'tools/plan_ask.dart' show planSource;
import 'tools/proposal.dart' show bodyChangeLine, proposalOf, savedLine;
import 'tools/proposal_view.dart' show proposalChange, proposalHead;
import 'tools/settings_row.dart'
    show SettingsTone, foldedSettingsNote, settingsRows;
import 'agents/subagents.dart';
import '../dialogs/permission.dart' show permissionOutcome;

/// The styles a settings row's warning and success are drawn in, the
/// theme's, which the rows' selectable text carries.
typedef SettingsStyles = ({Style warning, Style success});

/// The options a transcript draws its entries with, beside width and
/// expansion.
typedef EntryDrawing = ({
  bool copyCodeBlocks,
  bool runCodeBlocks,
  String? shellStopKey,
  String? expandKey,
  PathView? paths,
  String? agent,
  String? chordServer,
  Map<String, Color> agentColours,
});

/// Current domain snapshots for the transcript's lazy selection provider.
class TranscriptSources {
  TranscriptSources(this.namespace);
  final Object namespace;
  Map<model.EntryIdentity, int> _indices = {};
  final _entries =
      <model.EntryIdentity, ({Object revision, SelectionSource source})>{};

  /// The styles settings rows are drawn in, the theme's, which the
  /// transcript sets as it draws: kept here, so every reader of an entry,
  /// the code picker's too, asks for the same revision of it.
  SettingsStyles settingsStyles = (warning: Style.plain, success: Style.plain);

  /// What the transcript last drew its entries with, which it sets as it
  /// draws: [drawnEntryAt] reads them, so a lazy reader asks for the
  /// revision on screen, and a click's block matches the catalog's.
  EntryDrawing drawing = const (
    copyCodeBlocks: false,
    runCodeBlocks: false,
    shellStopKey: null,
    expandKey: 'ctrl+o',
    paths: null,
    agent: null,
    chordServer: null,
    agentColours: {},
  );

  /// [entryAt] with the options the transcript last drew with.
  SelectionSource drawnEntryAt(
    model.Transcript transcript,
    int index, {
    required int width,
    bool expanded = false,
  }) => entryAt(
    transcript,
    index,
    width: width,
    expanded: expanded,
    copyCodeBlocks: drawing.copyCodeBlocks,
    runCodeBlocks: drawing.runCodeBlocks,
    shellStopKey: drawing.shellStopKey,
    expandKey: drawing.expandKey,
    paths: drawing.paths,
    agent: drawing.agent,
    chordServer: drawing.chordServer,
    agentColours: drawing.agentColours,
  );

  /// Number of current roots retained; removed entries leave no cache history.
  int get cachedEntryCount => _entries.length;

  /// Keeps only current logical entries without resolving/parsing their sources.
  void retain(List<model.Entry> entries) {
    _indices = {
      for (final (index, entry) in entries.indexed) entry.identity: index,
    };
    _entries.removeWhere((id, _) => !_indices.containsKey(id));
  }

  /// Session-scoped identity, independent of mounted rows or entry revisions.
  Object id(model.Entry entry) => (namespace, entry.identity);

  // A block's source id holds its entry's at its head, however deep the
  // block is drawn: in a subagent's work, under its group's entry.
  model.EntryIdentity? _codeEntry(CodeBlockId block) {
    Object? id = block.sourceId;
    while (true) {
      switch (id) {
        case (Object scope, model.EntryIdentity identity)
            when scope == namespace:
          return identity;
        case (Object head, Object _):
          id = head;
        default:
          return null;
      }
    }
  }

  /// Current entry position from this application's own source identity scheme.
  int? indexOfCodeBlock(CodeBlockId block) => _indices[_codeEntry(block)];

  /// Whether a frame style belongs to this entry, without resolving its source.
  bool ownsCodeBlock(CodeBlockId block, model.Entry entry) =>
      _codeEntry(block) == entry.identity;

  /// The single current-state adapter shared by mounted rows and lazy catalogs.
  SelectionSource entryAt(
    model.Transcript transcript,
    int index, {
    required int width,
    bool expanded = false,
    bool copyCodeBlocks = false,
    bool runCodeBlocks = false,
    String? shellStopKey,
    String? expandKey = 'ctrl+o',
    PathView? paths,
    String? agent,
    String? chordServer,
    Map<String, Color> agentColours = const {},
  }) {
    final entry = transcript.entries[index], turn = transcript.turn;
    return source(
      entry,
      width: width,
      expanded: expanded,
      growing:
          entry is model.AssistantEntry &&
          index == transcript.entries.length - 1 &&
          !turnEnded(turn, entry.turnId),
      ended:
          turnEnded(turn, entry.turnId) &&
          !(entry is model.ToolEntry && asksFor(turn, entry.call.id)),
      asked: entry is model.ToolEntry && asksFor(turn, entry.call.id),
      spinning: inSpinner(entry, turn),
      copyCodeBlocks: copyCodeBlocks,
      runCodeBlocks: runCodeBlocks,
      shellStopKey: shellStopKey,
      expandKey: expandKey,
      paths: paths,
      agent: agent,
      chordServer: chordServer,
      agentColours: agentColours,
      settingsStyles: settingsStyles,
      group: agentGroup(transcript.entries, index) ?? const [],
      waits: turn is model.AwaitingPermission ? turn.permissions : const [],
    );
  }

  /// Resolves just one immutable current entry at its effective list width.
  SelectionSource source(
    model.Entry entry, {
    required int width,
    bool expanded = false,
    bool growing = false,
    bool ended = false,
    bool asked = false,
    bool spinning = false,
    bool copyCodeBlocks = false,
    bool runCodeBlocks = false,
    String? shellStopKey,
    String? expandKey = 'ctrl+o',
    PathView? paths,
    String? agent,
    String? chordServer,
    Map<String, Color> agentColours = const {},
    SettingsStyles settingsStyles = const (
      warning: Style.plain,
      success: Style.plain,
    ),
    List<model.Subagent> group = const [],
    List<model.PermissionWait> waits = const [],
  }) {
    final revision = (
      entry,
      width,
      expanded,
      growing,
      ended,
      asked,
      spinning,
      paths,
      copyCodeBlocks,
      runCodeBlocks,
      shellStopKey,
      expandKey,
      agent,
      chordServer,
      coloursKey(agentColours),
      settingsStyles,
      Object.hashAll(group),
      group.isEmpty ? null : Object.hashAll(waits),
    );
    final old = _entries[entry.identity];
    if (old?.revision == revision) return old!.source;
    final source = entrySelectionSource(
      entry,
      id: id(entry),
      revision: revision,
      width: width,
      expanded: expanded,
      growing: growing,
      ended: ended,
      asked: asked,
      spinning: spinning,
      copyCodeBlocks: copyCodeBlocks,
      runCodeBlocks: runCodeBlocks,
      shellStopKey: shellStopKey,
      expandKey: expandKey,
      paths: paths,
      agent: agent,
      chordServer: chordServer,
      agentColours: agentColours,
      settingsStyles: settingsStyles,
      group: group,
      waits: waits,
      previous: old?.source,
    );
    _entries[entry.identity] = (revision: revision, source: source);
    return source;
  }
}

/// One composite's current source children, with no historical entry references.
class SourceBuilder {
  SourceBuilder(this.id, this.revision, this.previous) {
    void visit(SelectionSource source) {
      _old[source.id] = source;
      for (final child in source.children) {
        visit(child);
      }
    }

    if (previous != null) visit(previous!);
  }
  final Object id, revision;
  final SelectionSource? previous;
  final _old = <Object, SelectionSource>{};
  final _children = <SelectionSourceChild>[];
  Object childId(Object key) => (id, key);

  SelectionSource text(
    Object key,
    TextSpan span, {
    int left = 0,
    int right = 0,
    bool softWrap = true,
    int? maxLines,
    TextOverflow overflow = TextOverflow.clip,
    String separator = '\n',
    bool selectable = true,
  }) {
    final child = SelectionSource.text(
      id: childId(key),
      revision: revision,
      text: span,
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
      previous: _old[childId(key)],
    );
    _children.add(
      SelectionSourceChild(
        source: child,
        insetLeft: left,
        insetRight: right,
        separatorBefore: separator,
        selectable: selectable,
      ),
    );
    return child;
  }

  void markdown(
    Object key,
    String text, {
    int left = 0,
    bool growing = false,
    bool copyCodeBlocks = false,
    bool runCodeBlocks = false,
  }) {
    final child = SelectionSource.markdown(
      id: childId(key),
      revision: revision,
      text: text,
      growing: growing,
      copyCodeBlocks: copyCodeBlocks,
      runCodeBlockLanguages: runCodeBlocks ? runnableCodeLanguages : const {},
      previous: _old[childId(key)],
    );
    _children.add(SelectionSourceChild(source: child, insetLeft: left));
  }

  void diff(Object key, ToolDiffView diff) {
    final child = SelectionSource.diff(
      id: childId(key),
      revision: revision,
      view: diff.view,
      title: diff.path,
      showTitle: false,
      wrap: DiffWrap.wrapAnsi,
      // The original wraps a diff's code in the tool's width less five,
      // the row less the transcript's two cells; its tint fills the row.
      codeInsetRight: 2,
      previous: _old[childId(key)],
    );
    _children.add(SelectionSourceChild(source: child, insetLeft: 5));
  }

  /// [make]'s source, built under [key] from its previous one, [left]
  /// cells in: a composite drawn inside this one.
  SelectionSource nested(
    Object key,
    SelectionSource Function(Object id, SelectionSource? previous) make, {
    int left = 0,
  }) {
    final child = make(childId(key), _old[childId(key)]);
    _children.add(SelectionSourceChild(source: child, insetLeft: left));
    return child;
  }

  /// Decorative blank rows affect geometry and never introduce copy units.
  void gap(Object key) =>
      text(key, const TextSpan(''), separator: '', selectable: false);
  SelectionSource finish() => SelectionSource.group(
    id: id,
    revision: revision,
    children: _children,
    previous: previous,
  );
}

/// Finds a role in the same immutable object used by the lazy provider.
SelectionSource selectionChild(SelectionSource root, Object role) =>
    root.child((root.id, role));

/// Current ordered children of a composite role, including ambiguous fresh IDs.
List<SelectionSource> selectionChildren(SelectionSource root, String role) => [
  for (final child in root.children)
    if (child.id case (Object _, (String kind, Object _)) when kind == role)
      child,
];

/// The visible plan rows, with semantic description identities and excluded marks.
SelectionSource livePlanSelectionSource({
  required Object id,
  required Object revision,
  required List<acp.PlanEntry> plan,
  required int limit,
  required bool running,
  SelectionSource? previous,
}) {
  final b = SourceBuilder(id, revision, previous);
  if (!running) {
    b.gap('gap');
    b.text(
      'summary',
      TextSpan(planSummary(plan)),
      left: 2,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.middle,
      selectable: false,
    );
  }
  final rows = planRows(plan, limit);
  final counts = <String, int>{};
  for (final row in rows.whereType<EntryPlanRow>().where(
    (row) => planMarks.containsKey(row.entry.status),
  )) {
    counts.update(row.entry.content, (n) => n + 1, ifAbsent: () => 1);
  }
  for (final row in rows) {
    if (row is EntryPlanRow) {
      if (!planMarks.containsKey(row.entry.status)) {
        b.gap(('unknown-plan', Object()));
        continue;
      }
      final key = counts[row.entry.content] == 1
          ? ('plan-step', row.entry.content)
          : ('plan-step', Object());
      b.text(
        key,
        parseAnsi(row.entry.content),
        left: 7,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.middle,
      );
    } else {
      final text = switch (row) {
        DonePlanRow(:final count) => '… $count done',
        MorePlanRow(:final count) => '… +$count more',
        EntryPlanRow() => throw StateError('entry already handled'),
      };
      b.text(
        ('plan-fold', row.runtimeType),
        TextSpan(text),
        left: 5,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.middle,
        selectable: false,
      );
    }
  }
  return b.finish();
}

/// The four startup text rows; the logo and its spacing are absent.
SelectionSource headerSelectionSource({
  required Object id,
  required Object revision,
  required int width,
  required String version,
  required String agent,
  required String directory,
  String? model,
  ResumedHeader? resumed,
  SelectionSource? previous,
  String? helpKey = '?',
}) {
  final b = SourceBuilder(id, revision, previous);
  final room = (width - 7).clamp(0, unbounded);
  for (final (key, span) in <(String, TextSpan)>[
    (
      'version',
      TextSpan(
        '',
        children: [
          const TextSpan('chord', style: Style.bold),
          TextSpan(' v$version', style: Style.dim),
        ],
      ),
    ),
    ('agent', TextSpan('$agent${model == null ? '' : ' · $model'}')),
    ('directory', TextSpan(cutPath(directory, room))),
    ('help', TextSpan(helpRow(helpKey))),
  ]) {
    b.text(
      key,
      span,
      left: 7,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.middle,
    );
  }
  if (resumed case final facts?) {
    b.text(
      'resumed',
      TextSpan(resumedRows(facts, room)),
      left: 7,
      softWrap: facts.wrap,
      maxLines: facts.wrap ? null : 1,
      overflow: facts.wrap ? TextOverflow.clip : TextOverflow.middle,
    );
  }
  return b.finish();
}

/// A child's line at the start of its transcript, `parser · fake · opened
/// by main 1m ago`: nothing to copy, as the original's line is not
/// selectable, and its age goes on with no source to keep up.
SelectionSource childLineSelectionSource({
  required Object id,
  required Object revision,
  SelectionSource? previous,
}) => SelectionSource.group(
  id: id,
  revision: revision,
  children: const [],
  previous: previous,
);

/// The same current text, Markdown and diff data that an entry draws.
SelectionSource entrySelectionSource(
  model.Entry entry, {
  required Object id,
  required Object revision,
  required int width,
  bool expanded = false,
  bool growing = false,
  bool ended = false,
  bool asked = false,
  bool spinning = false,
  bool copyCodeBlocks = false,
  bool runCodeBlocks = false,
  String? shellStopKey,
  String? expandKey = 'ctrl+o',
  PathView? paths,
  String? agent,
  String? chordServer,
  Map<String, Color> agentColours = const {},
  SettingsStyles settingsStyles = const (
    warning: Style.plain,
    success: Style.plain,
  ),
  List<model.Subagent> group = const [],
  List<model.PermissionWait> waits = const [],
  SelectionSource? previous,
}) {
  final b = SourceBuilder(id, revision, previous);
  switch (entry) {
    case model.HistoryOmittedEntry():
      b.gap('gap');
      b.text(
        'omitted',
        const TextSpan(model.HistoryOmittedEntry.message),
        left: 2,
      );
    case model.ShellEntry(:final run):
      final view = shellView(run, true, shellStopKey);
      b.gap('gap');
      b.text('shell-command', TextSpan(run.command), left: 2);
      for (final stderr in [false, true]) {
        final lines = view.lines
            .where((line) => line.stderr == stderr)
            .toList();
        if (lines.isNotEmpty) {
          b.text(
            stderr ? 'shell-stderr' : 'shell-stdout',
            TextSpan(lines.map((line) => line.text).join('\n')),
            left: 5,
          );
        }
      }
      if (view.note case final note?) {
        b.text('shell-note', TextSpan(note.text), left: 5, selectable: false);
      }
    // A monitor's lines select as it printed them; the fold and chord's
    // sentence do not.
    case model.UserEntry(:final text, :final from?) when from.monitor != null:
      b.gap('gap');
      monitorBody(
        b,
        text,
        width,
        ended: from.monitor!.end != null,
        expanded: expanded,
        expandKey: expandKey,
      );
    // A message's words select; its arrow and who it is from do not.
    case model.UserEntry(:final text, from: _?):
      b.gap('gap');
      messageBody(
        b,
        text,
        width,
        folds: false,
        copyCodeBlocks: copyCodeBlocks,
        runCodeBlocks: runCodeBlocks,
      );
    case model.UserEntry(:final text):
      b.gap('gap');
      b.text('user', TextSpan(text), left: 2);
    case model.SelfStartedEntry(:final alone, :final from):
      if (alone) b.gap('gap');
      b.text(
        'self-started',
        TextSpan(
          selfStartedLine((width - (alone ? 2 : 5)).clamp(0, unbounded), from),
        ),
        left: alone ? 2 : 5,
        selectable: false,
        softWrap: false,
        maxLines: 1,
      );
    case model.AssistantEntry(:final text):
      b.gap('gap');
      b.markdown(
        'assistant',
        stripAnsi(text.text),
        left: 2,
        growing: growing,
        copyCodeBlocks: copyCodeBlocks,
        runCodeBlocks: runCodeBlocks,
      );
    case model.ThoughtEntry(:final text):
      b.gap('gap');
      b.text(
        'thinking',
        const TextSpan('Thinking…'),
        left: 2,
        selectable: false,
      );
      if (expanded) b.text('thought', parseAnsi(text.text.trim()), left: 2);
    case model.NotedEntry() ||
        model.TypedCallEntry() ||
        model.TeamShownEntry() ||
        model.LeftOpenEntry() ||
        model.MonitorsLeftEntry() ||
        model.ForkedEntry() ||
        model.ReportEntry() ||
        model.ElicitationEntry() ||
        model.ItemEndedEntry():
      return b.finish();
    // Outcomes and failures select nothing, but hold their rows, so what
    // is drawn after them in a subagent's work is found where it is.
    case model.PermissionEntry():
      outcome(b, permissionOutcome(entry).text);
    case model.CancelledEntry():
      outcome(b, 'Interrupted by user');
    case model.StoppedEntry(:final reason):
      outcome(b, 'Stopped: $reason');
    case model.NoticeEntry(:final title, :final description):
      b.gap('gap');
      b.text('notice', parseAnsi(title), left: 2, selectable: false);
      if (description != null) {
        b.text(
          'notice-description',
          parseAnsi(noticeDescription(description)),
          left: 2,
          selectable: false,
        );
      }
    case model.ErrorEntry(:final message, signIn: final signIn?):
      final name = agent ?? 'agent';
      b.gap('gap');
      b.text(
        'failure',
        parseAnsi('$name needs a sign-in: $message'),
        left: 2,
        selectable: false,
      );
      signInSource(b, name, signIn);
    case model.ErrorEntry(:final message) || model.WarningEntry(:final message):
      b.gap('gap');
      b.text('failure', parseAnsi(message), left: 2, selectable: false);
    // A subagent's title and task are the agent's words; its work, rows and
    // counts are furniture here. The group's first entry holds them all.
    case model.SubagentEntry():
      if (group.isNotEmpty) {
        agentsSource(
          b,
          group,
          width: width,
          open: expanded,
          waits: waits,
          agent: agent,
          copyCodeBlocks: copyCodeBlocks,
          runCodeBlocks: runCodeBlocks,
          expandKey: expandKey,
        );
      }
    // A message's words select; its arrow and who it is from do not.
    case model.AgentMessageEntry(:final text, :final toSubagent, :final launch):
      b.gap('gap');
      messageBody(
        b,
        text,
        width,
        folds: toSubagent && launch && !expanded,
        copyCodeBlocks: copyCodeBlocks,
        runCodeBlocks: runCodeBlocks,
      );
    case model.ChildMessageEntry(:final text):
      b.gap('gap');
      messageBody(
        b,
        text,
        width,
        folds: false,
        copyCodeBlocks: copyCodeBlocks,
        runCodeBlocks: runCodeBlocks,
      );
    // The line is furniture; the instructions under ctrl+o select, as the
    // original's do.
    case model.TeamPartEntry(:final part):
      b.gap('gap');
      b.text(
        'team-part',
        TextSpan(teamPartLine(part, expanded, expandKey)),
        left: 2,
        selectable: false,
      );
      if (expanded) {
        b.text('team-instructions', parseAnsi(part.text), left: 2);
      }
    // The spinner says one running in the turn; the line is furniture, the
    // summary under ctrl+o the agent's words, as a reply's are.
    case model.CompactionEntry(:final compaction):
      if (spinning) return b.finish();
      final line = compactionLine(compaction, expanded, expandKey);
      if (line.tone == CompactionTone.running) {
        b.gap('gap');
        b.text('compaction', TextSpan(line.text), left: 2, selectable: false);
        return b.finish();
      }
      b.text('compaction', TextSpan(line.text), left: 5, selectable: false);
      final summary = compaction.summary.trim();
      if (expanded && summary.isNotEmpty) {
        b.markdown(
          'summary',
          stripAnsi(summary),
          left: 5,
          copyCodeBlocks: copyCodeBlocks,
          runCodeBlocks: runCodeBlocks,
        );
      }
    case model.FinishedPlanEntry(:final entries):
      b.gap('gap');
      b.text(
        'plan-title',
        const TextSpan('Plan'),
        left: 2,
        selectable: false,
        softWrap: false,
        maxLines: 1,
      );
      final counts = <String, int>{};
      for (final step in entries) {
        counts.update(step.content, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final step in entries) {
        final key = counts[step.content] == 1
            ? ('plan-step', step.content)
            : Object();
        b.text(
          key,
          parseAnsi(step.content),
          left: 7,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.middle,
        );
      }
    case model.ToolEntry(:final call):
      if (guardianView(call) == GuardianView.hidden) return b.finish();
      b.gap('gap');
      if (guardianView(call) == GuardianView.reviewing) {
        b.text(
          'guardian',
          const TextSpan(guardianReviewing),
          left: 2,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.middle,
          selectable: false,
        );
        return b.finish();
      }
      final line = foldedSettingsNote(
        headline(call, chordServer: chordServer),
        call.chord,
        expanded: expanded,
        key: expandKey,
      );
      // The recipient's colour as the drawn row has it.
      b.text(
        'headline',
        headlineSpan(line, colour: line.sent ? agentColours[line.name] : null),
        left: 2,
      );
      // A sent message's words select as a received one's do; why it
      // failed is furniture after them.
      if (sentBody(call, chordServer: chordServer) case final sent?) {
        b.nested(
          'message',
          (id, previous) => messageSource(
            sent.text,
            id: id,
            revision: b.revision,
            previous: previous,
          ),
          left: 5,
        );
        if (sent.ending case final ending?) {
          b.text('ending', TextSpan(ending), left: 5, selectable: false);
        }
        return b.finish();
      }
      if (call.plan case final plan?) {
        planSource(b, plan, agent ?? plan.wait.agent.name);
        return b.finish();
      }
      if (call.review case final review?) {
        b.text(
          'review',
          TextSpan('Reviewed: ${review.outcome}'),
          left: 5,
          selectable: false,
        );
      }
      // A proposal's rows are furniture, as the original's; a change's body
      // diff selects, its headline and code, as a tool's diff does. The
      // rows above hold their place, so the diff is found where it is.
      if (call.chord case final chord? when proposalOf(chord) != null) {
        final view = proposalOf(chord)!;
        final room = math.max(width - 7, 1);
        b.text(
          'proposal',
          TextSpan(
            proposalHead(view, expanded: expanded, width: room).join('\n'),
          ),
          left: 5,
          softWrap: false,
          selectable: false,
        );
        if (proposalChange(view) case final diff?) {
          b.text(
            'proposal-change',
            TextSpan(bodyChangeLine(view.name, diff.view)),
            left: 5,
          );
          b.diff('proposal-diff', diff);
        }
        if (savedLine(view) case final saved?) {
          b.text(
            'proposal-saved',
            TextSpan(saved.text),
            left: 5,
            selectable: false,
          );
        }
        return b.finish();
      }
      // What a settings call read or changed, selectable as its rows are
      // drawn: labels dim, values in their tone's style.
      if (call.chord case final chord?) {
        final rows = settingsRows(
          chord,
          expanded: expanded,
          width: math.max(width - 7, 1),
        );
        if (rows != null) {
          b.text(
            'settings',
            TextSpan(
              '',
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const TextSpan('\n'),
                  TextSpan(row.label, style: const Style(dim: true)),
                  TextSpan(
                    row.text,
                    style: switch (row.tone) {
                      SettingsTone.warning => settingsStyles.warning,
                      SettingsTone.success => settingsStyles.success,
                      SettingsTone.dim => const Style(dim: true),
                      SettingsTone.text => Style.plain,
                    },
                  ),
                ],
              ],
            ),
            left: 5,
            softWrap: false,
          );
          return b.finish();
        }
      }
      // Wrapped as the drawn rows are, by wrap-ansi at the room under `⎿`,
      // a break only at a space: the text's own soft wrap would break
      // after an opening bracket.
      final view = summary(
        call,
        expanded,
        ended: ended,
        asked: asked,
        width: math.max(width - 7, 1),
        chordServer: chordServer,
      );
      if (view.lines.isNotEmpty) {
        b.text(
          'output',
          _glyphLines(view.rows),
          left: 5,
          right: 2,
          softWrap: false,
        );
      }
      if (view.hidden > 0) {
        b.text(
          'folded-output',
          TextSpan(foldedLine(view.hidden, expandKey)),
          left: 5,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.middle,
          selectable: false,
        );
      }
      for (final terminal in view.terminals) {
        if (terminal.lines.isNotEmpty) {
          b.text(
            ('terminal', terminal.id),
            TextSpan(terminal.lines.join('\n')),
            left: 5,
            right: 2,
          );
        }
        if (terminal.hidden > 0) {
          b.text(
            ('terminal-folded', terminal.id),
            TextSpan(foldedLine(terminal.hidden, expandKey)),
            left: 5,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.middle,
            selectable: false,
          );
        }
        if (terminal.note case final note?) {
          b.text(
            ('terminal-note', terminal.id),
            TextSpan(note.text),
            left: 5,
            selectable: false,
          );
        }
      }
      for (final diff in view.diffs) {
        final role = view.diffs.where((d) => d.path == diff.path).length == 1
            ? diff.path
            : Object();
        b.text(
          ('diff-headline', role),
          TextSpan(diffHeadline(diff, path: shownFile(diff.path, paths))),
          left: 5,
        );
        b.diff(('diff', role), diff);
      }
  }
  return b.finish();
}

/// Wrapped [rows] as one text, each glyph keeping its style.
TextSpan _glyphLines(List<List<Glyph>> rows) => TextSpan(
  '',
  children: [
    for (final (i, row) in rows.indexed) ...[
      if (i > 0) const TextSpan('\n'),
      for (final glyph in row) TextSpan(glyph.text, style: glyph.style),
    ],
  ],
);

/// [root]'s child [role], or null where the source left it out.
SelectionSource? selectionChildOrNull(SelectionSource root, Object role) {
  final id = (root.id, role);
  SelectionSource? find(SelectionSource source) {
    if (source.id == id) return source;
    for (final child in source.children) {
      if (find(child) case final found?) return found;
    }
    return null;
  }

  for (final child in root.children) {
    if (find(child) case final found?) return found;
  }
  return null;
}

/// The key a subagent's work item is drawn under.
Object workKey(model.Subagent subagent, WorkItem item) => switch (item) {
  WorkEntry(:final entry) => ('work', entry.identity),
  WorkAgents(:final agents) => ('work-agents', agents.first.id),
  WorkPlan() => ('work-plan', subagent.id),
};

/// Whether an entry's source holds every row it draws, so rows after it
/// can be found.
bool _mirrored(model.Entry entry) => switch (entry) {
  model.ToolEntry() ||
  model.AssistantEntry() ||
  model.ThoughtEntry() ||
  model.UserEntry() ||
  model.ShellEntry() ||
  model.FinishedPlanEntry() ||
  model.AgentMessageEntry() ||
  model.ChildMessageEntry() ||
  model.PermissionEntry() ||
  model.CancelledEntry() ||
  model.StoppedEntry() ||
  model.ErrorEntry() ||
  model.WarningEntry() ||
  model.NoticeEntry() ||
  model.CompactionEntry() => true,
  _ => false,
};

/// The rows [agents] draw, a lone block or a group's tree, as
/// `agents/agents.dart` lays them out at the item's [width]: titles and
/// tasks select, and an open block's work is its entries' own sources.
/// After work whose rows no source holds, nothing more is bound.
void agentsSource(
  SourceBuilder b,
  List<model.Subagent> agents, {
  required int width,
  required bool open,
  required List<model.PermissionWait> waits,
  String? agent,
  bool copyCodeBlocks = false,
  bool runCodeBlocks = false,
  String? expandKey = 'ctrl+o',
}) {
  var lost = false;
  var pads = 0;
  // A row of furniture, which selects nothing but takes its place; [key]
  // names it where a jump looks for it.
  void row(int left, [Object? key]) {
    if (lost) return;
    b.text(
      key ?? ('agent-pad', pads++),
      const TextSpan('·'),
      left: left,
      selectable: false,
      softWrap: false,
      maxLines: 1,
    );
  }

  void words(String text, int left) {
    if (lost) return;
    b.text(
      ('agent-pad', pads++),
      parseAnsi(text),
      left: left,
      selectable: false,
    );
  }

  void task(model.Subagent subagent, int left) {
    if (lost) return;
    if (taskOf(subagent) case final task?) {
      b.text(('agent-task', subagent.id), parseAnsi(task), left: left);
    }
  }

  void note(model.Subagent subagent, int left) {
    if (endNote(subagent) case final note?) words(note.text, left);
  }

  void work(model.Subagent subagent, int left) {
    bool asks(String callId) => waits.any(
      (wait) => wait.toolCallId == callId && wait.subagentId == subagent.id,
    );
    for (final item in workOf(subagent)) {
      if (lost) return;
      if (item is WorkEntry && !_mirrored(item.entry)) {
        lost = true;
        return;
      }
      b.nested(workKey(subagent, item), (id, previous) {
        final inner = width - left;
        switch (item) {
          case WorkAgents(:final agents):
            final nb = SourceBuilder(id, b.revision, previous);
            agentsSource(
              nb,
              agents,
              width: inner,
              open: false,
              waits: waits,
              agent: agent,
              copyCodeBlocks: copyCodeBlocks,
              runCodeBlocks: runCodeBlocks,
              expandKey: expandKey,
            );
            return nb.finish();
          case WorkPlan(:final entries):
            final entry = model.FinishedPlanEntry(subagent.id, entries);
            return entrySelectionSource(
              entry,
              id: id,
              revision: b.revision,
              width: inner,
              expanded: true,
              agent: agent,
              previous: previous,
            );
          case WorkEntry(:final entry):
            final call = entry is model.ToolEntry ? entry.call : null;
            return entrySelectionSource(
              entry,
              id: id,
              revision: b.revision,
              width: inner,
              expanded: true,
              ended:
                  call != null &&
                  endingOf(subagent.state) != null &&
                  !asks(call.id),
              asked: call != null && asks(call.id),
              copyCodeBlocks: copyCodeBlocks,
              runCodeBlocks: runCodeBlocks,
              expandKey: expandKey,
              agent: agent,
              previous: previous,
            );
        }
      }, left: left);
    }
  }

  b.gap('gap');
  if (agents.length == 1) {
    final subagent = agents.single;
    b.text('agent-title', headlineSpan(agentHeadline(subagent)), left: 2);
    if (open) {
      task(subagent, 5);
      work(subagent, 5);
      if (endedLine(subagent) case final ended?) words(ended.text, 5);
      note(subagent, 5);
      return;
    }
    switch (blockFold(subagent, waits)) {
      case FoldEnded(:final text):
        words(text, 5);
        if (subagent.addressed &&
            subagent.state == model.SubagentState.failed) {
          note(subagent, 5);
        }
      case FoldStarting():
        row(5);
      case FoldWork(:final lines, :final more):
        for (final _ in lines) {
          row(5);
        }
        if (more > 0) row(5);
    }
    return;
  }
  row(2);
  for (final subagent in agents) {
    for (final (at, runs) in groupRow(subagent, width - 5).indexed) {
      if (lost) return;
      if (runs.every((run) => run.counts)) {
        // A jump to this agent finds its row by it.
        row(5, ('agent-row-pad', subagent.id, at));
      } else {
        b.text(
          ('agent-row', subagent.id, at),
          rowSpan(runs, counts: false),
          left: 5,
          softWrap: false,
          maxLines: 1,
        );
      }
    }
    if (open) {
      task(subagent, 8);
      work(subagent, 8);
      if (endingOf(subagent.state) case final ending?) words(ending.word, 8);
      note(subagent, 8);
    } else {
      row(8);
      if (subagent.addressed && subagent.state == model.SubagentState.failed) {
        note(subagent, 8);
      }
    }
  }
}

/// A message's words under its arrow at the item's [width], as Markdown;
/// while it [folds] past [messageLines] rows, its code has no controls.
void messageBody(
  SourceBuilder b,
  String text,
  int width, {
  required bool folds,
  bool copyCodeBlocks = false,
  bool runCodeBlocks = false,
}) {
  // Its arrow and who it is from or to, one row of furniture.
  b.text(
    'message-head',
    const TextSpan('·'),
    selectable: false,
    softWrap: false,
    maxLines: 1,
  );
  final hides = messageHidden(text, width, folds: folds) > 0;
  b.nested(
    'message',
    (id, previous) => messageSource(
      text,
      id: id,
      revision: b.revision,
      copyCodeBlocks: copyCodeBlocks && !hides,
      runCodeBlocks: runCodeBlocks && !hides,
      previous: previous,
    ),
    left: 5,
  );
}

/// A monitor's event under its arrow, as `monitorMessage` lays it out at
/// the item's [width].
void monitorBody(
  SourceBuilder b,
  String text,
  int width, {
  required bool ended,
  required bool expanded,
  String? expandKey,
}) {
  b.text(
    'message-head',
    const TextSpan('·'),
    selectable: false,
    softWrap: false,
    maxLines: 1,
  );
  final (:lines, :hidden, :sentence) = monitorMessage(
    text,
    ended: ended,
    expanded: expanded,
    width: math.max(width - 5, 1),
  );
  if (lines.isNotEmpty) {
    b.text(
      'monitor-lines',
      TextSpan(
        [for (final line in lines) line.isEmpty ? ' ' : line].join('\n'),
      ),
      left: 5,
      softWrap: false,
    );
  }
  if (hidden > 0) {
    b.text(
      'monitor-folded',
      TextSpan(foldedLine(hidden, expandKey)),
      left: 5,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.middle,
      selectable: false,
    );
  }
  if (sentence != null) {
    b.text(
      'monitor-sentence',
      TextSpan(sentence),
      left: 5,
      softWrap: false,
      selectable: false,
    );
  }
}

/// The rows a `SignInBlock` for [agent]'s [signIn] holds, none selectable.
void signInSource(SourceBuilder b, String agent, SignIn signIn) {
  if (accountReported(agent, signIn.account) case final account?) {
    b.text('sign-in-account', TextSpan(account), left: 5, selectable: false);
  }
  if (signIn.ways.isNotEmpty) {
    b.text(
      'sign-in-offers',
      TextSpan(offersLine(agent, signIn.ways.length)),
      left: 5,
      selectable: false,
    );
  }
  for (final (i, way) in signIn.ways.indexed) {
    b.text(
      ('sign-in-way', i),
      TextSpan(
        '',
        children: [
          if (way.name case final name?)
            TextSpan('', style: Style.bold, children: [parseAnsi(name)]),
          if (way.name != null && way.description != null)
            const TextSpan(' · '),
          if (way.description case final description?) parseAnsi(description),
        ],
      ),
      left: 7,
      selectable: false,
    );
  }
  b.text('sign-in-way-on', TextSpan(wayOn(agent)), left: 5, selectable: false);
}

/// A result line under the entry before it, as `Outcome` draws it.
void outcome(SourceBuilder b, String text) =>
    b.text('outcome', parseAnsi(text), left: 5, selectable: false);
