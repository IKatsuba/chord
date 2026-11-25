/// `/team`, kept out of the window: the teams picker's rows, its line and
/// hint, and `/team show`'s table of a running team. Nothing here reads a
/// file or a session; the window gathers what each needs. From the
/// original's `ui/teams/teams.ts`.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart'
    show PickerItem, TextLayout, TextSpan, cellWidth;

import '../../js_trim.dart';
import '../../session/team_command.dart';
import '../../session/transcript/types.dart';
import '../../teams.dart';
import '../agents/glyphs.dart';
import '../transcript/message.dart' show messageHeader;
import 'cliffy_row.dart';

/// What `/team` says of runs, in the window's words.
const TeamWords teamWords = (
  whichRun: 'Which run? The list under the prompt names them',
  closedLead: '/resume lists it',
  closedRun: '/resume lists them',
  noRun: 'the list under the prompt names them',
);

/// A call's headline as one line: `Edit(src/a.ts)`, `→ to @coder`.
String headlineText({
  required String name,
  String? arg,
  String tag = '',
  bool sent = false,
}) => sent
    ? '→ to @$name'
    : arg == null
    ? '$name$tag'
    : '$name$tag($arg)';

/// An incoming message's headline, as its row's header:
/// `← from @tester · claude`.
String messageHeadline(MessageFrom from) {
  final (:word, :name, :rest) = messageHeader(from);
  return '← $word$name$rest';
}

/// `✻ working 6m` for one run, `✻ 2 runs` for more, nothing for none.
String runningWords(List<TeamRun> runs, num now) => runs.isEmpty
    ? ''
    : runs.length == 1
    ? '${WaitGlyph.working.glyph} working ${briefly(now - runs.single.since)}'
    : '${WaitGlyph.working.glyph} ${runs.length} runs';

/// Below this many columns the picker drops the runtimes and half its
/// hint.
const narrowColumns = 100;

/// Between columns, as `chord agents` has it.
const _gap = '  ';

String _padded(String text, int width) =>
    text + ' ' * math.max(0, width - cellWidth(text));

int _widest(Iterable<String> texts) =>
    texts.fold(0, (widest, text) => math.max(widest, cellWidth(text)));

/// The picker's rows, a team each, by name: its size and runtimes, where it
/// is saved, whether it runs in this window and its description, in
/// columns; a broken file's problem across them and its path where the
/// description goes. Below [narrowColumns] the runtimes and a broken file's
/// path go. The value is the team's name.
List<PickerItem<String>> teamChoices(
  List<ListedTeam> teams,
  List<TeamRun> runs,
  num now,
  int columns,
) {
  final narrow = columns < narrowColumns;
  String sizeOf(Team team) {
    final runtimes = {
      team.lead.agent,
      for (final member in team.members) member.agent,
    };
    final size = '${team.members.length + 1} agents';
    return narrow ? size : '$size · ${runtimes.join(', ')}';
  }

  String placeOf(FoundTeam found) => found.place == TeamPlace.user
      ? 'every project'
      : found.hides
      ? "this project · hides every project's"
      : 'this project';
  final running = [
    for (final listed in teams)
      runningWords([
        for (final run in runs)
          if (run.team == listed.found.name) run,
      ], now),
  ];
  final names = _widest(teams.map((listed) => listed.found.name));
  final sizes = _widest([
    for (final listed in teams)
      if (listed.found.team case final team?) sizeOf(team),
  ]);
  final places = _widest([
    for (final listed in teams)
      if (listed.found.team != null) placeOf(listed.found),
  ]);
  final runnings = _widest(running);
  String problemOf(String problem) =>
      '${WaitGlyph.failed.glyph} not read: $problem';
  // Where the description starts, for a broken file's path to start there
  // too: after the columns before it, or a wider problem.
  final before = [
    [
      sizes,
      places,
      runnings,
    ].where((width) => width > 0).fold(0, (sum, width) => sum + width + 2),
    for (final listed in teams)
      if (listed.found.problem case final problem? when !narrow)
        cellWidth(problemOf(problem)) + _gap.length,
  ].reduce(math.max);
  return [
    for (final (index, listed) in teams.indexed)
      () {
        final found = listed.found;
        final name = _padded(found.name, names);
        if (found.problem case final problem?) {
          final said = problemOf(problem);
          return PickerItem(
            value: found.name,
            label: narrow
                ? '$name$_gap$said'
                : '$name$_gap${_padded(said, before - _gap.length)}'
                      '$_gap${listed.shown}',
          );
        }
        final head = [
          _padded(sizeOf(found.team!), sizes),
          _padded(placeOf(found), places),
          if (runnings > 0) _padded(running[index], runnings),
        ].join(_gap);
        return PickerItem(
          value: found.name,
          label: [
            name,
            _padded(head, before - _gap.length),
            found.team!.description,
          ].join(_gap),
        );
      }(),
  ];
}

/// The picker's line under its title: where teams are saved.
String teamsWhere(({String project, String? user}) dirs, int columns) =>
    dirs.user != null && columns < narrowColumns
    ? 'For this project in ${dirs.project}, for every project in '
          '${dirs.user}.'
    : teamsSaved(dirs);

/// The picker's hint for the team under the highlight, before its close
/// hint. A broken file takes no job, so its hint says how it gets fixed
/// instead of offering Enter: teams are changed by asking main.
List<String> teamsHint(FoundTeam? found, int columns) {
  final narrow = columns < narrowColumns;
  if (found == null) return const [];
  if (found.problem != null) {
    return [
      narrow
          ? 'Ask main to fix ${found.name}'
          : 'Fix the file, or ask main to fix ${found.name}',
    ];
  }
  return narrow
      ? const ['Enter to hand it a job']
      : const ['Enter to hand it a job', '/team show <name>'];
}

/// What Enter on a team puts in the draft: a run's start. A broken file has
/// nothing to start, so Enter on it leaves the picker open.
String? pickedDraft(FoundTeam found) =>
    found.problem != null ? null : '/team run ${found.name} ';

/// [text] wrapped to [width] as wrap-ansi with `hard` and `trim` does.
List<String> _wrapHard(String text, int width) => [
  for (final row in TextLayout.wrapAnsi(
    TextSpan(text),
    math.max(1, width),
    hard: true,
  ).lines)
    row.map((glyph) => glyph.text).join(),
];

/// The lines `/team show` opens a running team with: its name, its file
/// and how long it has worked on what, the whole job wrapped to [width].
List<String> runningHeader(
  String name,
  String file,
  TeamRunShown run,
  int width,
) {
  final job = jsTrim(run.job.replaceAll(RegExp(r'\s+'), ' '));
  return _wrapHard(
    '$name · $file · working ${briefly(run.at - run.since)} on "$job"',
    width,
  );
}

/// One running agent's row laid out, and where its state is in it.
final class RunningLine {
  /// [agent]'s row: [text], then the lines [under] it.
  const RunningLine({
    required this.text,
    required this.state,
    required this.stateLine,
    required this.markLine,
    required this.under,
    required this.agent,
    this.mark,
  });

  final String text;

  /// The state, `[start, end)` as string indices in its line, to paint by
  /// its tone: [text], or the line of [under] that [stateLine] names.
  final (int, int) state;

  /// Which line the state is on: 0 for [text], else [under]'s, from 1.
  final int stateLine;

  /// Its mark after the state, in the line [markLine] names.
  final (int, int)? mark;
  final int markLine;

  /// The row's further lines: its wrapped cells, its state where the row
  /// had no room for it, and its latest headline, wrapped.
  final List<String> under;
  final TeamAgentShown agent;
}

/// What a member not open says in the state column.
const notOpened = 'not opened';

/// The least of the latest headline's column kept beside the row; with
/// less the headline goes under the row.
const _beside = 20;

/// `/team show`'s running table: each agent's name, `runtime · model ·
/// effort` and mode from the file, then its state, its mark and its latest
/// headline. Nothing is cut: the headline wraps in its column while that
/// keeps `_beside` cells, and under the row from the runtime's column where
/// it would not. Where the row's own columns are wider than [width], the
/// runtime's and then the name's wrap in a third of it; if that is not
/// enough the state and mark go whole under the row, and then the mode
/// before them, that line wrapping between its parts.
List<RunningLine> runningTable(
  Team team,
  List<TeamAgentShown> agents,
  int width,
) {
  ({String agent, String? model, String? effort, String? mode})? defined(
    TeamAgentShown agent,
  ) {
    if (agent.lead) {
      final lead = team.lead;
      return (
        agent: lead.agent,
        model: lead.model,
        effort: lead.effort,
        mode: lead.mode,
      );
    }
    for (final member in team.members) {
      if (member.name == agent.name) {
        return (
          agent: member.agent,
          model: member.model,
          effort: member.effort,
          mode: member.mode,
        );
      }
    }
    return null;
  }

  String ownState(TeamAgentShown agent) => !agent.open
      ? notOpened
      : switch (agent.state) {
          null => 'idle',
          final state => '${state.glyph} ${state.words}',
        };
  String? markOf(TeamAgentShown agent) => agent.open && agent.mark != null
      ? '${agent.mark!.glyph} ${agent.mark!.words}'
      : null;
  // Each state padded where a mark follows, so the marks start in one
  // column.
  final stateWidth = _widest(agents.map(ownState));
  String stateOf(TeamAgentShown agent) {
    final mark = markOf(agent);
    return mark == null
        ? ownState(agent)
        : '${_padded(ownState(agent), stateWidth)}$_gap$mark';
  }

  if (agents.isEmpty) return const [];
  // Name, runtime · model · effort, mode, then state and mark.
  final cells = [
    for (final agent in agents)
      () {
        final file = defined(agent);
        return [
          agent.name,
          [?file?.agent, ?file?.model, ?file?.effort].join(' · '),
          file?.mode ?? '—',
          stateOf(agent),
        ];
      }(),
  ];
  final widths = [
    for (var column = 0; column < 4; column++)
      _widest(cells.map((row) => row[column])),
  ];
  int across(List<int> some) =>
      some.fold(0, (sum, each) => sum + each + _gap.length) - _gap.length;
  final third = math.max(1, width ~/ 3);
  // The runtime's column, then the name's, wrap in a third of the width
  // while the row's own columns are wider than it.
  for (final column in [1, 0]) {
    if (across(widths) > width && widths[column] > third) {
      widths[column] = third;
    }
  }
  // Still wider, the state goes under the row, and then the mode with it.
  final kept = across(widths) <= width
      ? 4
      : across(widths.sublist(0, 3)) <= width
      ? 3
      : 2;
  final room = kept == 4 ? width - across(widths) - _gap.length : 0;
  final beside = room >= _beside;
  final runtimeAt = widths[0] + _gap.length;
  // Beside, after the state's column; under, from the runtime's.
  final latestAt = beside ? width - room : runtimeAt;
  final columns = widths.sublist(0, kept);
  return [
    for (final (index, agent) in agents.indexed)
      () {
        final row = cells[index];
        final own = [
          for (final line in cliffyRow([
            for (final cell in row.sublist(0, kept)) CliffyCell(cell),
          ], columns))
            line.trimRight(),
        ];
        final state = ownState(agent);
        final mark = markOf(agent);
        // Under the row from the runtime's column: the mode where it went
        // too, the state and the mark, each whole, a line wrapping between
        // them.
        final parts = [
          if (kept == 2) _padded(row[2], widths[2]),
          mark == null ? state : _padded(state, stateWidth),
          ?mark,
        ];
        final placed = <({int line, int at})>[];
        final down = <String>[];
        if (kept < 4) {
          final indent = ' ' * runtimeAt;
          for (final part in parts) {
            final last = down.isEmpty ? null : down.last;
            // String indices, not cells, for the paint.
            if (last != null &&
                cellWidth('$last$_gap$part'.trimRight()) <= width) {
              placed.add((line: down.length - 1, at: last.length + 2));
              down[down.length - 1] = '$last$_gap$part';
            } else {
              placed.add((line: down.length, at: indent.length));
              down.add(indent + part);
            }
          }
        } else {
          // The state's cell ends the row's first line, before a headline
          // beside it; a wide character before it is two cells and one or
          // two code units, so its place is counted from the end.
          final cell = row[3];
          final at = own.first.length - cell.length;
          placed
            ..add((line: 0, at: at))
            ..add((line: 0, at: at + cell.length - (mark?.length ?? 0)));
        }
        final latest = jsTrim(
          (agent.latest ?? '').replaceAll(RegExp(r'\s+'), ' '),
        );
        final wrapped = latest.isEmpty
            ? const <String>[]
            : _wrapHard(latest, width - latestAt);
        final lines = beside
            ? [
                for (
                  var at = 0;
                  at < math.max(own.length, wrapped.length);
                  at++
                )
                  at < wrapped.length
                      ? _padded(at < own.length ? own[at] : '', latestAt) +
                            wrapped[at]
                      : own[at],
              ]
            : [
                ...own,
                for (final line in down) line.trimRight(),
                for (final line in wrapped) ' ' * latestAt + line,
              ];
        final below = kept < 4 ? own.length : 0;
        final statePlace = placed[kept == 2 ? 1 : 0];
        final markPlace = placed.last;
        return RunningLine(
          text: lines.first,
          state: (statePlace.at, statePlace.at + state.length),
          stateLine: below + statePlace.line,
          mark: mark == null
              ? null
              : (markPlace.at, markPlace.at + mark.length),
          markLine: below + markPlace.line,
          under: lines.sublist(1),
          agent: agent,
        );
      }(),
  ];
}
