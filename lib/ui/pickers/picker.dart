import 'dart:math' as math;
import 'package:chord_tui/chord_tui.dart'
    show cellWidth, pickerNumber, TextLayout, TextSpan;
import '../../session/sessions.dart';
import '../../settings.dart';
import 'mcp.dart';

import '../../agents.dart';

/// One catalog choice, with the original default-agent preference.
typedef AgentChoice = ({String key, String value, String label, bool current});

/// Catalog order and original dim title/PATH annotations.
List<AgentChoice> agentChoices(List<ListedAgent> agents, String preferred) => [
  for (final agent in agents) _choice(agent, preferred),
];

AgentChoice _choice(ListedAgent agent, String preferred) {
  final note = [
    if (agent.title case final title? when title != agent.name) title,
    if (agent.found == false) 'not on PATH',
  ].join(' · ');
  return (
    key: agent.name,
    value: agent.name,
    label: note.isEmpty ? agent.name : '${agent.name}\x1b[2m · $note\x1b[22m',
    current: agent.name == preferred,
  );
}

int _choiceCalls = 0,
    _projectedChoices = 0,
    _linePasses = 0,
    _overflowPasses = 0,
    _rowShapes = 0;

/// Internal measurement support: numeric work only, with no retained choices.
({
  int choiceCalls,
  int projectedChoices,
  int linePasses,
  int overflowPasses,
  int rowShapes,
})
get resumePickerWorkDiagnostics => (
  choiceCalls: _choiceCalls,
  projectedChoices: _projectedChoices,
  linePasses: _linePasses,
  overflowPasses: _overflowPasses,
  rowShapes: _rowShapes,
);

/// Resets internal measurements without changing a picker or geometry cache.
void resetResumePickerWorkDiagnostics() {
  _choiceCalls = _projectedChoices = _linePasses = _overflowPasses =
      _rowShapes = 0;
}

/// A metadata prefix and title, retaining the original UTF-16 split offset.
typedef SessionChoice = ({EarlierSession session, String label, int hang});

/// Original aligned ages and optional directories, frozen for a scope opening.
///
/// A session in [open], a child of this window's open now, says `open now`
/// after when it was used, as picking it goes to the child rather than load
/// it twice; the column is there only when a row says it.
List<SessionChoice> sessionChoices(
  List<EarlierSession> sessions,
  num now, {
  bool directories = false,
  String? home,
  Set<String> open = const {},
}) {
  _choiceCalls++;
  _projectedChoices += sessions.length;
  final when = [
    for (final session in sessions) lastUsed(session.lastUsedAt, now),
  ];
  final opens = [
    for (final session in sessions)
      open.contains(session.resume.sessionId) ? 'open now' : '',
  ];
  final where = [
    if (directories)
      for (final session in sessions)
        cutPath(homePath(session.resume.cwd, home), 30),
  ];
  int widest(List<String> values) =>
      values.fold(0, (n, text) => cellWidth(text) > n ? cellWidth(text) : n);
  final ageWidth = widest(when),
      opensWidth = widest(opens),
      pathWidth = widest(where);
  String padded(String text, int width) =>
      '$text${' ' * (width - cellWidth(text))}';
  return List.unmodifiable([
    for (var i = 0; i < sessions.length; i++)
      (() {
        final prefix =
            '${[padded(when[i], ageWidth), if (opensWidth > 0) padded(opens[i], opensWidth), if (directories) padded(where[i], pathWidth)].join('  ')}  ';
        return (
          session: sessions[i],
          label: '$prefix${sessions[i].prompt}',
          hang: prefix.length,
        );
      })(),
  ]);
}

/// The widest frozen metadata prefix, measured in terminal cells.
int sessionPrefixWidth(List<SessionChoice> choices) => choices.fold(
  0,
  (n, choice) => math.max(n, cellWidth(choice.label.substring(0, choice.hang))),
);

/// Whether the original list-wide threshold hangs titles beside metadata.
bool sessionChoiceHangs(int contentWidth, int prefixWidth, int innerWidth) =>
    contentWidth - prefixWidth >= innerWidth / 2;

/// A choice's title in rows [width] cells wide, as the original's
/// `choiceLines` breaks it with wrap-ansi.
List<String> sessionChoiceTitle(SessionChoice choice, int width) => [
  for (final row in TextLayout.wrapAnsi(
    TextSpan(choice.label.substring(choice.hang)),
    math.max(1, width),
    hard: true,
  ).lines)
    row.map((g) => g.text).join(),
];

/// Exact rows of the same metadata/title composition used by the visible row.
int sessionChoiceRows(
  SessionChoice choice,
  int contentWidth, {
  required int prefixWidth,
  required int innerWidth,
}) {
  _rowShapes++;
  final hanging = sessionChoiceHangs(contentWidth, prefixWidth, innerWidth);
  final titleWidth = math.max(
    0,
    hanging ? contentWidth - prefixWidth : contentWidth,
  );
  final titleRows = sessionChoiceTitle(choice, titleWidth).length;
  return hanging ? math.max(1, titleRows) : 1 + titleRows;
}

/// Unscrolled row count at the original frame width, before overflow's gutter.
int sessionListLines(
  List<SessionChoice> choices,
  int frameWidth, {
  bool overflow = false,
  int? prefixWidth,
}) {
  if (overflow) {
    _overflowPasses++;
  } else {
    _linePasses++;
  }
  final inner = math.max(1, frameWidth - 4);
  final prefix = prefixWidth ?? sessionPrefixWidth(choices);
  final numbers = choices.isEmpty
      ? 0
      : pickerNumber(choices.length - 1, choices.length).length + 1;
  final width = math.max(1, inner - 2 - numbers - (overflow ? 2 : 0));
  return choices.fold(
    0,
    (n, choice) =>
        n +
        sessionChoiceRows(
          choice,
          width,
          prefixWidth: prefix,
          innerWidth: inner,
        ),
  );
}
