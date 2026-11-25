/// A link the agent asks the person to open, in the permission box's shape,
/// from the original's `ui/dialogs/Link.tsx`: the link whole, the host it
/// goes to, then a numbered choice. Nothing opens until a choice is made;
/// Esc answers cancel.
library;

import 'package:chord_tui/chord_tui.dart';

import 'leave.dart';

import '../../session/transcript/types.dart';
import '../transcript/agents/subagents.dart' show AskerPiece;
import 'asker.dart';
import 'fold.dart';
import 'form.dart' show linkHost;

/// What the person made of a link.
enum LinkAnswer { open, decline, cancel }

/// A link box's lines above its hint, [boxWidth] wide: the heading, the
/// message, the link and its host, and the choices, as they wrap.
int linkLines(LinkWait wait, int boxWidth) {
  final host = linkHost(wait.url);
  final inner = (boxWidth - 4).clamp(1, unbounded);
  int rows(String text, int width) =>
      TextLayout.compute(parseAnsi(text), maxWidth: width).height;
  final hostLine = host == null ? 'Not a web link' : 'Opens $host';
  return 1 +
      rows(wait.message, inner) +
      1 +
      rows(wait.url, (inner - 2).clamp(1, unbounded)) +
      rows(hostLine, (inner - 2).clamp(1, unbounded)) +
      1 +
      (host == null ? 1 : 2);
}

/// A link box's height before layout, [boxWidth] wide: its margin,
/// borders, hint and the row above it always drawn; its lines fold only
/// while [held].
({int fixed, int natural}) linkNatural(
  LinkWait wait,
  int boxWidth, {
  bool held = false,
}) => heldNatural(linkLines(wait, boxWidth), chrome: 5, held: held);

/// The link box for [wait], asked by [agent], answered through [onAnswer].
class LinkBox extends StatelessWidget {
  const LinkBox({
    super.key,
    required this.wait,
    required this.agent,
    this.asker = const [],
    this.picked,
    required this.onAnswer,
    this.focusNode,
    this.between = false,
    this.held = false,
    this.attendKey,
    this.maxRows,
    this.away = false,
    this.onLeave,
    this.highlight,
  });

  /// The list of agents has the keys: the highlight and the hint are not
  /// drawn, and the box keeps its place for when they come back.
  final bool away;

  /// ↓ on Decline, where there is a list of agents to go to; none where
  /// there is none.
  final void Function()? onLeave;

  /// The choice highlighted, kept by the window so the box comes back where
  /// it was left; none is the first.
  final ValueNotifier<LinkAnswer?>? highlight;

  final LinkWait wait;
  final String agent;

  /// Who asks, when a subagent or task does: its way down from the
  /// session, as the permission box's row names it, without `asks`; none
  /// when the session's own agent does.
  final List<AskerPiece> asker;

  /// The child in front, whose session asks, named when no subagent of
  /// its does.
  final PickedAsker? picked;
  final void Function(LinkAnswer answer) onAnswer;
  final FocusNode? focusNode;

  /// Asked with no turn running: the heading says so.
  final bool between;

  /// Asked between turns and not taken into yet: no keys.
  final bool held;

  /// The key that takes the keys into it while [held].
  final String? attendKey;

  /// The rows the window leaves the box, its margin with them; held, its
  /// lines above the hint fold into them.
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = linkHost(wait.url);
    final choices = host == null
        ? const [PickerItem(value: LinkAnswer.decline, label: '1. Decline')]
        : const [
            PickerItem(value: LinkAnswer.open, label: '1. Open in the browser'),
            PickerItem(value: LinkAnswer.decline, label: '2. Decline'),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = linkLines(wait, constraints.maxWidth);
        // Its margin, borders and the hint with the row above it.
        final room = maxRows == null
            ? null
            : (maxRows! - 5).clamp(0, unbounded);
        return _box(context, theme, host, choices, lines, room);
      },
    );
  }

  Widget _box(
    BuildContext context,
    ThemeData theme,
    String? host,
    List<PickerItem<LinkAnswer>> choices,
    int lines,
    int? room,
  ) {
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
                        says: 'asks you to open a link',
                        between: between,
                        style: theme.focus.merge(Style.bold),
                        theme: theme,
                      ),
                      softWrap: false,
                      maxLines: 1,
                    ),
                    Text.ansi(wait.message),
                    const SizedBox(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(wait.url, style: theme.link),
                          if (host == null)
                            Text('Not a web link', style: theme.error)
                          else
                            Text.rich(
                              TextSpan(
                                '',
                                style: theme.dim,
                                children: [
                                  const TextSpan('Opens '),
                                  TextSpan(host, style: Style.bold),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 1),
                    leavingLast(
                      values: [for (final choice in choices) choice.value],
                      highlighted: () => highlight?.value,
                      onLeave: held || away ? null : onLeave,
                      picker: Picker<LinkAnswer>(
                        items: choices,
                        enabled: !held && !away,
                        showNumbers: false,
                        wrapNavigation: true,
                        focusNode: focusNode,
                        autofocus: false,
                        initialValue: highlight?.value,
                        onChanged: (value) => highlight?.value = value,
                        maxVisibleRows: choices.length,
                        onSelected: onAnswer,
                        onCanceled: () => onAnswer(LinkAnswer.cancel),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              if (held)
                Text(
                  attendKey == null ? '' : '$attendKey to answer',
                  style: theme.dim,
                )
              else
                // Away, the line stays, blank, so the box holds still.
                Text(
                  away ? ' ' : 'Enter to choose · Esc to cancel',
                  style: theme.dim,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
