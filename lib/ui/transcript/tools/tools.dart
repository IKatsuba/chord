import 'dart:convert';

import 'package:chord_tui/chord_tui.dart' hide Terminal;

import '../../../session/transcript/types.dart';
import '../../../acp/schema.dart' as acp;
import 'diff.dart';
import '../../../session/transcript/chord.dart'
    show chordCallOf, chordToolNamed;
import 'chord.dart';
import 'terminal.dart';
import '../message.dart' show wrapLines;

// M1 omits settings changes.
/// The one-line label for a structured Guardian review in progress.
const guardianReviewing = 'Guardian reviewing…';

/// How a Guardian call is presented from its structured status.
enum GuardianView {
  /// An approved review leaves no block.
  hidden,

  /// An in-progress review occupies one line.
  reviewing,

  /// Any other status keeps the full block.
  block,
}

/// Selects presentation from the structured status alone.
GuardianView guardianView(ToolCall call) => switch (call.guardian) {
  'approved' => GuardianView.hidden,
  'inProgress' => GuardianView.reviewing,
  _ => GuardianView.block,
};

/// The name, argument and dim annotations of a tool headline.
final class Headline {
  /// A tool name with optional argument and annotations.
  const Headline(this.name, {this.arg, this.tag, this.note, this.sent = false});

  /// The bold tool name.
  final String name;

  /// The complete argument, including real newlines.
  final String? arg;

  /// A dim tag immediately after the name.
  final String? tag;

  /// A dim note after the argument.
  final String? note;

  /// A message the session sent, [name] its recipient: drawn `→ to @name`,
  /// as the `←` it arrives as, not as a call.
  final bool sent;
}

const _kindNames = {
  'read': 'Read',
  'edit': 'Update',
  'delete': 'Delete',
  'move': 'Move',
  'search': 'Search',
  'execute': 'Bash',
  'think': 'Think',
  'fetch': 'Fetch',
  'switch_mode': 'Mode',
  'other': 'Tool',
};
final _codeSpan = RegExp(r'^`([^`]+)`$');
final _verbFirst = RegExp(r'^([A-Z][A-Za-z]*) (.+)$', dotAll: true);
final _mcpTitle = RegExp(r'^mcp__(.+?)__(.+)$', dotAll: true);

/// Names a filed MCP call before falling back to its title; one chord
/// served by its verb, and one to chord's own server, by the name the
/// session gave it, [chordServer], as chord's own call even before chord
/// has tied it to the request it served.
Headline headline(ToolCall call, {String? chordServer}) {
  // A plan put to the person reads as one, whatever its agent titled the
  // call: `Plan(<name>)`, cursor's name when it gave one.
  if (call.plan case final plan?) {
    return Headline('Plan', arg: plan.wait.name);
  }
  if (call.chord case final chord?) return chordHeadline(chord);
  final mcp = call.mcp;
  if (mcp?.server != null) {
    return mcpHeadline(mcp!.server!, mcp.tool, mcp.input, chordServer);
  }
  final match = _mcpTitle.firstMatch(call.title?.trim() ?? '');
  return match == null
      ? titleHeadline(call)
      : mcpHeadline(match[1]!, match[2]!, call.rawInput, chordServer);
}

final _askingWord = RegExp(r'^Asking\s+');

/// Reads a verb-first title or names its argument by the ACP kind.
Headline titleHeadline(ToolCall call) {
  final title = call.title?.trim() ?? '';
  final name = _kindNames[call.kind] ?? 'Tool';
  // A call whose questions chord's box answered asks: claude titles a lone
  // question by the question itself, whose first word is no tool's name.
  if (call.asked && title.isNotEmpty) {
    return Headline('Asking', arg: title.replaceFirst(_askingWord, ''));
  }
  if (title.isEmpty) return Headline(name);
  final code = _codeSpan.firstMatch(title);
  if (code != null) return Headline(name, arg: code[1]);
  final verb = _verbFirst.firstMatch(title);
  if (verb != null) {
    final arg = verb[2]!;
    return Headline(verb[1]!, arg: _codeSpan.firstMatch(arg)?[1] ?? arg);
  }
  return RegExp(r'^[A-Z]\S*$').hasMatch(title)
      ? Headline(title)
      : Headline(name, arg: title);
}

/// Names the MCP server and tool with compact JSON arguments; one to
/// chord's own server, [chordServer], as chord's own call.
Headline mcpHeadline(
  String server,
  String tool,
  Object? input, [
  String? chordServer,
]) {
  final named = chordToolNamed(tool);
  if (server == chordServer && named != null) {
    return chordHeadline(
      ChordCall(
        tool: named,
        input: input is Map<String, Object?> ? input : const {},
      ),
    );
  }
  return Headline('$server - $tool', tag: ' (MCP)', arg: mcpArguments(input));
}

/// Renders MCP arguments as escaped key/value JSON, or none when empty.
String? mcpArguments(Object? input) {
  if (input == null) return null;
  final text = input is Map<String, Object?>
      ? input.entries
            .map((entry) {
              final key = jsonEncode(entry.key);
              return '${key.substring(1, key.length - 1)}: ${jsonEncode(entry.value)}';
            })
            .join(', ')
      : jsonEncode(input);
  if (text.isEmpty) return null;
  return text.replaceAllMapped(
    RegExp(r'[\u007f-\u009f]'),
    (match) =>
        '\\u${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
  );
}

/// Keeps only the first argument line for a one-row headline.
Headline firstLine(Headline line) => line.arg == null
    ? line
    : Headline(
        line.name,
        arg: line.arg!.split('\n').first.trimRight(),
        tag: line.tag,
        note: line.note,
        sent: line.sent,
      );

/// Original headline styling before width-dependent wrapping: the name
/// bold, a sent message's `@name` in its recipient's [colour], its `to `
/// and the notes dim.
TextSpan headlineSpan(Headline line, {Color? colour}) {
  // Escapes, as the original's, so a style the agent opened in the
  // argument reads on through the rest.
  final named = line.sent && colour != null;
  return parseAnsi(
    '${line.sent ? '\x1b[2mto \x1b[22m' : ''}'
    '\x1b[1m${named ? '\x1b[${colour.fgCode}m' : ''}'
    '${line.sent ? '@${line.name}' : line.name}'
    '${named ? '\x1b[39m' : ''}\x1b[22m'
    '${line.tag == null ? '' : '\x1b[2m${line.tag}\x1b[22m'}'
    '${line.arg == null ? '' : '(${line.arg})'}'
    '${line.note == null ? '' : '\x1b[2m${line.note}\x1b[22m'}',
  );
}

/// Styled glyphs, each line wrapped as the original's `wrapLine`; a sent
/// message's `@name` in [colour].
List<List<Glyph>> headlineRows(Headline line, int width, {Color? colour}) =>
    wrapLines(headlineSpan(line, colour: colour), width);

/// Whether a call no longer belongs to a running turn.
bool turnEnded(TurnState turn, String turnId) => switch (turn) {
  Idle() => true,
  AwaitingPermission(between: true) => true,
  Working(turnId: final id) ||
  AwaitingPermission(turnId: final id) ||
  Cancelling(turnId: final id) => id != turnId,
};

/// The status tone of the marker before a tool call.
enum Tone {
  /// Waiting for the agent or person.
  pending,

  /// The tool is in progress.
  running,

  /// The tool completed successfully.
  done,

  /// The tool failed.
  failed,
}

/// Whether any permission waiting on this turn names the call.
bool asksFor(TurnState turn, String callId) =>
    turn is AwaitingPermission &&
    turn.permissions.any((wait) => wait.toolCallId == callId);

/// Picks the ACP status tone, with a permission wait taking precedence and
/// chord's refusal over both.
Tone toneOf(ToolCall call, {bool asked = false}) => call.chord?.error != null
    ? Tone.failed
    : asked
    ? Tone.pending
    : switch (call.status) {
        'in_progress' => Tone.running,
        'completed' => Tone.done,
        'failed' => Tone.failed,
        _ => Tone.pending,
      };

/// Output lines a Read keeps before its hidden count.
const summaryLines = 3;

/// A tool's text, terminals and edits beneath its headline.
final class Summary {
  /// Visible lines and hidden count, followed by terminal output and edits.
  const Summary(this.lines, this.hidden, this.terminals, this.diffs, this.rows);

  /// Wrapped visible text, or original text without a width.
  final List<String> lines;

  /// Source text lines folded away from a Read.
  final int hidden;

  /// Nonempty terminal tails or full output.
  final List<TerminalView> terminals;

  /// Full edits; ctrl+o does not fold normal tool diffs.
  final List<ToolDiffView> diffs;

  /// Styled wrapped glyphs, retaining ANSI color across output rows.
  final List<List<Glyph>> rows;
}

/// A sent message's body: the text it sent, then what said it failed.
final class SentBody {
  /// [text] as sent, and the [ending] said after it, if any.
  const SentBody(this.text, {this.ending});

  /// What was sent, as markdown.
  final String text;

  /// chord's refusal, `Failed`, or that it was cut off, drawn after it.
  final String? ending;
}

/// A `send_message` call's text, drawn under its `→` as a received
/// message's is, in every state; a refused or failed one keeps it and says
/// why after it; one cut off before it reached chord, read from the call as
/// the agent sent it to [chordServer], says it was not delivered. None for
/// any other call or an empty text, whose own lines say it.
SentBody? sentBody(ToolCall call, {String? chordServer}) {
  final cut = cutChord(call, chordServer);
  final chord = call.chord ?? cut;
  final text = chord == null ? null : sentText(chord);
  if (text == null) return null;
  if (cut != null) return SentBody(text, ending: cutLine(cut.tool));
  return toneOf(call) == Tone.failed
      ? SentBody(text, ending: call.chord?.error ?? 'Failed')
      : SentBody(text);
}

/// The call of chord's tools [call] asked for when the agent cut it off
/// before it reached chord: nothing served for it, so it did nothing.
ChordCall? cutChord(ToolCall call, String? chordServer) =>
    call.cut && call.chord == null ? chordCallOf(call, chordServer) : null;

/// Selects the original's output lines, failure wording, terminals and
/// edits; chord's own calls say what was sent or answered, not the
/// answer's JSON, and one cut off what it asked for and that it did
/// nothing.
Summary summary(
  ToolCall call,
  bool expanded, {
  bool ended = false,
  bool asked = false,
  int? width,
  String? chordServer,
}) {
  // A box of questions' record under the call says what was asked and
  // answered; ctrl+o shows the call's own lines too.
  if (call.asked && !expanded) return const Summary([], 0, [], [], []);
  final cut = cutChord(call, chordServer);
  final chord = call.chord;
  final lines = <String>[
    if (cut != null) ...[
      ...chordLines(cut, expanded: expanded),
      cutLine(cut.tool),
    ],
    if (cut == null && chord != null) ...chordLines(chord, expanded: expanded),
  ];
  final own = cut != null || chord != null;
  final diffs = <ToolDiffView>[];
  for (final item in call.content ?? const <acp.ToolCallContent>[]) {
    if (item.type == 'content') {
      if (own) continue;
      final block = item.content!;
      if (block.type == 'text') {
        final text = block.text!.trimRight();
        if (text.isNotEmpty) lines.addAll(text.split(RegExp(r'\r?\n')));
      } else {
        lines.add('[${block.type}]');
      }
    } else if (item.type == 'diff') {
      final diff = item.diff!;
      diffs.add(diffView(diff.path, diff.oldText, diff.newText));
    }
  }
  final terminals = (call.terminals ?? const <Terminal>[])
      .map((terminal) => terminalView(terminal, expanded))
      .where((view) => !isEmpty(view))
      .toList();
  final tone = toneOf(call, asked: asked);
  final told = terminals.any((view) => view.note?.failed ?? false);
  final fallback =
      lines.isEmpty &&
      (tone == Tone.failed ? !told : terminals.isEmpty && diffs.isEmpty);
  if (fallback) {
    switch (tone) {
      case Tone.pending:
      case Tone.running:
        if (!ended && !(asked && call.review != null)) {
          lines.add(tone == Tone.pending ? 'Waiting…' : 'Running…');
        }
      case Tone.failed:
        lines.add('Failed');
      case Tone.done:
        break;
    }
  } else if (tone == Tone.failed && lines.isNotEmpty && !own) {
    // chord's refusal is its own sentence, said as it is; another's error
    // is marked as one.
    lines[0] = 'Error: ${lines[0]}';
  }
  // A Resources report is never folded: each line is one provider's fact.
  final folds =
      (cut ?? chord)?.tool != ChordTool.getBudgets &&
      !expanded &&
      call.kind == 'read' &&
      lines.length > summaryLines;
  final kept = [
    if (!fallback && asked && tone == Tone.pending && call.review == null)
      'Waiting…',
    ...(folds ? lines.sublist(0, summaryLines) : lines),
  ];
  final rows = [
    for (final line in kept)
      ...(width == null
          ? TextLayout.compute(parseAnsi(line)).lines
          : wrapLines(parseAnsi(line), width)),
  ];
  return Summary(
    width == null
        ? kept
        : [for (final row in rows) row.map((g) => g.text).join()],
    folds ? lines.length - summaryLines : 0,
    terminals,
    diffs,
    rows,
  );
}

/// The original nonselectable count of source lines hidden by details folding.
/// [key] is the one that expands, none when nothing is bound to it.
String foldedLine(int hidden, [String? key = 'ctrl+o']) =>
    '… +$hidden ${hidden == 1 ? 'line' : 'lines'}${key == null ? '' : ' ($key to expand)'}';
