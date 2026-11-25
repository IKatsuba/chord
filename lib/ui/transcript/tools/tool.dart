import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import '../../../session/transcript/types.dart' as model;
import 'tools.dart';
import 'diff.dart';
import 'paths.dart';

import '../../app/context.dart' show hintKeyOf;
import '../agent_colours.dart';
import '../gap.dart';
import '../selection.dart' show selectionChild, selectionChildren;
import 'plan_ask.dart' show PlanAskBody;
import 'proposal.dart' show proposalOf;
import 'proposal_view.dart';
import 'settings_row.dart';
import '../message.dart' show ArrowTone, messageSource, outArrow, wrapLines;

/// A fixed-width marker beside a transcript block.
class Gutter extends StatelessWidget {
  /// A marker that never takes space from its neighboring text.
  const Gutter(this.text, {super.key, this.width = 2, this.style});

  /// The marker's glyph.
  final String text;

  /// Cells reserved for the marker.
  final int width;

  /// Marker tone.
  final Style? style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: SelectionContainer.disabled(
      child: Text(text, style: style, softWrap: false),
    ),
  );
}

/// A result line hanging below the turn it ends, with no gap above it.
class Outcome extends StatelessWidget {
  /// An interrupted, stopped or permission result.
  const Outcome(this.text, {super.key, this.failed = false});

  /// The original's result wording.
  final String text;

  /// Whether the words use the error tone.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Under(
      first: true,
      child: Text.ansi(text, style: failed ? theme.error : theme.dim),
    );
  }
}

/// [child] laid out in [width] cells, as the original lays out what it
/// draws under a call's `⎿` in the row's width less the gutter: the row
/// beside the gutter is two cells wider than that, as the transcript's
/// inset is counted once here.
Widget inRoom(int width, Widget child) => Align(
  alignment: Alignment.topLeft,
  heightFactor: 1,
  child: SizedBox(width: width, child: child),
);

/// A summary row with the original's hanging result gutter.
class Under extends StatelessWidget {
  /// The first row carries the result mark; continuation rows align below it.
  const Under({super.key, required this.first, required this.child});

  /// Whether to show the result mark.
  final bool first;

  /// The row's text or rich output.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gutter(first ? '⎿' : ' ', width: 3, style: Theme.of(context).dim),
        Expanded(child: child),
      ],
    ),
  );
}

/// A failure or warning, set apart as a transcript block.
class Failure extends StatelessWidget {
  /// Failure words, or a warning when [warning] is true.
  const Failure(this.text, {super.key, this.warning = false});

  /// What failed or what to notice.
  final String text;

  /// Whether chord continued past it.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = warning ? theme.warning : theme.error;
    return blockGap(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gutter('⏺', style: style),
          Expanded(child: Text.ansi(text, style: style)),
        ],
      ),
    );
  }
}

/// The original's visible count of source lines hidden by ctrl+o.
class Folded extends StatelessWidget {
  /// A Read or terminal's hidden source lines.
  const Folded(this.hidden, {super.key});

  /// Number of source lines not drawn.
  final int hidden;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 5),
    child: SelectionContainer.disabled(
      child: Text(
        foldedLine(hidden, hintKeyOf(context, 'app:toggleTranscript')),
        style: Theme.of(context).dim,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.middle,
      ),
    ),
  );
}

/// A tool headline, its result, terminal tails, edits and Guardian state.
class Tool extends StatelessWidget {
  /// Draws the reducer's call without owning its state or detail setting.
  const Tool(
    this.call, {
    super.key,
    required this.expanded,
    this.ended = false,
    this.asked = false,
    this.paths,
    this.selectionSource,
    this.agent,
    this.chordServer,
  });

  /// The name the session gave chord's own server, by which a call to it
  /// is read as chord's before chord has tied it to what it served.
  final String? chordServer;

  /// The agent as the window names it, for a plan's words.
  final String? agent;

  /// The merged tool call.
  final model.ToolCall call;

  /// Whether folded text and terminal output is shown whole.
  final bool expanded;

  /// Whether an unfinished call no longer waits on its turn.
  final bool ended;

  /// Whether any permission waiting on the turn names this call.
  final bool asked;

  /// Session path spellings used by edit headlines.
  final PathView? paths;

  /// Same immutable current source used by the transcript delegate.
  final SelectionSource? selectionSource;

  @override
  Widget build(BuildContext context) {
    final guardian = guardianView(call);
    if (guardian == GuardianView.hidden) return const SizedBox();
    final theme = Theme.of(context);
    if (guardian == GuardianView.reviewing) {
      return SelectionContainer.disabled(
        child: blockGap(
          Row(
            children: [
              const Gutter(' '),
              Expanded(
                child: Text(
                  guardianReviewing,
                  style: theme.dim,
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.middle,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 2).clamp(1, unbounded);
        final room = (width - 5).clamp(1, unbounded);
        final view = summary(
          call,
          expanded,
          ended: ended,
          asked: asked,
          width: room,
          chordServer: chordServer,
        );
        final live = toneOf(call, asked: asked);
        final tone = ended && live == Tone.running ? Tone.pending : live;
        final resultStyle = tone == Tone.failed ? theme.error : theme.dim;
        // A read of every key says the key that opens it.
        final line = foldedSettingsNote(
          headline(call, chordServer: chordServer),
          call.chord,
          expanded: expanded,
          key: hintKeyOf(context, 'app:toggleTranscript'),
        );
        final settings = switch (call.chord) {
          final chord? => settingsRows(chord, expanded: expanded, width: room),
          null => null,
        };
        final recipient = line.sent
            ? AgentColours.of(context)[line.name]
            : null;
        final sent = sentBody(call, chordServer: chordServer);
        final children = <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (line.sent)
                Arrow('→', outArrow(tone), colour: recipient)
              else
                ToolMarker(tone),
              Expanded(
                child: selectionSource == null
                    ? _glyphRows(headlineRows(line, width, colour: recipient))
                    : Text.fromSelectionSource(
                        selectionChild(selectionSource!, 'headline'),
                      ),
              ),
            ],
          ),
        ];
        final plan = call.plan;
        if (plan != null) {
          // The plan put to the person stands in its content's place.
          children.add(
            PlanAskBody(
              plan,
              agent: agent ?? plan.wait.agent.name,
              selectionSource: selectionSource,
            ),
          );
          return blockGap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        var first = true;
        final review = call.review;
        if (sent != null) {
          // What was sent stands where the call's lines would, whole.
          children.add(
            MessageBody(
              sent.text,
              ending: sent.ending,
              source: selectionSource == null
                  ? null
                  : selectionChild(selectionSource!, 'message'),
            ),
          );
          return blockGap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        if (review != null) {
          children.add(
            Under(
              first: first,
              child: SelectionContainer.disabled(
                child: Text(
                  'Reviewed: ${review.outcome}',
                  style: review.outcome == 'failed'
                      ? theme.error
                      : theme.warning,
                ),
              ),
            ),
          );
          first = false;
        }
        final proposal = switch (call.chord) {
          final chord? => proposalOf(chord),
          null => null,
        };
        if (proposal != null) {
          // The team stands where the call's lines would.
          children.add(
            ProposalBody(
              proposal,
              expanded: expanded,
              width: room,
              source: selectionSource,
            ),
          );
          return blockGap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        if (settings != null && selectionSource != null) {
          // What it read or changed, selectable, as the source styles it.
          children.add(
            Under(
              first: first,
              child: Text.fromSelectionSource(
                selectionChild(selectionSource!, 'settings'),
                softWrap: false,
              ),
            ),
          );
          return blockGap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        if (settings != null) {
          // What it read or changed: labels dim, values in the text's own
          // colour, each wrapped under its own column and never folded.
          for (final row in settings) {
            children.add(
              Under(
                first: first,
                child: SelectionContainer.disabled(
                  child: Text.rich(
                    TextSpan(
                      '',
                      children: [
                        TextSpan(row.label, style: theme.dim),
                        TextSpan(
                          row.text,
                          style: switch (row.tone) {
                            SettingsTone.warning => theme.warning,
                            SettingsTone.success => theme.success,
                            SettingsTone.dim => theme.dim,
                            SettingsTone.text => Style.plain,
                          },
                        ),
                      ],
                    ),
                    softWrap: false,
                  ),
                ),
              ),
            );
            first = false;
          }
          return blockGap(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        if (selectionSource != null && view.rows.isNotEmpty) {
          children.add(
            Under(
              first: first,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text.fromSelectionSource(
                  selectionChild(selectionSource!, 'output'),
                  style: resultStyle,
                ),
              ),
            ),
          );
          first = false;
        } else {
          for (final row in view.rows) {
            children.add(
              Under(
                first: first,
                child: _glyphRows([row], style: resultStyle),
              ),
            );
            first = false;
          }
        }
        if (view.hidden > 0) children.add(Folded(view.hidden));
        // The original's terminal/diff `ahead` counts text, not the review row.
        if (view.rows.isEmpty) first = true;
        for (final terminal in view.terminals) {
          if (selectionSource != null && terminal.lines.isNotEmpty) {
            children.add(
              Under(
                first: first,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Text.fromSelectionSource(
                    selectionChild(selectionSource!, ('terminal', terminal.id)),
                    style: theme.dim,
                  ),
                ),
              ),
            );
            first = false;
          } else {
            for (final line in terminal.lines) {
              final rows = wrapLines(TextSpan(line), room);
              for (final row in rows) {
                children.add(
                  Under(
                    first: first,
                    child: _glyphRows([row], style: theme.dim),
                  ),
                );
                first = false;
              }
            }
          }
          if (terminal.hidden > 0) children.add(Folded(terminal.hidden));
          final note = terminal.note;
          if (note != null) {
            children.add(
              Under(
                first: first,
                child: SelectionContainer.disabled(
                  child: Text(
                    note.text,
                    style: note.failed ? theme.error : theme.dim,
                  ),
                ),
              ),
            );
            first = false;
          }
        }
        final diffSources = selectionSource == null
            ? const <SelectionSource>[]
            : selectionChildren(selectionSource!, 'diff');
        final diffHeadlines = selectionSource == null
            ? const <SelectionSource>[]
            : selectionChildren(selectionSource!, 'diff-headline');
        for (final (i, diff) in view.diffs.indexed) {
          children.add(
            Under(
              first: first,
              child: selectionSource == null
                  ? Text(
                      diffHeadline(diff, path: shownFile(diff.path, paths)),
                      style: theme.dim,
                    )
                  : Text.fromSelectionSource(
                      diffHeadlines[i],
                      style: theme.dim,
                    ),
            ),
          );
          first = false;
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: selectionSource == null
                  ? Diff.fromView(
                      diff.view,
                      title: diff.path,
                      showTitle: false,
                      wrap: DiffWrap.wrapAnsi,
                      codeInsetRight: 2,
                    )
                  : Diff.fromSelectionSource(diffSources[i]),
            ),
          );
        }
        return blockGap(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }
}

Widget _glyphRows(List<List<Glyph>> rows, {Style? style}) => Text.rich(
  TextSpan(
    '',
    children: [
      for (final (i, row) in rows.indexed) ...[
        if (i > 0) const TextSpan('\n'),
        if (row.isEmpty) const TextSpan(' '),
        for (final glyph in row) TextSpan(glyph.text, style: glyph.style),
      ],
    ],
  ),
  style: style,
  softWrap: false,
);

/// A message's `←` or `→` in the gutter, in its tone: in the other
/// agent's colour or as the text is, dim, or in the error colour.
class Arrow extends StatelessWidget {
  /// [glyph] drawn in [tone], a plain one in [colour].
  const Arrow(this.glyph, this.tone, {super.key, this.colour});

  /// `←` for a message that came in, `→` for one sent.
  final String glyph;

  /// How it is drawn.
  final ArrowTone tone;

  /// The other agent's colour, for an arrow neither dim nor failed; none
  /// draws it as the text is.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Gutter(
      glyph,
      style: switch (tone) {
        ArrowTone.plain => colour == null ? null : Style(fg: colour),
        ArrowTone.dim => theme.dim,
        ArrowTone.failed => theme.error,
      },
    );
  }
}

/// A message's text under its arrow, `←` or `→` alike, so the two never
/// drift apart: as Markdown, whole, never folded or cut, dim, or in the
/// error colour when it [failed]; then [ending], why a send failed, in the
/// error colour.
class MessageBody extends StatelessWidget {
  /// [text] under `⎿`, then [ending].
  const MessageBody(
    this.text, {
    super.key,
    this.failed = false,
    this.ending,
    this.source,
  });

  /// The message, as markdown.
  final String text;

  /// A failed report's, drawn in the error colour.
  final bool failed;

  /// Why a send failed, drawn after it.
  final String? ending;

  /// The body's own selection source; none draws it from [text].
  final SelectionSource? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = this.source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Under(
          first: true,
          child: DefaultTextStyle(
            style: failed ? theme.error : theme.dim,
            child: source == null
                ? Markdown.fromSelectionSource(
                    messageSource(text, id: 'message', revision: text),
                  )
                : Markdown.fromSelectionSource(source),
          ),
        ),
        if (ending case final ending?)
          Under(
            first: false,
            child: SelectionContainer.disabled(
              child: Text(ending, style: theme.error),
            ),
          ),
      ],
    );
  }
}

/// The tool's status marker, pulsing between accent and dim while running.
class ToolMarker extends StatefulWidget {
  /// A marker for one ACP status tone.
  const ToolMarker(this.tone, {super.key});

  /// The call's presentation tone.
  final Tone tone;

  @override
  State<ToolMarker> createState() => _ToolMarkerState();
}

class _ToolMarkerState extends State<ToolMarker> {
  Timer? _timer;
  var _lit = true;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ToolMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tone != widget.tone) _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (widget.tone == Tone.running) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => setState(() => _lit = !_lit),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = switch (widget.tone) {
      Tone.pending => theme.dim,
      Tone.running => _lit ? theme.accent : theme.dim,
      Tone.done => theme.success,
      Tone.failed => theme.error,
    };
    return Gutter('⏺', style: style);
  }
}
