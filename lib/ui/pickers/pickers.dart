import 'dart:math' as math;
import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import '../../mcp.dart';
import '../../session/agent_state.dart';
import '../../session/servers.dart';
import '../../session/config.dart';
import '../../session/efforts.dart';
import '../../session/models.dart';
import '../../session/parameters.dart';
import '../app/context.dart';
import '../dialogs/permission_scroll.dart' show permissionScrollSteps;
import '../prompt/overlay.dart';
import '../shortcuts/bindings.dart' show keysOf, sequencePanel;
import '../theme/theme.dart'
    show themeChoices, themeName, themePickerLayout, themeSample;
import 'state.dart';
import 'mcp.dart';
import 'picker.dart';
import '../../session/sessions.dart';
import '../../session/team_command.dart' show ListedTeam, TeamListing, noTeams;
import '../../notices.dart' show dimcodeWords, noticeChoices;
import '../teams/teams.dart' show teamChoices, teamsHint, teamsWhere;

/// The original model, effort and two-level settings frames above the prompt.
class SettingsPicker extends StatelessWidget {
  const SettingsPicker({
    super.key,
    required this.state,
    required this.agent,
    required this.agentName,
    required this.windowRows,
    required this.onAction,
    required this.onSelected,
    required this.onCanceled,
  });
  final SettingsPickerState state;
  final AgentState agent;
  final String agentName;
  final int windowRows;
  final void Function(SettingsPickerAction) onAction;
  final void Function(String) onSelected;
  final void Function() onCanceled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final models = modelsFrom(agent.configOptions, agent.models);
      final efforts = effortsFrom(agent.configOptions);
      // The keys that move the effort, as arrows when bound to them, as bound
      // when rebound, and none when neither direction is bound.
      final named = [
        for (final action in const [
          'modelPicker:decreaseEffort',
          'modelPicker:increaseEffort',
        ])
          ...keysOf(Keys.of(context), action).take(1).map(sequencePanel),
      ];
      final effortKeys = named.isEmpty ? null : named.join('/');
      final options = optionsFromConfigOptions(agent.configOptions);
      final option = options.where((o) => o.id == state.option).firstOrNull;
      final model = modelName(models) ?? '';
      var title = '';
      var description = '';
      var verb = '';
      String? current;
      SettingsLine? line;
      final items = <PickerItem<String>>[];
      String marked(String name, bool current) => '$name${current ? ' ✔' : ''}';
      if (state.kind == 'model') {
        title = 'Select model';
        verb = 'switch';
        current = models?.current;
        for (final m in models?.available ?? <AgentModel>[]) {
          items.add(
            PickerItem(value: m.id, label: marked(m.name, m.id == current)),
          );
        }
        description = items.isEmpty
            ? '$agentName offers no models to choose from.'
            : "Switch $agentName's model for this session.";
        final highlighted = models?.available
            .where((m) => m.id == state.highlighted)
            .firstOrNull;
        line = settingsLine(
          keys: effortKeys,
          options: agent.configOptions,
          inUse: model,
          highlighted: highlighted?.id == current ? null : highlighted?.name,
          pending: state.effort?.option == efforts?.option
              ? state.effort?.value
              : null,
          width: math.max(1, constraints.maxWidth - 4),
        );
        if (state.effort != null &&
            state.effort!.value != efforts?.current &&
            (state.highlighted == null || state.highlighted == current)) {
          verb = 'set';
        }
      } else if (state.kind == 'effort') {
        title = 'Effort';
        verb = 'set';
        current = efforts?.current;
        for (final e in efforts?.available ?? <AgentEffort>[]) {
          items.add(
            PickerItem(value: e.id, label: marked(e.name, e.id == current)),
          );
        }
        final wide =
            "$agentName's effort for $model, in the order it gives them.";
        description = items.isEmpty
            ? noEffortNote(agentName, model)
            : wide.length <= constraints.maxWidth - 4
            ? wide
            : "$agentName's effort for $model.";
      } else if (option != null) {
        title = 'Set ${option.name}';
        verb = 'set';
        current = option.current;
        description = "Choose $agentName's ${option.name} for this session.";
        for (final v in option.values) {
          items.add(
            PickerItem(
              value: v.value,
              label: marked(v.name, v.value == current),
            ),
          );
        }
      } else {
        title = 'Settings';
        verb = 'choose';
        current = state.from;
        description = options.isEmpty
            ? '$agentName has no settings other than its model and mode.'
            : "Change $agentName's settings for this session.";
        final width = options.fold(0, (n, o) => math.max(n, o.name.length));
        for (final o in options) {
          items.add(
            PickerItem(
              value: o.id,
              label: '${o.name.padRight(width)}  ${valueName(o, o.current)}',
            ),
          );
        }
      }
      final room = constraints.maxHeight;
      final listed = items.isEmpty
          ? 0
          : framedRows(math.max(3, windowRows ~/ 4), room, items.length);
      final listHeight =
          math.min(items.length, listed) +
          (items.length > listed && listed > 0 ? 1 : 0);
      final bodyHeight =
          1 +
          (listed > 0 ? 1 + listHeight : 0) +
          (listed > 0 && line != null ? 2 : 0);
      final parts = <(int, int)>[
        (0, 1),
        if (listed > 0) (2, listHeight),
        if (listed > 0 && line != null) (3 + listHeight, 1),
      ];
      final back = state.kind == 'config' && option != null;
      final close = closeHint(context, back ? 'to go back' : 'to close');
      final hint = [
        if (listed > 0) 'Enter to $verb',
        if (listed > 0 &&
            state.kind == 'model' &&
            efforts != null &&
            effortKeys != null)
          '$effortKeys ${line?.narrow == true ? 'effort' : 'for effort'}',
        ?close,
      ].join(' · ');
      final innerWidth = math.max(1, constraints.maxWidth - 4);
      int wrappedRows(String text) =>
          TextLayout.compute(parseAnsi(text), maxWidth: innerWidth).height;
      final chrome = 2 + wrappedRows(title) + 1 + wrappedRows(hint);
      final shown = cutRows(math.max(0, room - chrome), bodyHeight, parts);
      Widget row(String text, {Style? style, bool cut = false}) => Text.ansi(
        text,
        style: style ?? theme.dim,
        softWrap: false,
        maxLines: 1,
        overflow: cut ? TextOverflow.middle : TextOverflow.clip,
      );
      return Actions(
        bindings: [
          Binding(
            'esc',
            back ? 'Back to settings' : 'Close settings picker',
            onCanceled,
            id: 'select:cancel',
          ),
          if (listed > 0 && state.kind == 'model' && efforts != null) ...[
            Binding(
              'left',
              'Decrease effort',
              () => onAction(const EffortMoved(-1)),
              id: 'modelPicker:decreaseEffort',
            ),
            Binding(
              'right',
              'Increase effort',
              () => onAction(const EffortMoved(1)),
              id: 'modelPicker:increaseEffort',
            ),
          ],
        ],
        child: Focus(
          autofocus: true,
          child: Box(
            style: theme.text,
            background: Style.plain,
            border: Border.rounded.withStyle(
              theme.focus.fg == null ? theme.dim : theme.focus,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.ansi(title, style: theme.focus.merge(Style.bold)),
                SizedBox(
                  height: shown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row(description, cut: true),
                      if (listed > 0) ...[
                        const SizedBox(height: 1),
                        Picker<String>(
                          key: ValueKey('${state.kind}/${option?.id ?? ''}'),
                          items: items,
                          showNumbers: false,
                          itemBuilder: (_, item, _) => Text.ansi(
                            '${pickerNumber(items.indexWhere((each) => each.value == item.value), items.length)} ${item.label}',
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.middle,
                          ),
                          initialValue: current,
                          maxVisibleRows: listHeight,
                          showInitialSelectionAtTop: false,
                          countHiddenItemsAbove: true,
                          unhandledKeys: {
                            'esc',
                            'shift+up',
                            'shift+down',
                            'home',
                            'end',
                            'pageup',
                            'pagedown',
                            'shift+pageup',
                            'shift+pagedown',
                            ...boundKeys(context, const [
                              'select:cancel',
                              'modelPicker:decreaseEffort',
                              'modelPicker:increaseEffort',
                            ]),
                          },
                          onChanged: state.kind != 'model'
                              ? null
                              : (id) => onAction(ModelHighlighted(id)),
                          onSelected: onSelected,
                          onCanceled: onCanceled,
                        ),
                      ],
                      if (listed > 0 && line != null) ...[
                        const SizedBox(height: 1),
                        row(
                          line.text,
                          style: line.dim ? theme.dim : theme.text,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Text.ansi(hint, style: theme.dim),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Original resume frame with keyboard scope/cancel and wrapped numbered rows.
class ResumePicker extends StatefulWidget {
  const ResumePicker({
    super.key,
    required this.picker,
    required this.agent,
    this.home,
    this.open = const {},
    required this.rows,
    required this.room,
    this.starting = false,
    this.active = true,
    required this.onToggleScope,
    required this.onSelected,
    required this.onCanceled,
  });
  final ResumePickerState picker;
  final String agent;
  final String? home;

  /// The ids of the sessions open now, as children of this window's: their
  /// rows say `open now`. Read when the list is made, as the rows are.
  final Set<String> open;
  final int rows, room;
  final bool starting, active;
  final void Function() onToggleScope, onCanceled;
  final void Function(EarlierSession) onSelected;

  @override
  State<ResumePicker> createState() => _ResumePickerState();
}

class _ResumePickerState extends State<ResumePicker> {
  late List<SessionChoice> _choices;
  late List<PickerItem<SessionChoice>> _items;
  late int _prefixWidth;
  int? _lineWidth, _firstLines, _overflowLines;

  @override
  void initState() {
    super.initState();
    _snapshot();
  }

  @override
  void didUpdateWidget(ResumePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.picker, after = widget.picker;
    if (!identical(before.sessions, after.sessions) ||
        before.cwd != after.cwd ||
        before.everywhere != after.everywhere ||
        before.opening != after.opening ||
        before.openedAt != after.openedAt ||
        oldWidget.home != widget.home) {
      _snapshot();
    }
  }

  void _snapshot() {
    final picker = widget.picker;
    _choices = sessionChoices(
      resumeChoices(picker),
      picker.openedAt,
      directories: picker.everywhere,
      home: widget.home,
      open: widget.open,
    );
    _items = List.unmodifiable([
      for (final choice in _choices)
        PickerItem(value: choice, label: choice.label),
    ]);
    _prefixWidth = sessionPrefixWidth(_choices);
    _lineWidth = _firstLines = _overflowLines = null;
  }

  int _lineCount(int width, {bool overflow = false}) {
    if (_lineWidth != width) {
      _lineWidth = width;
      _firstLines = _overflowLines = null;
    }
    return overflow
        ? _overflowLines ??= sessionListLines(
            _choices,
            width,
            overflow: true,
            prefixWidth: _prefixWidth,
          )
        : _firstLines ??= sessionListLines(
            _choices,
            width,
            prefixWidth: _prefixWidth,
          );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final choices = _choices, prefixWidth = _prefixWidth;
      final picker = widget.picker;
      final rows = widget.rows, room = widget.room;
      final starting = widget.starting, active = widget.active;
      final agent = widget.agent;
      final onToggleScope = widget.onToggleScope,
          onCanceled = widget.onCanceled;
      final onSelected = widget.onSelected;
      final available = math.min(room, constraints.maxHeight);
      final listed = choices.isEmpty
          ? 0
          : framedRows(rows, available, choices.length);
      final innerWidth = math.max(1, constraints.maxWidth - 4);
      // Every choice has its one metadata row, so this cap is already full
      // when even one row per choice would exceed it.
      var listHeight = listed;
      if (listed > 0 && choices.length <= listed) {
        final firstRows = _lineCount(constraints.maxWidth);
        final needed = firstRows > listed
            ? _lineCount(constraints.maxWidth, overflow: true)
            : firstRows;
        listHeight = math.min(needed, listed);
      }
      final description = starting
          ? "Pick one of $agent's earlier sessions to open."
          : "$agent's earlier sessions in ${picker.everywhere ? 'every directory' : 'this directory'}.";
      final scopeKey = hintKeyOf(context, 'select:toggleScope');
      final close = closeHint(context, starting ? 'to quit' : 'to close');
      String hintFor(bool enter) => [
        if (enter) 'Enter to resume',
        if (scopeKey != null)
          '${capital(scopeKey)} for ${picker.everywhere ? 'this directory' : 'all directories'}',
        ?close,
      ].join(' · ');
      var hint = hintFor(listed > 0);
      int wrappedRows(String text) =>
          TextLayout.compute(TextSpan(text), maxWidth: innerWidth).height;
      final chrome =
          2 + wrappedRows('Resume a session') + 1 + wrappedRows(hint);
      final bodyHeight =
          1 +
          (choices.isEmpty
              ? 2
              : listed > 0
              ? 1 + listHeight
              : 0);
      final shown = cutRows(math.max(0, available - chrome), bodyHeight, [
        (0, 1),
        if (choices.isEmpty) (2, 1) else if (listed > 0) (2, listHeight),
      ]);
      final showList = listed > 0 && shown > 2;
      if (!showList) hint = hintFor(false);
      return Actions(
        bindings: [
          if (active)
            Binding(
              'ctrl+a',
              'Toggle resume directory scope',
              onToggleScope,
              id: 'select:toggleScope',
            ),
          if (active)
            Binding(
              'esc',
              starting ? 'Cancel resume startup' : 'Close resume picker',
              onCanceled,
              id: 'select:cancel',
            ),
        ],
        child: Focus(
          // Removing the inner Picker must give the remaining modal actions
          // their own fresh autofocus owner instead of the overlay scope.
          key: ValueKey(showList),
          autofocus: active,
          canRequestFocus: active,
          child: Box(
            width: starting ? null : constraints.maxWidth,
            style: theme.text,
            background: Style.plain,
            border: Border.rounded.withStyle(
              theme.focus.fg == null ? theme.dim : theme.focus,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resume a session', style: theme.focus.merge(Style.bold)),
                SizedBox(
                  height: shown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        style: theme.dim,
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.middle,
                      ),
                      if (choices.isEmpty) ...[
                        const SizedBox(height: 1),
                        Text('No earlier sessions in this directory.'),
                      ] else if (showList) ...[
                        const SizedBox(height: 1),
                        Picker<SessionChoice>(
                          key: ValueKey((picker.opening, picker.everywhere)),
                          items: _items,
                          itemExtentVersion: (_items, innerWidth, prefixWidth),
                          itemExtentBuilder: (item, positions, width) =>
                              sessionChoiceRows(
                                item.value,
                                width,
                                prefixWidth: prefixWidth,
                                innerWidth: innerWidth,
                              ),
                          onSelected: (choice) => onSelected(choice.session),
                          onCanceled: onCanceled,
                          maxVisibleRows: math.min(listHeight, shown - 2),
                          enabled: active,
                          searchable: false,
                          showNumbers: true,
                          wrapNavigation: false,
                          showInitialSelectionAtTop: false,
                          countHiddenItemsAbove: true,
                          unhandledKeys: {
                            'esc',
                            'home',
                            'end',
                            'pageup',
                            'pagedown',
                            'shift+up',
                            'shift+down',
                            'shift+pageup',
                            'shift+pagedown',
                            ...boundKeys(context, const [
                              'select:cancel',
                              'select:toggleScope',
                            ]),
                          },
                          itemBuilder: (context, item, _) {
                            final choice = item.value;
                            final prefix = choice.label.substring(
                              0,
                              choice.hang,
                            );
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final hanging = sessionChoiceHangs(
                                  constraints.maxWidth,
                                  prefixWidth,
                                  innerWidth,
                                );
                                final metadata = Text(
                                  hanging ? prefix : prefix.trimRight(),
                                  softWrap: false,
                                  maxLines: 1,
                                );
                                return hanging
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: prefixWidth,
                                            child: metadata,
                                          ),
                                          Expanded(
                                            child: Text(
                                              sessionChoiceTitle(
                                                choice,
                                                constraints.maxWidth -
                                                    prefixWidth,
                                              ).join('\n'),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          metadata,
                                          Text(
                                            sessionChoiceTitle(
                                              choice,
                                              constraints.maxWidth,
                                            ).join('\n'),
                                          ),
                                        ],
                                      );
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Text(hint, style: theme.dim),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The notice's paragraphs wrapped to [width], each after its blank row, and
/// where each one's lines start among the body's rows and how many it has.
({List<List<String>> paragraphs, List<(int, int)> parts}) _noticeBody(
  int width,
) {
  // Wrapped at spaces, as the transcript is, so a path or a value a person
  // types stays whole on its line; only a word longer than the line is cut,
  // where it is drawn.
  final paragraphs = <List<String>>[];
  final parts = <(int, int)>[];
  var at = 0;
  for (final paragraph in dimcodeWords.paragraphs) {
    final lines = [
      for (final row in TextLayout.wrapAnsi(TextSpan(paragraph), width).lines)
        [for (final glyph in row) glyph.text].join(),
    ];
    at++;
    parts.add((at, lines.length));
    paragraphs.add(lines);
    at += lines.length;
  }
  return (paragraphs: paragraphs, parts: parts);
}

/// The notice's frame, its title, the gap above its choices and the
/// choices, then the hint with its gap when [room] has room for it.
int _noticeChrome(int room) =>
    2 + 1 + 1 + noticeChoices.length + (room >= noticeFixed ? 2 : 0);

/// The rows the notice draws in a layer of [room] rows, [columns] wide: what
/// a panel under it, the shortcuts help, is left with.
int noticeRows(int room, int columns) {
  final (:paragraphs, :parts) = _noticeBody(math.max(1, columns - 4));
  final rows = paragraphs.fold(0, (sum, lines) => sum + 1 + lines.length);
  final chrome = _noticeChrome(room);
  return chrome + cutRows(math.max(0, room - chrome), rows, parts);
}

/// `/theme`'s picker, as the original's ThemePicker: the seven themes, the
/// one in use marked, a diff sample in the theme highlighted, while the
/// whole window previews it; Enter keeps it, Esc goes back.
class ThemePicker extends StatefulWidget {
  const ThemePicker({
    super.key,
    required this.current,
    required this.background,
    required this.room,
    required this.onMove,
    required this.onPick,
    required this.onCanceled,
  });

  /// The `theme` setting in use, marked and highlighted first.
  final String current;

  /// The terminal's background, which Auto names.
  final TerminalBackground background;

  /// The rows the layer it floats in has.
  final int room;

  final void Function(String) onMove, onPick;
  final void Function() onCanceled;

  @override
  State<ThemePicker> createState() => _ThemePickerState();

  Widget _picker(BuildContext context, FocusNode focus) {
    final theme = Theme.of(context);
    final choices = themeChoices(current, background);
    final layout = themePickerLayout(room);
    final back = closeHint(context, 'to go back');
    final hint = [
      if (layout.choices > 0) ...['↑↓ to preview', 'Enter to keep'],
      if (back != null) '$back to ${themeName(current)}',
    ].join(' · ');
    final items = [
      for (final choice in choices)
        PickerItem(value: choice.value, label: choice.label),
    ];
    Widget row(String text) => Text(
      text,
      style: theme.dim,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
    return Actions(
      bindings: [
        Binding(
          'esc',
          'Go back to the theme in use',
          onCanceled,
          id: 'select:cancel',
        ),
      ],
      child: Focus(
        focusNode: focus,
        autofocus: true,
        // The window's width whatever it holds, a tight one with no list
        // too, as the other pickers and the original's.
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth,
            child: Box(
              style: theme.text,
              background: Style.plain,
              border: Border.rounded.withStyle(
                theme.focus.fg == null ? theme.dim : theme.focus,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: theme.focus.merge(Style.bold)),
                  row(
                    Theme.noColorOf(context)
                        ? 'NO_COLOR is set, so chord draws no colour.'
                        : 'Choose the colours that read best on this terminal.',
                  ),
                  if (layout.choices > 0) ...[
                    const SizedBox(height: 1),
                    Picker<String>(
                      items: items,
                      showNumbers: false,
                      initialValue: current,
                      maxVisibleRows: layout.choices,
                      showInitialSelectionAtTop: false,
                      countHiddenItemsAbove: true,
                      itemBuilder: (_, item, _) => Text(
                        '${pickerNumber(items.indexWhere((each) => each.value == item.value), items.length)} ${item.label}',
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                      unhandledKeys: {
                        'esc',
                        ...boundKeys(context, const ['select:cancel']),
                      },
                      onChanged: onMove,
                      onSelected: onPick,
                      onCanceled: onCanceled,
                    ),
                  ],
                  if (layout.sample) ...[
                    const SizedBox(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: Diff.fromView(
                        diffTexts(
                          themeSample.old,
                          themeSample.now,
                        ).view(maxRows: 3),
                        title: themeSample.path,
                        showTitle: false,
                      ),
                    ),
                  ],
                  const SizedBox(height: 1),
                  row(hint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePickerState extends State<ThemePicker> {
  final _focus = FocusNode(debugLabel: 'theme picker');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A room too tight for the list unmounts it with the keys it held, and
    // focus goes to the scope around: the picker takes them back, so Esc
    // still goes back to the theme in use.
    if (themePickerLayout(widget.room).choices == 0) {
      context.owner.afterLayout(() {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
    }
    return widget._picker(context, _focus);
  }
}

/// `/mcp`, as the original's McpPanel: the MCP servers chord passed to the
/// agent, in the pickers' frame but with nothing to pick. Whether the agent
/// reached each one ACP does not say, so the panel says that rather than
/// show a state it cannot know. Esc closes it.
class McpPanel extends StatelessWidget {
  const McpPanel({
    super.key,
    required this.servers,
    this.ignored = const [],
    this.heldBack = const [],
    required this.agent,
    required this.windowRows,
    required this.room,
    this.starting = false,
    this.chord,
    required this.onClose,
  });

  /// The servers the session's directory gives.
  final List<DefinedServer> servers;

  /// What the files lost, said under the list so a missing server is
  /// found.
  final List<Ignored> ignored;

  /// The servers its agent was not given, each listed `not passed`.
  final List<HeldBack> heldBack;
  final String agent;

  /// The window's height, which decides how many servers are listed.
  final int windowRows;

  /// The rows the layer it floats in has.
  final int room;

  /// Its agent's session not there yet: chord has passed it nothing, so
  /// neither a server passed nor one held back can be said.
  final bool starting;

  /// chord's own server, listed first; none where the window has none.
  final ChordRow? chord;
  final void Function() onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final width = math.max(1, constraints.maxWidth - 4);
      final users = withHeldBack(servers, heldBack);
      final chord = this.chord;
      final listed = [if (chord != null) ListedServer(chord.server), ...users];
      final held = heldNote(heldBack);
      final lost = ignoredNote(ignored);
      final (:headings, :rows) = mcpRows(listed, width);
      final (:shown, :more) = mcpFit(rows, mcpRowLimit(windowRows));
      final close = closeHint(context);
      int wrapped(String text) =>
          TextLayout.compute(parseAnsi(text), maxWidth: width).height;
      Widget prose(String text) => Text(text, style: theme.dim);
      Widget line(String text, [Style? style]) => Text(
        text,
        style: style,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );

      // The body's parts, each its first row and its height, so a cut
      // falls after a drawn row and never leaves a gap before the hint.
      final body = <Widget>[];
      final parts = <(int, int)>[];
      var at = 0;
      void add(List<Widget> widgets, int height, {bool gap = false}) {
        if (gap && body.isNotEmpty) {
          body.add(const SizedBox(height: 1));
          at++;
        }
        body.addAll(widgets);
        parts.add((at, height));
        at += height;
      }

      if (starting) {
        add([prose(startingLine(agent))], wrapped(startingLine(agent)));
      } else {
        if (listed.isEmpty) {
          final none = lost == null
              ? 'No MCP servers were passed to $agent: none are defined in '
                    ".mcp.json or in chord's settings files."
              : 'No MCP servers were passed to $agent.';
          add([prose(none)], wrapped(none));
        } else {
          final about =
              "chord's MCP servers for $agent. ACP does not say whether "
              '$agent connected to the ones it was passed.';
          add([prose(about)], wrapped(about));
          final lines = [for (final row in shown) ...row];
          add(
            [
              line(headings, theme.dim),
              for (final each in lines) line(each),
              if (more > 0) line('… +$more more', theme.dim),
            ],
            1 + lines.length + (more > 0 ? 1 : 0),
            gap: true,
          );
        }
        if (chord != null) {
          final said = chordLine(chord, agent);
          add([prose(said)], wrapped(said), gap: true);
        }
        if (held != null) add([prose(held)], wrapped(held), gap: true);
        // With no servers the note follows the none line directly, as the
        // original's.
        if (lost != null) {
          add([prose(lost)], wrapped(lost), gap: listed.isNotEmpty);
        }
      }
      final chrome = 2 + 1 + (close == null ? 0 : 1 + wrapped(close));
      final height = cutRows(math.max(0, room - chrome), at, parts);
      return Actions(
        bindings: [
          Binding('esc', 'Close the MCP servers', onClose, id: 'select:cancel'),
        ],
        child: Focus(
          autofocus: true,
          // The window's width whatever it holds, as the other pickers.
          child: SizedBox(
            width: constraints.maxWidth,
            child: Box(
              style: theme.text,
              background: Style.plain,
              border: Border.rounded.withStyle(
                theme.focus.fg == null ? theme.dim : theme.focus,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MCP servers', style: theme.focus.merge(Style.bold)),
                  SizedBox(
                    height: height,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: body,
                    ),
                  ),
                  if (close != null) ...[
                    const SizedBox(height: 1),
                    Text(close, style: theme.dim),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// `/team`: the teams saved for this project and every project, above the
/// prompt as `/resume`'s list is: each with its size and runtimes, where it
/// is saved, whether it runs in this window and its description, a broken
/// file with its problem. Enter on one hands it to [onPick]; Esc closes.
/// From the original's `TeamsPicker` in `ui/pickers/Pickers.tsx`.
class TeamsPicker extends StatefulWidget {
  /// The picker over [listing], [columns] wide, its list at most [rows]
  /// rows in a layer of [room].
  const TeamsPicker({
    super.key,
    required this.listing,
    required this.rows,
    required this.room,
    required this.columns,
    required this.onPick,
    required this.onCanceled,
    this.active = true,
  });

  final TeamListing listing;
  final int rows, room, columns;
  final bool active;
  final void Function(ListedTeam found) onPick;
  final void Function() onCanceled;

  @override
  State<TeamsPicker> createState() => _TeamsPickerState();
}

class _TeamsPickerState extends State<TeamsPicker> {
  // Read once: a running time that ticks would shift the rows under the
  // highlight.
  late final List<PickerItem<String>> _choices = teamChoices(
    widget.listing.teams,
    widget.listing.runs,
    DateTime.now().millisecondsSinceEpoch,
    widget.columns,
  );
  late String? _highlighted = _choices.firstOrNull?.value;

  ListedTeam? _named(String? name) =>
      widget.listing.teams.where((each) => each.found.name == name).firstOrNull;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final innerWidth = math.max(1, constraints.maxWidth - 4);
      final where = teamsWhere(widget.listing.dirs, widget.columns);
      int wrapped(String text) =>
          TextLayout.compute(TextSpan(text), maxWidth: innerWidth).height;
      final listed = _choices.isEmpty
          ? 0
          : framedRows(
              widget.rows,
              math.min(widget.room, constraints.maxHeight) - wrapped(where) + 1,
              _choices.length,
            );
      final hint = [
        if (listed > 0)
          ...teamsHint(_named(_highlighted)?.found, widget.columns),
        ?closeHint(context),
      ].join(' · ');
      return Actions(
        bindings: [
          if (widget.active)
            Binding(
              'esc',
              'Close teams picker',
              widget.onCanceled,
              id: 'select:cancel',
            ),
        ],
        child: Focus(
          autofocus: widget.active,
          canRequestFocus: widget.active,
          child: Box(
            width: constraints.maxWidth,
            style: theme.text,
            background: Style.plain,
            border: Border.rounded.withStyle(
              theme.focus.fg == null ? theme.dim : theme.focus,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teams', style: theme.focus.merge(Style.bold)),
                Text(where, style: theme.dim),
                if (_choices.isEmpty) ...[
                  const SizedBox(height: 1),
                  Text(noTeams),
                ] else if (listed > 0) ...[
                  const SizedBox(height: 1),
                  Picker<String>(
                    items: _choices,
                    onSelected: (name) {
                      final found = _named(name);
                      if (found != null) widget.onPick(found);
                    },
                    onChanged: (name) => setState(() => _highlighted = name),
                    onCanceled: widget.onCanceled,
                    maxVisibleRows: listed,
                    enabled: widget.active,
                    showInitialSelectionAtTop: false,
                    // One line each, a row too wide kept at both ends
                    // around `...`, as the original's picker cuts it: its
                    // number and label as one text.
                    itemBuilder: (context, item, _) => LayoutBuilder(
                      builder: (context, constraints) {
                        final number = pickerNumber(
                          _choices.indexOf(item),
                          _choices.length,
                        );
                        return Text(
                          rowLabel(
                            number,
                            item.label,
                            constraints.maxWidth.toInt() + number.length + 1,
                          ),
                          softWrap: false,
                        );
                      },
                    ),
                    unhandledKeys: {
                      'esc',
                      ...boundKeys(context, const ['select:cancel']),
                    },
                  ),
                ],
                const SizedBox(height: 1),
                Text(hint, style: theme.dim, softWrap: false, maxLines: 1),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// [label] as a numbered row cuts it in [width] cells: [number], a space and
/// the label as one text, a text too wide kept at both ends around `...`,
/// its head the cells left of half and its tail the rest, then the number
/// and its space taken off again, as the row draws the number apart.
String rowLabel(String number, String label, int width) {
  final whole = '$number $label';
  if (cellWidth(whole) <= width) return label;
  final room = math.max(0, width - 3);
  final headCells = room ~/ 2;
  final graphemes = whole.characters.toList();
  final head = StringBuffer();
  var used = 0;
  for (final grapheme in graphemes) {
    final cells = cellWidth(grapheme);
    if (used + cells > headCells) break;
    head.write(grapheme);
    used += cells;
  }
  final tail = <String>[];
  var tailUsed = 0;
  for (final grapheme in graphemes.reversed) {
    final cells = cellWidth(grapheme);
    if (tailUsed + cells > room - used) break;
    tail.insert(0, grapheme);
    tailUsed += cells;
  }
  final cut = '$head...${tail.join()}';
  final prefix = '$number ';
  return cut.startsWith(prefix) ? cut.substring(prefix.length) : cut;
}

/// The rows the notice keeps with its body cut away: its frame's two, its
/// title, its two choices with the gap above them, and its hint with its.
const noticeFixed = 8;

/// dimcode's one-time notice, in the pickers' frame above the prompt, as
/// the original's NoticeBox: what it may start, how to turn that off, and
/// the two answers. Esc closes it to show again next time, as 2 does.
class NoticeBox extends StatelessWidget {
  /// The notice in a layer of [room] rows, answered through [onAnswer] and
  /// closed by Esc through [onClose].
  const NoticeBox({
    super.key,
    required this.room,
    required this.onAnswer,
    required this.onClose,
  });

  /// The rows the layer it floats in has.
  final int room;

  /// Whether the person dismissed it for good, or asked to see it again.
  final void Function(bool dismissed) onAnswer;

  /// Esc: closed, to show again the next time it comes due.
  final void Function() onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final width = math.max(1, constraints.maxWidth - 4);
      // Short of room, after its body, the hint goes; its title and choices
      // stay.
      final hinted = room >= noticeFixed;
      final later = closeHint(context, 'to show it again next time');
      final hint = ['Enter to pick', '1–2', '↑↓ to move', ?later].join(' · ');
      Widget line(String text, [Style? style]) => Text(
        text,
        style: style,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
      // Wrapped at spaces, as the transcript is, so a path or a value a
      // person types stays whole on its line; only a word longer than the
      // line is cut, where it is drawn.
      final (:paragraphs, :parts) = _noticeBody(width);
      final body = <Widget>[
        for (final lines in paragraphs) ...[
          const SizedBox(height: 1),
          for (final each in lines) line(each),
        ],
      ];
      final chrome = _noticeChrome(room);
      final height = cutRows(math.max(0, room - chrome), body.length, parts);
      final items = [
        for (final choice in noticeChoices)
          PickerItem(value: choice.value, label: choice.label),
      ];
      return Actions(
        bindings: [
          Binding(
            'esc',
            "Close dimcode's notice, to show it again next time",
            onClose,
            id: 'select:cancel',
          ),
        ],
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Box(
              style: theme.text,
              background: Style.plain,
              border: Border.rounded.withStyle(
                theme.focus.fg == null ? theme.dim : theme.focus,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(dimcodeWords.title, theme.focus.merge(Style.bold)),
                  SizedBox(
                    height: height,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: body,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Picker<String>(
                    items: items,
                    showNumbers: true,
                    searchable: false,
                    wrapNavigation: false,
                    maxVisibleRows: items.length,
                    // The page and scroll keys are not the notice's, as the
                    // original's takes only its choices': the help under it
                    // scrolls with them.
                    unhandledKeys: {
                      'esc',
                      ...boundKeys(context, const ['select:cancel']),
                      ...permissionScrollSteps.keys,
                    },
                    itemBuilder: (_, item, _) => line(item.label),
                    onSelected: (value) => onAnswer(value == 'dismiss'),
                    onCanceled: onClose,
                  ),
                  if (hinted) ...[
                    const SizedBox(height: 1),
                    line(hint, theme.dim),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
