import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../app/context.dart' show capital, hintKeyOf;

import '../../session/transcript/types.dart';
import '../transcript/tools/paths.dart';
import 'asker.dart' show PickedAsker, betweenNote, pickedSpans, pickedText;
import 'permission.dart';
import 'leave.dart';
import 'permission_scroll.dart';

/// The oldest agent request, inline above the prompt with pinned answers.
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    super.key,
    required this.wait,
    required this.windowRows,
    required this.maxRows,
    required this.scroll,
    required this.onChoose,
    required this.onReject,
    this.focusNode,
    this.between = false,
    this.held = false,
    this.paths,
    this.onOverflow,
    this.isClosing,
    this.asker = const [],
    this.picked,
    this.away = false,
    this.onLeave,
    this.highlight,
    this.changeOverflows = false,
  });

  /// chord's own change asked about is taller than the transcript's room,
  /// so a save box's hint says the key that reads the whole of it.
  final bool changeOverflows;

  /// The list of agents has the keys: the highlight and the hint are not
  /// drawn, and the box keeps its place for when they come back.
  final bool away;

  /// ↓ on the last choice, where there is a list of agents to go to,
  /// rather than wrapping to the first; none where there is none.
  final void Function()? onLeave;

  /// The choice highlighted, by its value, kept by the window so the box
  /// comes back where it was left; none is the first.
  final ValueNotifier<String?>? highlight;

  /// Who asks, when a subagent does: `Agent(child) › Agent(grandchild)
  /// asks`, the names bold, whole; none when the session's own agent asks.
  final List<({String text, bool bold})> asker;

  /// The child in front, whose session asks: named on the row when no
  /// subagent of its asks, as the original's `child`.
  final PickedAsker? picked;

  /// Reads the live window barrier before a wheel report changes the proposal.
  final bool Function()? isClosing;

  final PermissionWait wait;
  final int windowRows;
  final int maxRows;
  final PermissionScroll scroll;
  final void Function(String) onChoose;
  final void Function() onReject;
  final FocusNode? focusNode;
  final bool between;
  final bool held;
  final PathView? paths;
  final void Function(bool)? onOverflow;

  @override
  Widget build(BuildContext context) =>
      wait.save == null ? _agents(context) : _saveBox(context, wait.save!);

  /// chord's own question: what it asks, bold in the permission colour,
  /// its numbered choices, then the key that says no.
  Widget _saveBox(BuildContext context, SaveBox save) => LayoutBuilder(
    builder: (context, constraints) =>
        _saveBoxOf(context, save, constraints.maxWidth),
  );

  Widget _saveBoxOf(BuildContext context, SaveBox save, int boxWidth) {
    final theme = Theme.of(context);
    final permission = theme.focus;
    final choices = saveChoices(wait);
    final hint = permissionHint(
      wait,
      held: false,
      reject: hintKeyOf(context, 'confirm:no'),
      pageUp: changeOverflows ? hintKeyOf(context, 'scroll:pageUp') : null,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Box(
        border: Border.rounded.withStyle(permission),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _furniture(
              Text(save.question, style: permission.merge(Style.bold)),
            ),
            const SizedBox(height: 1),
            SelectionContainer.disabled(
              key: const ValueKey('permission-choices-selection'),
              child: leavingLast(
                values: [for (final choice in choices) choice.value],
                highlighted: () => highlight?.value,
                onLeave: away ? null : onLeave,
                picker: Picker<String>(
                  key: const ValueKey('permission-choices'),
                  items: [
                    for (final choice in choices)
                      PickerItem(value: choice.value, label: choice.label),
                  ],
                  enabled: !away,
                  wrapNavigation: true,
                  showNumbers: false,
                  focusNode: focusNode,
                  initialValue: highlight?.value,
                  onChanged: (value) => highlight?.value = value,
                  // The scroll keys read the change it asks about, above.
                  unhandledKeys: permissionScrollSteps.keys.toSet(),
                  maxVisibleRows: permissionChoiceRows(wait, boxWidth),
                  // A choice naming a long file wraps; each is as tall as
                  // it is drawn, so none is pushed out of the box.
                  itemExtentBuilder: (item, _, width) =>
                      _rows(item.label, width),
                  itemBuilder: (context, item, _) => Text.ansi(item.label),
                  onSelected: onChoose,
                  onCanceled: onReject,
                ),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 1),
              _furniture(Text(away ? ' ' : hint, style: theme.dim)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _agents(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: scroll,
      builder: (context) {
        final theme = Theme.of(context);
        // The framework's focus role is the original permission colour.
        final permission = theme.focus;
        final width = math.max(constraints.maxWidth - 4, 1);
        final review = wait.review;
        final failed = review?.outcome == 'failed';
        // The keys bound now; no line when none is.
        final hint = permissionHint(
          wait,
          held: held,
          attend: hintKeyOf(context, 'session:attention'),
          reject: hintKeyOf(context, 'confirm:no'),
        );
        final question = permissionQuestion(wait);
        final choices = choicesFor(wait);
        final choiceRows = permissionChoiceRows(wait, constraints.maxWidth);
        final pinnedRows = permissionPinned(
          wait,
          constraints.maxWidth,
          hint: hint,
          asker: askerText(asker),
          picked: picked,
          between: between,
        );
        final whole = requestRows(wait, width, paths: paths);
        final wholeHeight = requestHeight(whole.rows, width);
        final room = math.min(
          wholeHeight,
          math.min(
            math.max(windowRows ~/ 2, 1),
            math.max(maxRows - pinnedRows, 0),
          ),
        );
        final request = room <= 1 && wholeHeight > room
            ? requestRows(
                wait,
                width,
                titleWidth: width - countRoom(wholeHeight) - 1,
                paths: paths,
              )
            : whole;
        final total = requestHeight(request.rows, width);
        scroll.configure(total, room);
        final report = onOverflow;
        if (report != null) {
          context.owner.afterLayout(() => report(total > room));
        }
        final view = requestView(total, room, scroll.top);
        final hidden = hiddenRows(total, view.top, view.shown);
        final count = room <= 1 && total > room ? requestCount(hidden) : null;
        return Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Box(
            border: Border.rounded.withStyle(permission),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (asker.isNotEmpty)
                  _furniture(
                    Text.rich(
                      TextSpan(
                        '',
                        // The whole row in the accent, as the original draws it.
                        style: theme.accent,
                        children: [
                          for (final piece in asker)
                            TextSpan(
                              piece.text,
                              style: piece.bold ? Style.bold : null,
                            ),
                          // A subagent's or task's request between turns
                          // says so on its own row, after who asks.
                          if (between) TextSpan(betweenNote, style: theme.dim),
                        ],
                      ),
                    ),
                  ),
                if (asker.isEmpty && picked != null)
                  _furniture(
                    Text.rich(
                      TextSpan(
                        '',
                        children: [
                          ...pickedSpans(picked!, Style.plain),
                          const TextSpan(' asks'),
                          if (between) TextSpan(betweenNote, style: theme.dim),
                        ],
                      ),
                    ),
                  )
                else if (between && asker.isEmpty)
                  _furniture(
                    Text.rich(
                      TextSpan(
                        '',
                        children: [
                          const TextSpan('main', style: Style.bold),
                          const TextSpan(' asks'),
                          TextSpan(betweenNote, style: theme.dim),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _furniture(
                        Text.ansi(
                          request.pinned,
                          style: permission.merge(Style.bold),
                          softWrap: false,
                          overflow: TextOverflow.middle,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    if (count != null)
                      SizedBox(
                        width: math.min(cellWidth(count), width),
                        child: _furniture(
                          Text(
                            count,
                            style: theme.dim,
                            softWrap: false,
                            overflow: TextOverflow.middle,
                            maxLines: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                if (room > 0) ...[
                  if (view.above)
                    _furniture(
                      Text(
                        requestRule(
                          '↑',
                          hidden.above,
                          held ? null : 'pageup',
                          width,
                        ),
                        style: theme.dim,
                        softWrap: false,
                        overflow: TextOverflow.middle,
                      ),
                    ),
                  if (view.shown > 0)
                    Listener(
                      behavior: HitTestBehavior.opaque,
                      absorbPointerSignal: total > room,
                      onPointerSignal: (event) {
                        if ((isClosing?.call() ?? false) || total <= room) {
                          return;
                        }
                        for (var i = 0; i < event.scrollDelta.y.abs(); i++) {
                          scroll.step(
                            event.scrollDelta.y < 0
                                ? ScrollStep.lineUp
                                : ScrollStep.lineDown,
                          );
                        }
                      },
                      child: SizedBox(
                        height: view.shown,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -view.top,
                              height: total,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final row in request.rows)
                                    _requestRow(row, permission, theme.dim),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (view.below)
                    _furniture(
                      Text(
                        requestRule(
                          '↓',
                          hidden.below,
                          held ? null : 'pagedown',
                          width,
                        ),
                        style: theme.dim,
                        softWrap: false,
                        overflow: TextOverflow.middle,
                      ),
                    ),
                ],
                const SizedBox(height: 1),
                if (review == null)
                  _furniture(Text(question))
                else if (failed)
                  _furniture(Text.ansi(question, style: theme.error))
                else ...[
                  _furniture(
                    Text('The safety review held this:', style: theme.warning),
                  ),
                  _furniture(Text.ansi(review.reason)),
                ],
                if (review != null) const SizedBox(height: 1),
                SelectionContainer.disabled(
                  key: const ValueKey('permission-choices-selection'),
                  child: leavingLast(
                    values: [for (final choice in choices) choice.value],
                    highlighted: () => highlight?.value,
                    onLeave: held || away ? null : onLeave,
                    picker: Picker<String>(
                      key: const ValueKey('permission-choices'),
                      items: [
                        for (final choice in choices)
                          PickerItem(value: choice.value, label: choice.label),
                      ],
                      enabled: !held && !away,
                      wrapNavigation: true,
                      showNumbers: false,
                      focusNode: focusNode,
                      initialValue: highlight?.value,
                      onChanged: (value) => highlight?.value = value,
                      unhandledKeys: permissionScrollSteps.keys.toSet(),
                      maxVisibleRows: choiceRows,
                      itemBuilder: (context, item, _) => Text.ansi(item.label),
                      onSelected: onChoose,
                      onCanceled: onReject,
                    ),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 1),
                  // Away, the line stays, blank, so the box holds still.
                  _furniture(Text(away ? ' ' : hint, style: theme.dim)),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _requestRow(RequestRow row, Style permission, Style dim) =>
    switch (row) {
      RequestDiff(:final view) => Padding(
        padding: const EdgeInsets.only(left: inputIndent),
        child: Diff.fromView(
          view.view,
          title: view.path,
          showTitle: false,
          wrap: DiffWrap.wrapAnsi,
        ),
      ),
      RequestText(:final text, :final kind) => Padding(
        padding: EdgeInsets.only(left: kind == 'input' ? inputIndent : 0),
        child: _furniture(
          Text.ansi(
            text.isEmpty ? ' ' : text,
            style: kind == 'title'
                ? permission.merge(Style.bold)
                : kind == 'location'
                ? dim
                : null,
            softWrap: false,
            overflow: TextOverflow.middle,
            maxLines: 1,
          ),
        ),
      ),
    };

/// The question above a permission's choices, or what its safety review
/// says.
String permissionQuestion(PermissionWait wait) {
  final review = wait.review;
  return review == null
      ? 'Do you want to proceed?'
      : review.outcome == 'failed'
      ? 'The safety review could not run (${review.reason}). Allow it yourself, or deny it.'
      : 'The safety review held this:\n${review.reason}';
}

/// The hint under a permission's choices, by the keys bound to [attend]
/// to it while [held] and to [reject] it; none when that key is unbound.
/// chord's own question says what no does, and, given [pageUp] while the
/// change it asks about overflows, the key that reads the whole of it.
String? permissionHint(
  PermissionWait wait, {
  required bool held,
  String? attend,
  String? reject,
  String? pageUp,
}) => switch (wait.save) {
  final save? =>
    reject == null
        ? null
        : '${capital(reject)} to ${save.escape}'
              '${pageUp == null ? '' : ' · $pageUp to read the whole change'}',
  null =>
    held
        ? (attend == null ? null : '$attend to answer')
        : reject == null
        ? null
        : '${capital(reject)} to reject${wait.deadlineAt == null ? '' : ' · denied by itself in 5 minutes'}',
};

/// The asker row's text, as it wraps.
String askerText(List<({String text, bool bold})> asker) =>
    asker.map((piece) => piece.text).join();

int _rows(String text, int room) =>
    TextLayout.compute(parseAnsi(text), maxWidth: math.max(room, 1)).height;

/// The rows a permission box [boxWidth] wide gives its choices, as they
/// wrap.
int permissionChoiceRows(PermissionWait wait, int boxWidth) {
  final choices = wait.save == null ? choicesFor(wait) : saveChoices(wait);
  final choiceWidth = math.max(math.max(boxWidth - 4, 1) - 2, 1);
  return choices.isEmpty
      ? 1
      : choices.fold<int>(0, (n, c) => n + _rows(c.label, choiceWidth));
}

/// The rows of a permission box [boxWidth] wide that never give way: its
/// margin, borders, title, who asks, the question and the choices with the
/// gaps between them, and the [hint] with the gap above it.
int permissionPinned(
  PermissionWait wait,
  int boxWidth, {
  String? hint,
  String asker = '',
  PickedAsker? picked,
  bool between = false,
}) {
  final width = math.max(boxWidth - 4, 1);
  final review = wait.review;
  if (wait.save case final save?) {
    // Margin, borders, the question, the gap, the choices and the hint.
    return 1 +
        2 +
        _rows(save.question, width) +
        1 +
        permissionChoiceRows(wait, boxWidth) +
        (hint == null ? 0 : 1 + _rows(hint, width));
  }
  // A child in front names itself where no subagent of its asks.
  final named = asker.isNotEmpty
      ? asker
      : picked == null
      ? ''
      : '${pickedText(picked)} asks';
  // No hint takes its gap with it.
  final hintRows = hint == null ? -1 : _rows(hint, width);
  // Margin, borders, title, question gap, review trailing gap and hint gap.
  return 1 +
      2 +
      1 +
      // Between turns, the asker's row says so, or main's own row does.
      (named.isEmpty
          ? (between ? 1 : 0)
          : _rows(between ? '$named$betweenNote' : named, width)) +
      1 +
      _rows(permissionQuestion(wait), width) +
      (review == null ? 0 : 1) +
      permissionChoiceRows(wait, boxWidth) +
      1 +
      hintRows;
}

/// A permission box's height before layout, [boxWidth] wide in a window
/// [windowRows] high: [fixed], its pinned rows, and [natural], with its
/// request body as tall as it is drawn with room, at most half the window.
({int fixed, int natural}) permissionNatural(
  PermissionWait wait,
  int boxWidth, {
  required int windowRows,
  String? hint,
  String asker = '',
  PickedAsker? picked,
  bool between = false,
  PathView? paths,
}) {
  final width = math.max(boxWidth - 4, 1);
  final fixed = permissionPinned(
    wait,
    boxWidth,
    hint: hint,
    asker: asker,
    picked: picked,
    between: between,
  );
  // chord's own question has no request body to give way.
  if (wait.save != null) return (fixed: fixed, natural: fixed);
  final whole = requestHeight(
    requestRows(wait, width, paths: paths).rows,
    width,
  );
  return (
    fixed: fixed,
    natural: fixed + math.min(whole, math.max(windowRows ~/ 2, 1)),
  );
}

// Only the proposal's Diff remains selectable; request controls are furniture.
Widget _furniture(Widget child) => SelectionContainer.disabled(child: child);
