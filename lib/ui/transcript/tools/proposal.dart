/// A team as a table of its agents, as `propose_team`'s call and `/team
/// show` draw it, kept out of the widgets: name, `runtime · model`, effort
/// where any agent sets one, mode and role, laid out as @cliffy/table lays
/// it out, the role narrowed first, then a changed effort's `was`, then the
/// model, the effort and mode never; or opened, each role whole on lines of
/// its own under its row. From the original's
/// `ui/transcript/tools/proposal.ts`; its folding helpers, which nothing
/// draws since the original's CHD-422, are not ported.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart' show DiffView, TextSpan, cellWidth;

import '../../../js_trim.dart';
import '../../../session/team_command.dart' show leadRole;
import '../../../session/transcript/types.dart' show ChordCall, ChordTool;
import '../../../teams.dart';
import '../../teams/cliffy_row.dart';
import '../message.dart' show wrapLine;

/// Between columns, as `chord agents` has it.
const _padding = 2;

/// The role is cut no narrower than this before the model is cut too.
const _minRole = 12;

/// Modes that let an agent act without the person's ok, drawn as a warning.
const _unaskedModes = {'bypassPermissions', 'full-access'};

/// Whether [mode] skips the person's ok.
bool skipsAsking(String? mode) => mode != null && _unaskedModes.contains(mode);

/// A `propose_team` call's team, as its widget draws it.
final class ProposalView {
  /// Team [name], proposed new or as a change to [before].
  const ProposalView({
    required this.name,
    required this.team,
    required this.change,
    this.before,
    this.saved,
  });

  final String name;
  final Team team;

  /// A change to a team saved, not a new one.
  final bool change;

  /// The team saved before, for a change whose file was a team.
  final Team? before;

  /// Where it was saved, false when it was not; null while the box is open.
  final Object? saved;
}

/// The proposal a `propose_team` call drew, from what chord served: none
/// for another call, a refused one, or one not served yet. Its input passed
/// the check before it was served, so it is read as the team it is.
ProposalView? proposalOf(ChordCall call) {
  if (call.tool != ChordTool.proposeTeam ||
      call.error != null ||
      call.answer is! Map) {
    return null;
  }
  final input = call.input;
  final name = input['name'];
  final body = input['body'];
  if (name is! String || body is! String) return null;
  final team = teamFromJson({...input, 'body': jsTrim(body)});
  if (team == null) return null;
  final answer = call.answer! as Map;
  final saved = answer['saved'];
  return ProposalView(
    name: name,
    team: team,
    change: answer['proposal'] == 'change',
    before: teamFromJson(answer['before']),
    saved: saved is String || saved == false ? saved : null,
  );
}

/// The line the person's answer leaves under the call, and whether it says
/// it was saved; none while the box is open.
({String text, bool saved})? savedLine(ProposalView view) =>
    switch (view.saved) {
      null => null,
      false => (
        text: 'Not saved · the person will say what to change',
        saved: false,
      ),
      final saved => (
        text: 'Saved to $saved · /team run ${view.name} <job> hands it a job',
        saved: true,
      ),
    };

/// `bugfix.md's body · 1 addition, 1 removal`: a change the person has
/// not saved yet, so not an edit's `Updated …`, which reads as written.
String bodyChangeLine(String name, DiffView view) =>
    "$name.md's body · ${_counted(view.added, 'addition')}, "
    "${_counted(view.removed, 'removal')}";

String _counted(int count, String word) =>
    '$count $word${count == 1 ? '' : 's'}';

/// One agent of the team, as its row reads before it is laid out.
final class ProposalRow {
  /// A row of [name] on [runtime].
  const ProposalRow({
    required this.name,
    required this.runtime,
    required this.effort,
    required this.mode,
    required this.role,
    this.change,
    this.effortWas,
    this.was,
  });

  final String name;

  /// `claude · opus`, or the runtime alone.
  final String runtime;

  /// Its effort, or `—` where the runtime's own is used.
  final String effort;

  /// Its mode, or `—` where the runtime's own is used.
  final String mode;
  final String role;

  /// Against the team saved before; none for a new team or an unchanged
  /// row.
  final RowChange? change;

  /// The effort it had before, on a changed row whose effort changed.
  final String? effortWas;

  /// The mode it had before, on a changed row whose mode changed.
  final String? was;
}

/// No mode or effort set: the runtime starts on its own.
const _own = '—';

typedef _Defined = ({
  String agent,
  String? model,
  String? effort,
  String? mode,
});

_Defined _ofLead(TeamLead lead) => (
  agent: lead.agent,
  model: lead.model,
  effort: lead.effort,
  mode: lead.mode,
);

_Defined _ofMember(TeamMember member) => (
  agent: member.agent,
  model: member.model,
  effort: member.effort,
  mode: member.mode,
);

ProposalRow _agentRow(
  String name,
  _Defined agent,
  String role,
  RowChange? change, [
  _Defined? old,
]) {
  final effort = agent.effort ?? _own;
  final mode = agent.mode ?? _own;
  final changed = change == RowChange.changed;
  final effortWas = changed ? (old?.effort ?? _own) : effort;
  final was = changed ? (old?.mode ?? _own) : mode;
  return ProposalRow(
    name: name,
    runtime: [agent.agent, ?agent.model].join(' · '),
    effort: effort,
    mode: mode,
    role: role,
    change: change,
    effortWas: effortWas == effort ? null : effortWas,
    was: was == mode ? null : was,
  );
}

/// The team's rows, the lead first: against [before], each marked by how
/// it changed, with the members it no longer has after the rest.
List<ProposalRow> agentRows(Team team, [Team? before]) {
  final changes = before == null ? null : teamChanges(before, team);
  return [
    _agentRow(
      'lead',
      _ofLead(team.lead),
      leadRole,
      changes?.lead,
      before == null ? null : _ofLead(before.lead),
    ),
    for (final member in team.members)
      _agentRow(
        member.name,
        _ofMember(member),
        member.role,
        changes?.members[member.name],
        switch (before?.members.where((each) => each.name == member.name)) {
          final found? when found.isNotEmpty => _ofMember(found.first),
          _ => null,
        },
      ),
    for (final member in before?.members ?? const <TeamMember>[])
      if (changes?.members[member.name] == RowChange.removed)
        _agentRow(
          member.name,
          _ofMember(member),
          member.role,
          RowChange.removed,
        ),
  ];
}

/// A change's mark, before its row: `+` new, `~` changed, `-` gone.
const _marks = {
  RowChange.added: '+',
  RowChange.changed: '~',
  RowChange.removed: '-',
};

/// One line of a row laid out: its text, and where in it the mode is.
final class TableLine {
  /// A line of [row]'s.
  const TableLine({
    required this.text,
    required this.mode,
    required this.row,
    this.was,
    this.effortWas,
    this.role = false,
  });

  final String text;

  /// The mode's cells, `[start, end)` in [text]; empty on a row's later
  /// lines.
  final (int, int) mode;

  /// The mode it had before, after the mode: `[start, end)` in [text].
  final (int, int)? was;

  /// The effort it had before, after the effort: `[start, end)` in [text].
  final (int, int)? effortWas;

  /// A line of the role under its row, as an opened table draws it.
  final bool role;
  final ProposalRow row;
}

/// Between a changed mode and the one it had: `bypassPermissions was —`.
const _was = ' was ';

String _modeCell(ProposalRow row) =>
    row.was == null ? row.mode : '${row.mode}$_was${row.was}';

String _effortCell(ProposalRow row, [bool was = true]) =>
    row.effortWas == null || !was
    ? row.effort
    : '${row.effort}$_was${row.effortWas}';

/// Whether the table has an effort column: only where an agent sets one or
/// had one, so a team with none reads as it did before efforts.
bool _hasEfforts(List<ProposalRow> rows) =>
    rows.any((row) => row.effort != _own || row.effortWas != null);

/// A changed cell wider than its column, broken before `was`, so the new
/// value has a line of its own and is not read as the old one.
String _brokenBeforeWas(String cell, int room) => cellWidth(cell) <= room
    ? cell
    : cell.replaceFirst(_was, '\n${_was.trim()} ');

int _widest(Iterable<String> cells) =>
    cells.fold(0, (widest, cell) => math.max(widest, cellWidth(cell)));

int _widestWord(Iterable<String> cells) =>
    _widest([for (final cell in cells) ...cell.split(' ')]);

/// The rows laid out in columns no wider than [width], a change's with its
/// mark first when [marked]: the role narrowed first, down to `_minRole`,
/// then a changed effort's `was …` dropped, then agent · model narrowed,
/// each wrapping in its column, never cut; the name, effort and mode never.
/// [whole], each row's role goes on lines of its own under the row, from
/// the runtime's column to the right edge, and where the row would not fit
/// the mode, then the effort, then the runtime wrap in their columns, never
/// cut, a changed cell broken before its `was` first.
List<TableLine> proposalTable(
  List<ProposalRow> rows,
  int width, {
  bool marked = false,
  bool whole = false,
}) {
  String mark(ProposalRow row) =>
      row.change == null ? ' ' : _marks[row.change]!;
  final names = _widest(rows.map((row) => row.name));
  final modes = _widest(rows.map(_modeCell));
  final efforts = _hasEfforts(rows);
  final effortsWhole = efforts ? _widest(rows.map(_effortCell)) : 0;
  final named = marked ? 1 + _padding : 0;
  final runtimes = _widest(rows.map((row) => row.runtime));
  final roles = whole ? 0 : _widest(rows.map((row) => row.role));
  final leastRole = math.min(_minRole, roles);
  final base = named + names + _padding + modes + _padding;
  // Folded, a changed effort keeps its `was` only while the model stays
  // whole beside a role of `_minRole`: the `~` already says the row
  // changed.
  final effortWas =
      whole ||
      width - base - effortsWhole - _padding - runtimes - _padding >= leastRole;
  final effortsWidth = efforts
      ? effortWas
            ? effortsWhole
            : _widest(rows.map((row) => _effortCell(row, false)))
      : 0;
  final fixed = base + (efforts ? effortsWidth + _padding : 0);
  final roleRoom = math.max(width - fixed - runtimes - _padding, leastRole);
  final runtimeRoom = math.max(
    1,
    math.min(
      runtimes,
      width - fixed - (whole ? 0 : math.min(roles, roleRoom) + _padding),
    ),
  );
  if (rows.isEmpty) return const [];
  if (!whole) {
    // The two cells that wrap share what the row leaves, and the row is
    // never wider than [width]: agent · model keeps its longest word whole
    // and the role its least, wrapping in the rest. Where they cannot, the
    // table is laid out as opened.
    final shared = width - fixed - _padding;
    final runtimeWord = _widestWord(rows.map((row) => row.runtime));
    if (shared < math.min(runtimeWord, runtimes) + leastRole) {
      return proposalTable(rows, width, marked: marked, whole: true);
    }
    final runtimeColumn = math.min(
      runtimes,
      math.min(math.max(runtimeWord, runtimeRoom), shared - leastRole),
    );
    final roleColumn = math.max(1, math.min(roles, shared - runtimeColumn));
    final effortAt = named + names + _padding + runtimeColumn + _padding;
    final before = effortAt + (efforts ? effortsWidth + _padding : 0);
    final columns = [
      if (marked) 1,
      names,
      runtimeColumn,
      if (efforts) effortsWidth,
      modes,
      roleColumn,
    ];
    return [
      for (final row in rows)
        ...() {
          final lines = cliffyRow([
            if (marked) CliffyCell(mark(row)),
            CliffyCell(row.name),
            CliffyCell(row.runtime),
            if (efforts) CliffyCell(_effortCell(row, effortWas)),
            CliffyCell(_modeCell(row)),
            CliffyCell(row.role),
          ], columns);
          final from = effortAt + row.effort.length;
          final end = effortAt + _effortCell(row, effortWas).length;
          final first = _modeLine(lines.first, row, before);
          return [
            TableLine(
              text: first.text,
              mode: first.mode,
              was: first.was,
              effortWas: efforts && from < end ? (from, end) : null,
              row: row,
            ),
            for (final line in lines.skip(1))
              TableLine(text: line.trimRight(), mode: (0, 0), row: row),
          ];
        }(),
    ];
  }
  // Where the row does not fit, the mode cell wraps first, at its spaces
  // and never narrower than its longest word, then the effort cell
  // likewise, then agent · model, which breaks at its spaces while the
  // column holds its longest word and inside a word only below that.
  final room = width - named - names - _padding;
  final modeRoom = math.min(
    modes,
    math.max(
      _widestWord(rows.map(_modeCell)),
      room - runtimes - _padding - (efforts ? effortsWhole + _padding : 0),
    ),
  );
  final effortRoom = efforts
      ? math.min(
          effortsWhole,
          math.max(
            _widestWord(rows.map(_effortCell)),
            room - runtimes - _padding - modeRoom - _padding,
          ),
        )
      : 0;
  final agentRoom = math.max(
    1,
    math.min(
      runtimes,
      room - modeRoom - _padding - (efforts ? effortRoom + _padding : 0),
    ),
  );
  final effortAt = named + names + _padding + agentRoom + _padding;
  final before = effortAt + (efforts ? effortRoom + _padding : 0);
  // An empty last column takes what the row leaves of the width, so the
  // role spanning it and the runtime's and mode's reaches the right edge.
  // Where a mode leaves none, the row is wider than the width, as the mode
  // is never cut, and the role spans the runtime's and mode's columns only.
  final filler = width - before - modeRoom - _padding;
  final widths = [
    if (marked) 1,
    names,
    agentRoom,
    if (efforts) effortRoom,
    modeRoom,
    if (filler >= 0) filler,
  ];
  List<String> laid(List<CliffyCell> cells) => [
    for (final line in cliffyRow(cells, widths)) line.trimRight(),
  ];
  return [
    for (final row in rows)
      ...() {
        final lines = laid([
          if (marked) CliffyCell(mark(row)),
          CliffyCell(row.name),
          CliffyCell(row.runtime),
          if (efforts)
            CliffyCell(_brokenBeforeWas(_effortCell(row), effortRoom)),
          CliffyCell(_brokenBeforeWas(_modeCell(row), modeRoom)),
          if (filler >= 0) const CliffyCell(''),
        ]);
        final modeWases = _wasesIn(lines, _modeCell(row), row.mode, before);
        final effortWases = efforts
            ? _wasesIn(
                lines,
                _effortCell(row),
                row.effort,
                effortAt,
                effortRoom,
              )
            : const <(int, int)?>[];
        return [
          for (final (index, line) in lines.indexed)
            () {
              final was = modeWases[index];
              final effortWas = index < effortWases.length
                  ? effortWases[index]
                  : null;
              return TableLine(
                text: line,
                mode: index == 0
                    ? (before, before + row.mode.length)
                    : was == null
                    ? (0, 0)
                    : (was.$1, was.$1),
                was: row.was == null ? null : was,
                effortWas: row.effortWas == null ? null : effortWas,
                row: row,
              );
            }(),
          for (final line in laid([
            for (var i = 0; i < (marked ? 2 : 1); i++) const CliffyCell(''),
            CliffyCell(row.role, span: widths.length - (marked ? 2 : 1)),
          ]))
            TableLine(text: line, mode: (0, 0), row: row, role: true),
        ];
      }(),
  ];
}

/// Where a changed cell's `was …` landed on each of its row's lines, the
/// cell wrapped in its column of [room] from [start]: `[start, end)` in the
/// line, none on a line it is not on.
List<(int, int)?> _wasesIn(
  List<String> lines,
  String cell,
  String value,
  int start, [
  int room = 1 << 30,
]) {
  var read = 0;
  return [
    for (final line in lines)
      () {
        final end = math.min<int>(line.length, start + room);
        final part = start >= line.length
            ? ''
            : line.substring(start, end).trimRight();
        final at = part.isEmpty ? -1 : cell.indexOf(part, read);
        if (at < 0) return null;
        read = at + part.length;
        final from = start + math.max<int>(value.length, at) - at;
        final to = start + part.length;
        return from < to ? (from, to) : null;
      }(),
  ];
}

/// A row's first line, its mode at [before] and what it was after that.
TableLine _modeLine(String line, ProposalRow row, int before) {
  final end = before + row.mode.length;
  return TableLine(
    text: line.trimRight(),
    mode: (before, end),
    was: row.was == null ? null : (end, end + _was.length + row.was!.length),
    row: row,
  );
}

/// [line] wrapped to [width] as the original's `wrapLine`, as text.
List<String> wrapLineText(String line, int width) => [
  for (final row in wrapLine(TextSpan(line), width))
    row.map((glyph) => glyph.text).join(),
];

/// The lines ctrl+o adds after the table: each agent's instructions, under
/// its name, wrapped to [width] whole, as the person reviewing a team reads
/// all that the file holds.
List<String> instructionLines(Team team, int width) => [
  for (final (name, instructions) in [
    ('lead', team.lead.instructions),
    for (final member in team.members) (member.name, member.instructions),
  ])
    if (instructions != null)
      for (final line in [
        '',
        "$name's instructions",
        ...jsTrim(instructions).split('\n'),
      ])
        ...wrapLineText(line, width),
];

/// The lines after the table and how many ctrl+o adds: [expanded], each
/// agent's instructions, then the body's [blocks] with a blank line between
/// them; folded, the body's first [keep] lines read on without the blank
/// lines.
({List<String> lines, int hidden}) proposalBody({
  required List<String> instructions,
  required List<String> blocks,
  required int keep,
  required bool expanded,
}) {
  final body = [
    for (final (index, block) in blocks.indexed) ...[
      if (index > 0) '',
      ...block.split('\n'),
    ],
  ];
  final whole = [
    ...instructions,
    if (body.isNotEmpty) ...['', ...body],
  ];
  if (expanded) return (lines: whole, hidden: 0);
  final preview = [
    for (final block in blocks)
      for (final line in block.split('\n'))
        if (jsTrim(line).isNotEmpty) line,
  ].take(keep).toList();
  final lines = preview.isEmpty ? <String>[] : ['', ...preview];
  return (lines: lines, hidden: math.max(whole.length - lines.length, 0));
}
