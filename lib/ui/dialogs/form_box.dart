/// A form the agent asks the person to fill in, in the prompt box's place,
/// from the original's `ui/dialogs/Form.tsx`: who asks, the agent's message,
/// the schema's description, then the framework's [Form] with Accept and
/// Decline.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/elicitations.dart';
import '../../session/transcript/types.dart';
import '../transcript/agents/subagents.dart' show AskerPiece;
import 'asker.dart';
import 'fold.dart';

/// The rows a form box takes besides its message and fields: the border,
/// the heading, the blank rows around the fields, the buttons and the hint.
const formChrome = 8;

/// The most rows a form box takes in a window [windowRows] high: the window
/// less the header and five rows of transcript above it and the status line
/// below, so the prompt the form answers and the working line stay in sight.
int formRowLimit(int windowRows) => math.max(windowRows - 7, formChrome + 4);

/// The rows the agent's [message] takes wrapped to [width], at most what
/// leaves three rows of [room] for the fields; past that it is cut with `…`.
int messageRows(String message, int width, int room) => math.min(
  TextLayout.compute(parseAnsi(message), maxWidth: math.max(width, 1)).height,
  math.max(room - 3, 1),
);

String? _description(FormWait wait) => switch (wait.schema['description']) {
  final String text when text.isNotEmpty => text,
  _ => null,
};

/// A form box [boxWidth] wide in a window [windowRows] high, its form as
/// [data] has it: the rows of the agent's [message], the rows its fields
/// may take, and its [lines] above the hint.
({int message, int formRows, int lines}) formLines(
  FormWait wait,
  FormData data,
  int boxWidth, {
  required int windowRows,
}) {
  final inner = math.max(boxWidth - 4, 10);
  final description = _description(wait);
  final limit = formRowLimit(windowRows);
  final fixed = formChrome + (description == null ? 0 : 1);
  final message = messageRows(wait.message, inner, limit - fixed);
  final formRows = math.max(limit - fixed - message, 1);
  final fields = data.rows(formRows).length;
  return (
    message: message,
    formRows: formRows,
    lines:
        1 +
        message +
        (description == null ? 0 : 1) +
        1 +
        fields +
        (fields > 0 ? 1 : 0) +
        1,
  );
}

/// A form box's height before layout, [boxWidth] wide in a window
/// [windowRows] high: whole unless [held], when its lines fold to one.
/// With the keys, the form draws its own hint under its buttons; held, the
/// box draws the one that takes the keys, with a [hint] key.
({int fixed, int natural}) formNatural(
  FormWait wait,
  FormData data,
  int boxWidth, {
  required int windowRows,
  bool held = false,
  bool hint = true,
}) => heldNatural(
  formLines(wait, data, boxWidth, windowRows: windowRows).lines,
  chrome: 3 + (!held || hint ? 2 : 0),
  held: held,
);

/// The form box for [wait], asked by [agent], answered through [onAnswer].
/// Held, asked between turns with the keys elsewhere, its form keeps what
/// was typed and draws no marks; [attendKey] names the key that takes it.
class FormBox extends StatelessWidget {
  const FormBox({
    super.key,
    required this.wait,
    required this.agent,
    this.asker = const [],
    this.picked,
    required this.controller,
    required this.windowRows,
    required this.onAnswer,
    this.focusNode,
    this.between = false,
    this.held = false,
    this.attendKey,
    this.maxRows,
    this.away = false,
    this.onLeave,
  });

  /// The list of agents has the keys: no `❯`, highlight or hint is drawn,
  /// the hint's rows kept blank so the box holds still.
  final bool away;

  /// ↓ on the buttons, where there is a list of agents to go to.
  final void Function()? onLeave;

  final FormWait wait;
  final String agent;

  /// Who asks, when a subagent or task does: its way down from the
  /// session, as the permission box's row names it, without `asks`; none
  /// when the session's own agent does.
  final List<AskerPiece> asker;

  /// The child in front, whose session asks, named when no subagent of
  /// its does.
  final PickedAsker? picked;

  /// The form as the person left it, kept by the window.
  final FormController controller;
  final int windowRows;
  final void Function(ElicitationReply reply) onAnswer;
  final FocusNode? focusNode;

  /// Asked with no turn running: the heading says so.
  final bool between;

  /// Asked between turns and not taken into yet: no keys.
  final bool held;

  /// The key that takes the keys into it while [held].
  final String? attendKey;

  /// The rows the box may take, the rest of the window's furniture laid:
  /// held, its body folds into them, keeping the hint in sight.
  final int? maxRows;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final title = switch (wait.schema['title']) {
        final String title when title.isNotEmpty => ' · $title',
        _ => '',
      };
      final description = _description(wait);
      final (:message, :formRows, :lines) = formLines(
        wait,
        controller.value,
        constraints.maxWidth,
        windowRows: windowRows,
      );
      // Its margin, borders and the hint with the row above it.
      final room = maxRows == null ? null : math.max(maxRows! - 5, 0);
      return Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Box(
          border: Border.rounded.withStyle(theme.focus),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: SelectionContainer.disabled(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeldFold(
                  held: held,
                  lines: lines,
                  room: room,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        askerHeading(
                          asker: asker,
                          picked: picked,
                          agent: agent,
                          says: 'asks for input$title',
                          between: between,
                          style: theme.focus.merge(Style.bold),
                          theme: theme,
                        ),
                        softWrap: false,
                        maxLines: 1,
                      ),
                      Text.ansi(
                        wait.message,
                        maxLines: message,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (description != null)
                        Text.ansi(
                          description,
                          style: theme.dim,
                          softWrap: false,
                          maxLines: 1,
                        ),
                      const SizedBox(height: 1),
                      Form(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: false,
                        enabled: !held && !away,
                        onLeave: onLeave,
                        maxRows: formRows,
                        submitLabel: 'Accept',
                        declineLabel: 'Decline',
                        onSubmitted: (values) => onAnswer(AcceptReply(values)),
                        onDeclined: () => onAnswer(const DeclineReply()),
                        onCanceled: () => onAnswer(const CancelReply()),
                      ),
                      // The hint's gap and line, blank while away.
                      if (away && !held) const SizedBox(height: 2),
                    ],
                  ),
                ),
                if (held && attendKey != null) ...[
                  const SizedBox(height: 1),
                  Text('$attendKey to answer', style: theme.dim),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
