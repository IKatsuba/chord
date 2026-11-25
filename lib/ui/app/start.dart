import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../agents.dart';
import '../../session/sessions.dart';
import '../pickers/pickers.dart';
import '../pickers/state.dart';
import '../header/header.dart';
import '../header/mark.dart' as data;
import '../header/mark_widget.dart';
import '../header/wordmark.dart';
import '../pickers/picker.dart';
import '../theme/theme.dart';
import 'context.dart' show boundKeys, closeHint;
import 'start_layout.dart';
import 'startup_choice.dart';

/// The original start page's agent navigation and cancellation hint.
const agentHint = '↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel';

/// A new invocation's responsive title and catalog, before any agent starts.
class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    required this.version,
    required this.directory,
    required this.agents,
    required this.onPicked,
    this.onCanceled,
    this.preferred = defaultAgent,
    this.offered,
  });

  final String version;
  final String directory;

  /// Every agent chord can start; [offered] picks from them.
  final List<ListedAgent> agents;

  /// The `offeredAgents` setting; without it the default catalog shows.
  final List<String>? offered;
  final String preferred;
  final void Function(String) onPicked;
  final void Function()? onCanceled;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _selection = StartupSelection();

  ({List<ListedAgent> agents, List<String> unknown}) get _shown =>
      offeredFrom(widget.agents, widget.offered);
  final _pageFocus = FocusNode(debugLabel: 'start page');

  void _freeze() {
    _pageFocus
      ..canRequestFocus = false
      ..descendantsAreFocusable = false;
    _pageFocus.unfocus();
  }

  @override
  void dispose() {
    _pageFocus.dispose();
    super.dispose();
  }

  void _cancel(BuildContext context) {
    if (!_selection.settle(null)) return;
    _freeze();
    widget.onCanceled?.call();
    exitApp(context);
  }

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    child: Actions(
      bindings: [
        Binding(
          'esc',
          'Cancel agent selection',
          () => _cancel(context),
          id: 'select:cancel',
        ),
        Binding('ctrl+c', 'Cancel agent selection', () => _cancel(context)),
      ],
      child: Focus(
        focusNode: _pageFocus,
        canRequestFocus: !_selection.settled,
        autofocus: _shown.agents.isEmpty,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final (:agents, :unknown) = _shown;
            final choices = agentChoices(agents, widget.preferred);
            final nothingKnown = choices.isEmpty && unknown.isNotEmpty;
            // The key that cancels as the file binds it, as useAgentHint.
            final hint = [
              if (choices.isNotEmpty) ...[
                '↑↓ or j/k to move',
                'Enter or 1–9 to select',
              ],
              ?closeHint(context, 'to cancel'),
            ].join(' · ');
            final column = startColumn(constraints.maxWidth);
            final page = noteLayout(
              columns: constraints.maxWidth,
              rows: constraints.maxHeight,
              // The sentence under `No agents available` is the list's
              // second row.
              lines: nothingKnown ? 2 : math.max(choices.length, 1),
              hintRows: hintRows(hint, column - 2),
              noteRows: choices.isNotEmpty && unknown.isNotEmpty ? 2 : 0,
            );
            return Padding(
              padding: EdgeInsets.only(top: page.top),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Title(
                    step: page.step,
                    version: widget.version,
                    directory: widget.directory,
                    columns: constraints.maxWidth,
                  ),
                  SizedBox(
                    key: const ValueKey('agents'),
                    width: column,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: page.step == StartStep.none ? 0 : 1,
                        left: 1,
                        right: 1,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select agent'),
                          const SizedBox(height: 1),
                          if (choices.isEmpty) ...[
                            Text(
                              'No agents available',
                              style: Theme.of(context).dim,
                            ),
                            if (nothingKnown)
                              Text(
                                'offeredAgents in settings.json names no '
                                'agent chord knows.',
                                style: Theme.of(context).dim,
                                softWrap: false,
                                maxLines: 1,
                                overflow: TextOverflow.middle,
                              ),
                          ] else
                            Picker<String>(
                              enabled: !_selection.settled,
                              showInitialSelectionAtTop: false,
                              countHiddenItemsAbove: true,
                              // Esc is the page's, as the file binds it.
                              unhandledKeys: {
                                'esc',
                                'pageup',
                                'pagedown',
                                'home',
                                'end',
                                ...boundKeys(context, const ['select:cancel']),
                              },
                              items: [
                                for (final choice in choices)
                                  PickerItem(
                                    value: choice.value,
                                    label: choice.label,
                                  ),
                              ],
                              initialValue: widget.preferred,
                              // The layout's listRows excludes the hidden-count row.
                              maxVisibleRows:
                                  page.listRows +
                                  (choices.length > page.listRows ? 1 : 0),
                              itemBuilder: (context, item, _) => Text.ansi(
                                item.label,
                                softWrap: false,
                                maxLines: 1,
                                overflow: TextOverflow.middle,
                              ),
                              onSelected: (value) {
                                if (!_selection.settle(value)) return;
                                _freeze();
                                widget.onPicked(value);
                                exitApp(context);
                              },
                              onCanceled: () => _cancel(context),
                            ),
                          const SizedBox(height: 1),
                          Text(hint, style: Theme.of(context).dim),
                          if (page.note) ...[
                            const SizedBox(height: 1),
                            Text(
                              unknownNote(unknown, column - 2),
                              style: Theme.of(context).dim,
                              softWrap: false,
                              maxLines: 1,
                              overflow: TextOverflow.middle,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title({
    required this.step,
    required this.version,
    required this.directory,
    required this.columns,
    this.agent,
  });
  final StartStep step;
  final String version;
  final String directory;
  final int columns;
  final String? agent;

  @override
  Widget build(BuildContext context) {
    if (step == StartStep.none) return const SizedBox();
    final width = math.max(1, columns - 2);
    final theme = Theme.of(context);
    if (step == StartStep.line) {
      return SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (context, constraints) => Text.rich(
            TextSpan(
              '',
              children: [
                const TextSpan('chord', style: Style.bold),
                TextSpan(
                  ' ${versionLine(version: version, agent: agent, directory: directory, width: constraints.maxWidth - 6)}',
                  style: theme.dim,
                ),
              ],
            ),
            align: TextAlign.center,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.middle,
          ),
        ),
      );
    }
    final full = step == StartStep.full;
    final colors = wordmarkColours(markColour(chordThemeOf(context).mark));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.only(
              left:
                  (width -
                      ((full ? 9 : 4) +
                          (full ? 3 : 2) +
                          (colors == null
                              ? 5
                              : full
                              ? 45
                              : 19)) +
                      1) ~/
                  2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Mark(grid: full ? data.splashMark : data.mark),
                SizedBox(width: full ? 3 : 2),
                Padding(
                  padding: EdgeInsets.only(
                    top:
                        ((full ? 8 : 4) -
                            (colors == null
                                ? 1
                                : full
                                ? 6
                                : 2) +
                            1) ~/
                        2,
                  ),
                  child: _wordmark(full, colors),
                ),
              ],
            ),
          ),
        ),
        if (full) ...[const SizedBox(height: 1), Text(tagline)],
        SizedBox(
          width: width,
          child: LayoutBuilder(
            builder: (context, constraints) => Text(
              versionLine(
                version: version,
                agent: agent,
                directory: directory,
                width: constraints.maxWidth,
              ),
              style: theme.dim,
              align: TextAlign.center,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.middle,
            ),
          ),
        ),
      ],
    );
  }
}

Widget _wordmark(bool full, (String, String)? colors) {
  if (colors == null) return Text('chord', style: Style.bold);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final row in full ? fullWordmark : compactWordmark)
        Text.rich(
          TextSpan(
            '',
            children: [
              for (final segment in row)
                TextSpan(
                  segment.text,
                  style: Style(
                    fg: markColor(segment.role == 0 ? colors.$1 : colors.$2),
                  ),
                ),
            ],
          ),
          softWrap: false,
          maxLines: 1,
        ),
    ],
  );
}

/// Startup resume title page before any process, sharing the catalog's title.
class ResumeStartPage extends StatefulWidget {
  const ResumeStartPage({
    super.key,
    required this.version,
    required this.directory,
    required this.agent,
    required this.cwd,
    required this.sessions,
    this.home,
    required this.onPicked,
    this.onCanceled,
    this.openedAt,
  });
  final String version, directory, agent, cwd;
  final String? home;
  final List<EarlierSession> sessions;
  final num? openedAt;
  final void Function(EarlierSession) onPicked;
  final void Function()? onCanceled;
  @override
  State<ResumeStartPage> createState() => _ResumeStartPageState();
}

class _ResumeStartPageState extends State<ResumeStartPage> {
  final _selection = StartupSelection();
  final _focus = FocusNode(debugLabel: 'resume startup');
  late ResumePickerState _picker = ResumePickerState(
    sessions: widget.sessions,
    cwd: widget.cwd,
    opening: Object(),
    openedAt: widget.openedAt ?? DateTime.now().millisecondsSinceEpoch,
  );
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _freeze() {
    _focus
      ..canRequestFocus = false
      ..descendantsAreFocusable = false;
    _focus.unfocus();
  }

  void _cancel(BuildContext context) {
    if (!_selection.settle(null)) return;
    _freeze();
    widget.onCanceled?.call();
    exitApp(context);
  }

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    child: Actions(
      bindings: [
        Binding('ctrl+c', 'Cancel resume startup', () => _cancel(context)),
        Binding('ctrl+d', 'Cancel resume startup', () => _cancel(context)),
      ],
      child: Focus(
        focusNode: _focus,
        canRequestFocus: !_selection.settled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final choices = sessionChoices(
              resumeChoices(_picker),
              _picker.openedAt,
              directories: _picker.everywhere,
              home: widget.home,
            );
            final column = startColumn(constraints.maxWidth, framed: true);
            final hint = [
              if (choices.isNotEmpty) 'Enter to resume',
              'Ctrl+a for ${_picker.everywhere ? 'this directory' : 'all directories'}',
              'Esc to quit',
            ].join(' · ');
            final page = startLayout(
              columns: constraints.maxWidth,
              rows: constraints.maxHeight,
              lines: math.max(1, sessionListLines(choices, column)),
              framed: true,
              hintRows: hintRows(hint, column - 4),
            );
            return Padding(
              padding: EdgeInsets.only(top: page.top),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Title(
                    step: page.step,
                    version: widget.version,
                    directory: widget.directory,
                    agent: widget.agent,
                    columns: constraints.maxWidth,
                  ),
                  const SizedBox(height: 1),
                  SizedBox(
                    width: column,
                    child: ResumePicker(
                      key: ValueKey((_picker.opening, _picker.everywhere)),
                      picker: _picker,
                      agent: widget.agent,
                      home: widget.home,
                      rows: page.listRows,
                      // Startup keeps its selected row; the window clips the
                      // lower hint/border as the original title page does.
                      room: unbounded,
                      active: !_selection.settled,
                      starting: true,
                      onToggleScope: () {
                        if (!_selection.settled) {
                          setState(
                            () => _picker = toggledResumeScope(
                              _picker,
                              widget.openedAt ??
                                  DateTime.now().millisecondsSinceEpoch,
                            ),
                          );
                        }
                      },
                      onSelected: (chosen) {
                        if (!_selection.settle(chosen.resume.sessionId)) return;
                        _freeze();
                        widget.onPicked(chosen);
                        exitApp(context);
                      },
                      onCanceled: () => _cancel(context),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
