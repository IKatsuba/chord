import 'package:chord_tui/chord_tui.dart';
import 'commands.dart';
import 'mentions.dart';
import 'prompt.dart' show Cursor;
import '../../images.dart' show PastedImage;
import '../../session/context.dart';
import '../../session/transcript/types.dart';

/// A draft ↓ set aside: the whole of it as it stood, for ↑ to put back as
/// it was.
final class KeptDraft {
  const KeptDraft({
    required this.text,
    required this.cursor,
    this.images = const [],
    this.bash = false,
  });

  final String text;
  final Cursor cursor;

  /// The images its placeholders name.
  final List<PastedImage> images;
  final bool bash;
}

/// A command menu's semantic highlight and keyboard window, without focus.
final class CommandMenuState {
  const CommandMenuState({
    required this.draft,
    required this.items,
    required this.picker,
    this.top = 0,
    this.dismissed = false,
  });
  final String draft;
  final List<CommandItem> items;
  final PickerState<String> picker;
  final int top;
  final bool dismissed;

  /// The matching commands in the framework filter's order.
  List<CommandItem> get matches => [
    for (final result in picker.results) items[result.index],
  ];

  /// The highlighted match, or none for an empty result set.
  CommandItem? get selected =>
      picker.highlighted < 0 ? null : matches[picker.highlighted];
}

/// Edits reset dismissal and navigation; advertisements retain a valid value.
/// After `/new ` the list is of [agents], as [agentItems] ranks and
/// describes the window's runtimes; after `/team show `, `run ` or `stop `
/// it is of [teams]' names, read as the draft came to them.
CommandMenuState? commandMenu(
  CommandMenuState? previous,
  String draft,
  List<CommandItem> items, {
  List<CommandItem> agents = const [],
  TeamNames? teams,
}) {
  final team = teamQuery(draft);
  final agent = agentQuery(draft);
  final named = agent ?? team?.name;
  final query = named ?? commandQuery(draft);
  if (query == null) return null;
  if (agent != null) items = agents;
  if (team != null) {
    items = teams == null ? const [] : teamItems(team.form, teams);
  }
  final filter = named == null
      ? const FzfPickerFilter()
      : const _ExactFirstFilter();
  final choices = [
    for (final item in items) PickerItem(value: item.name, label: item.name),
  ];
  final same = previous?.draft == draft;
  final picker = same
      ? previous!.picker.withItems(choices, filter)
      : PickerState<String>.initial(choices).withQuery(query, filter);
  return CommandMenuState(
    draft: draft,
    items: items,
    picker: picker,
    top: same ? previous!.top : 0,
    dismissed: same && previous!.dismissed,
  );
}

/// fzf's order with the label typed exactly first: `/new fake` and Enter
/// opens fake, not fake2.
final class _ExactFirstFilter implements PickerFilter {
  const _ExactFirstFilter();

  @override
  List<PickerMatch> match(String query, List<String> labels) {
    final found = const FzfPickerFilter().match(query, labels);
    final exact = found.where((each) => labels[each.index] == query);
    return exact.isEmpty
        ? found
        : [exact.first, ...found.where((each) => each != exact.first)];
  }
}

/// One wrapping keyboard step, revealing the selected command minimally.
CommandMenuState moveCommandMenu(CommandMenuState state, int by, int rows) {
  if (rows <= 0 || state.picker.results.isEmpty) return state;
  final picker = state.picker.moved(by, wrap: true);
  final range = visibleRange(
    picker.results.length,
    picker.highlighted,
    rows,
    state.top,
  );
  return CommandMenuState(
    draft: state.draft,
    items: state.items,
    picker: picker,
    top: range.start,
  );
}

/// Esc preserves the draft and selection until the next text edit.
CommandMenuState dismissCommandMenu(CommandMenuState state) => CommandMenuState(
  draft: state.draft,
  items: state.items,
  picker: state.picker,
  top: state.top,
  dismissed: true,
);

/// Finished held runs in their original completion order; removed runs are skipped.
String heldContext(Transcript transcript, Iterable<String> held) =>
    shellContext([
      for (final id in held)
        for (final entry in transcript.entries)
          if (entry is ShellEntry && entry.turnId == id) entry.run,
    ]);

/// The current local command, independent of whether an agent turn is running.
String? runningShell(Transcript transcript) {
  for (final entry in transcript.entries) {
    if (entry is ShellEntry && entry.run.running) return entry.turnId;
  }
  return null;
}

/// Literal reachable recipient supplied by the caller, never discovered by UI.
final class MentionRecipient {
  const MentionRecipient(this.name, {this.color});
  final String name;
  final Color? color;
}

/// One passive file/agent finder snapshot; no focus or asynchronous work.
final class FileFinder {
  const FileFinder({
    required this.mention,
    required this.files,
    this.highlighted = 0,
    this.top = 0,
    this.pending = false,
    this.searching = false,
    this.empty,
  });
  final Mention mention;
  final List<String> files;
  final int highlighted, top;
  final bool pending, searching;
  final String? empty;
  bool get agent => mention is AgentMention;

  /// Pending work with no drawn row still needs linked positive-room geometry.
  bool get pendingSurface =>
      pending && files.isEmpty && empty == null && !searching;

  /// The one-row fallback keeps a retained choice instead of its slow marker.
  bool showsSearching(int room) =>
      searching && room > 0 && (files.isEmpty || room >= 2);

  /// Reserves the last retained row for searching without adding a list row.
  int choiceRows(int room) {
    if (room <= 0) return 0;
    final count = files.length.clamp(0, room);
    return showsSearching(room) && count > 0
        ? (count - 1).clamp(1, count)
        : count;
  }
}

/// A completion either replaces the token or submits the untouched draft.
final class MentionChoice {
  const MentionChoice(this.text, this.cursor, {this.submit = false});
  final String text;
  final int cursor;
  final bool submit;
}
