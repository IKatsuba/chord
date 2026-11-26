/// Takes the README's screenshots from chord itself, as the original's
/// `scripts/dev/screenshots.ts` takes them:
///
///     dart run tool/screenshots.dart [name…]
///
/// rewrites docs/images/*.png, or those named. Each shot runs chord from
/// source in a tmux session of its own, [columns] × [rows], built as the dev
/// runner builds it on the fake ([fixtureDefine] and [fakeRuntimesDefine]),
/// so every runtime it starts, children, teams and forks included, is the
/// Dart fake under `test/fixtures/fake_agent/`, and a start with no
/// `--agent-command` is refused. It types what a person would, waits for
/// the state the shot shows, and reads the screen back with its colours
/// (`capture-pane -e`). The frame is then drawn in a Chorded terminal pane
/// in Chrome (package:puppeteer, the system's Chrome, never a download)
/// as the original's ansi_up draws it, read with package:ansi_escape_codes,
/// and captured at twice its size.
///
/// chord runs in a home of its own under a fixed neutral directory, removed
/// after, so nothing of the person's settings, records or teams reaches a
/// shot, and no path of their machine shows. There the settings name the
/// fake `claude` and `codex`, on Claude Opus 5.5 and GPT-6.1 Sol, which its
/// `--tokens-only` offers; the team the shots run is `screenshots_team.md`
/// beside this tool, whose lead opens all three of its members; `/team new`
/// proposes the same team in short from `screenshots_proposal.md`; and the
/// scenario each shot plays comes from `CHORD_FAKE_SCENARIO`, so the prompt
/// typed can be a person's words.
///
/// Beside each picture but the logos it writes the shot as two recordings,
/// `docs/images/<name>.120x36.rec.json` and `<name>.80x20.rec.json`
/// (`tool/recordings.dart`): the shot played again at each size, a frame
/// after every step and every 100 ms while it waits, for the site's
/// Playback.
///
/// `logo` takes the README's two logos the same way: the title page in each
/// theme, kept to its art, with no window and a transparent background.
///
/// Chrome is the system's: `CHROME` names its binary where it is not at
/// macOS's usual place.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart'
    show Color, Color16, Color256, ColorRgb, Parser, Text;
import 'package:characters/characters.dart';
import 'package:chord/ui/app/start_layout.dart' show tagline;
import 'package:chord_tui/chord_tui.dart' show graphemeWidth;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart' as browsers;

import '../test/fixtures/fake.dart';
import 'dev.dart' show fakeRuntimesDefine, fixtureDefine, shellWord;
import 'recordings.dart';

/// What a shot does to the window before it is taken.
sealed class Step {
  const Step();
}

/// Text typed as it is.
final class TypeText extends Step {
  /// Types [text].
  const TypeText(this.text);

  /// What is typed.
  final String text;
}

/// tmux key names sent.
final class SendKeys extends Step {
  /// Sends [keys].
  const SendKeys(this.keys);

  /// The keys, as tmux names them.
  final List<String> keys;
}

/// A wait until the screen shows [text].
final class UntilShown extends Step {
  /// Waits for [text].
  const UntilShown(this.text);

  /// What the screen comes to show.
  final String text;
}

/// A wait of [ms] milliseconds.
final class Pause extends Step {
  /// Waits [ms].
  const Pause(this.ms);

  /// How long, in milliseconds.
  final int ms;
}

/// chord gone from its pane, as a `/exit` leaves it.
final class Exited extends Step {
  /// Waits for chord to leave.
  const Exited();
}

/// The sessions recorded so far aged, the latest first, by [hours].
final class Aged extends Step {
  /// Ages the records by [hours].
  const Aged(this.hours);

  /// Hours back, the latest session's first.
  final List<int> hours;
}

/// chord started again in the same pane and home, with [args].
final class Respawn extends Step {
  /// Starts chord again with [args].
  const Respawn(this.args);

  /// chord's arguments.
  final List<String> args;
}

/// One picture.
final class Shot {
  /// A shot named [name].
  const Shot({
    required this.name,
    required this.scenario,
    this.args = const ['claude'],
    this.first = 'for shortcuts',
    this.env = const [],
    this.theme = 'dark',
    this.group,
    this.steps = const [],
    this.team = true,
  });

  /// The file under docs/images, without `.png`.
  final String name;

  /// The fake agent's scenario for every prompt that names none.
  final String scenario;

  /// chord's arguments; `claude` by default, as an unnamed start asks first.
  final List<String> args;

  /// What chord's first screen shows; the prompt's hint by default.
  final String first;

  /// More of chord's environment, as `NAME=value`.
  final List<String> env;

  /// The settings' theme.
  final String theme;

  /// Which group of shots a name on the command line also takes it by.
  final String? group;

  /// What is done before the shot is taken.
  final List<Step> steps;

  /// Whether the project has the `bugfix` team saved.
  final bool team;
}

/// A prompt typed and sent.
List<Step> prompt(String text) => [
  TypeText(text),
  const SendKeys(['Enter']),
];

/// The README's shots, in the original's order.
final List<Shot> shots = [
  // Nothing picked, so no agent starts. The system's own PATH leaves out
  // every own CLI on the machine that takes it, so the list is the same on
  // any.
  const Shot(
    name: 'start',
    scenario: 'text',
    args: [],
    first: 'Select agent',
    env: ['PATH=/usr/bin:/bin'],
  ),
  Shot(
    name: 'team',
    scenario: 'team',
    steps: [
      ...prompt('Hand issue 214 to the bugfix team'),
      const UntilShown('● permission'),
    ],
  ),
  Shot(
    name: 'proposal',
    scenario: 'text',
    team: false,
    steps: [
      ...prompt(
        '/team new fix bugs the way we do by hand: a failing test first, then '
        'the fix on codex, then a review',
      ),
      const UntilShown('Save team bugfix?'),
    ],
  ),
  Shot(
    name: 'edit',
    scenario: 'edit',
    steps: [
      ...prompt('Greet people by name with a template literal'),
      const UntilShown('Edited.'),
    ],
  ),
  Shot(
    name: 'permission',
    scenario: 'permission',
    steps: [
      ...prompt('Write the release notes into notes.txt'),
      const UntilShown('Do you want to proceed?'),
    ],
  ),
  Shot(
    name: 'subagents',
    scenario: 'subagent',
    steps: [
      ...prompt(
        'Find where session updates are routed and where tool calls are '
        'drawn, in parallel',
      ),
      const UntilShown('Running 2 agents'),
      const Pause(1500),
    ],
  ),
  // The agents beside the main one, under the prompt: `docs` waits on a
  // permission, which the status line names with the key that goes there.
  // parser is told nothing, so main is idle once its first turn ends.
  Shot(
    name: 'agents',
    scenario: 'agentsquiet',
    steps: [
      ...prompt('Fix the parser, and have the README say what changed'),
      const UntilShown('docs needs your permission'),
      const UntilShown('Waiting on parser.'),
      const Pause(4000),
    ],
  ),
  Shot(
    name: 'resume',
    scenario: 'text',
    steps: [
      for (final text in [
        'Explain src/ui/state.ts',
        'Add a --json flag to the agents command',
        "Tidy the README's install section",
      ]) ...[
        ...prompt(text),
        const Pause(3000),
        ...prompt('/clear'),
        const Pause(3000),
      ],
      ...prompt('/exit'),
      const Exited(),
      // Taken one after another, they would all say "just now".
      const Aged([2, 26, 75]),
      const Respawn(['--resume']),
      const UntilShown('Resume a session'),
    ],
  ),
  // A reply's code blocks, each with its [copy], and [run] on a command.
  Shot(
    name: 'codeblocks',
    scenario: 'markdown',
    steps: [
      ...prompt('Walk me through landing a change'),
      const UntilShown(r'built $bin'),
      const UntilShown('context used'),
    ],
  ),
  // The conversation so far goes on in a fork, picked at once, its row in
  // the agents list beside main.
  Shot(
    name: 'fork',
    scenario: 'edit',
    steps: [
      ...prompt('Greet people by name with a template literal'),
      const UntilShown('context used'),
      ...prompt('/fork arrow-function'),
      const UntilShown('forked from main'),
    ],
  ),
];

/// The title page's art, for the README: its own colours on no background.
final List<Shot> logos = [
  for (final theme in ['dark', 'light'])
    Shot(
      name: 'logo-$theme',
      scenario: 'text',
      args: const [],
      first: tagline,
      theme: theme,
      group: 'logo',
    ),
];

/// The shots [names] take, in order: all with none; else each named, or in
/// a named group.
List<Shot> chosen(List<String> names) => [
  for (final shot in [...shots, ...logos])
    if (names.isEmpty ||
        names.contains(shot.name) ||
        (shot.group != null && names.contains(shot.group)))
      shot,
];

/// The terminal's size; `proposal` is the tallest shot, and fits in this.
const columns = 120;

/// The terminal's rows.
const rows = 37;

/// The art of the title page's `full` step.
const logoColumns = 57;

/// The art's rows.
const logoRowCount = 8;

/// The terminal's own colour behind chord.
const background = '#16171b';

/// The terminal's own colour in front of chord.
const foreground = '#e4e4e4';

/// A stretch of text in one style, as the frame's escape codes leave it.
final class Run {
  /// [text] in its colours ([fg], [bg] as red, green, blue) and attributes.
  const Run(
    this.text, {
    this.fg,
    this.bg,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
  });

  /// The text.
  final String text;

  /// The foreground, or the terminal's own.
  final List<int>? fg;

  /// The background, or the terminal's own.
  final List<int>? bg;

  /// SGR 1.
  final bool bold;

  /// SGR 2, faint.
  final bool dim;

  /// SGR 3.
  final bool italic;

  /// SGR 4.
  final bool underline;

  /// This run's style on [text].
  Run withText(String text) => Run(
    text,
    fg: fg,
    bg: bg,
    bold: bold,
    dim: dim,
    italic: italic,
    underline: underline,
  );
}

/// The red, green and blue the original's ansi_up gives a palette colour
/// [index]: its sixteen named colours, the 6×6×6 cube, then 24 greys.
List<int> paletteRgb(int index) {
  const named = [
    [0, 0, 0], [187, 0, 0], [0, 187, 0], [187, 187, 0], //
    [0, 0, 187], [187, 0, 187], [0, 187, 187], [255, 255, 255],
    [85, 85, 85], [255, 85, 85], [0, 255, 0], [255, 255, 85],
    [85, 85, 255], [255, 85, 255], [85, 255, 255], [255, 255, 255],
  ];
  const levels = [0, 95, 135, 175, 215, 255];
  RangeError.checkValueInInterval(index, 0, 255, 'index');
  if (index < 16) return named[index];
  if (index < 232) {
    final cube = index - 16;
    return [levels[cube ~/ 36], levels[cube ~/ 6 % 6], levels[cube % 6]];
  }
  final grey = 8 + (index - 232) * 10;
  return [grey, grey, grey];
}

List<int>? _rgb(Color? colour) => switch (colour) {
  null => null,
  ColorRgb(:final r, :final g, :final b) => [r, g, b],
  Color16(:final color) || Color256(:final color) => paletteRgb(color.index),
};

/// The frame's rows, each as the runs package:ansi_escape_codes reads, its
/// state carried from row to row as one terminal's is.
List<List<Run>> styledRows(String frame) {
  final rows = [<Run>[]];
  for (final piece in Parser(frame).pieces) {
    if (piece.entity case Text(:final string)) {
      final state = piece.state;
      final style = Run(
        '',
        fg: _rgb(state.foregroundColor),
        bg: _rgb(state.backgroundColor),
        bold: state.isBold,
        dim: state.isDim,
        italic: state.isItalic,
        underline: state.isUnderline,
      );
      for (final (at, part) in string.split('\n').indexed) {
        if (at > 0) rows.add([]);
        if (part.isNotEmpty) rows.last.add(style.withText(part));
      }
    }
  }
  return rows;
}

/// A row's text without its styles.
String plainOf(List<Run> row) => row.map((run) => run.text).join();

/// The title page's art out of a captured frame: the rows above the
/// tagline's gap, from the art's left edge, [logoColumns] wide, with their
/// colours. So the logo cannot drift from what chord draws.
List<List<Run>> logoRows(String frame) {
  final all = styledRows(frame);
  final at = all.indexWhere((row) => plainOf(row).contains(tagline));
  if (at < logoRowCount + 1) {
    throw StateError('The frame has no title page art above its tagline.');
  }
  final art = all.sublist(at - 1 - logoRowCount, at - 1);
  final left = [
    for (final row in art)
      if (plainOf(row).indexOf(RegExp(r'\S')) case final at when at >= 0) at,
  ].reduce((a, b) => a < b ? a : b);
  return [for (final row in art) _slice(row, left, left + logoColumns)];
}

/// [row]'s runs cut to the cells from [start] to [end], as slice-ansi
/// cuts them: a character whole within them is kept, one across an edge
/// is not.
List<Run> _slice(List<Run> row, int start, int end) {
  final out = <Run>[];
  var at = 0;
  for (final run in row) {
    final kept = StringBuffer();
    for (final grapheme in run.text.characters) {
      final width = graphemeWidth(grapheme);
      if (at >= start && at + width <= end) kept.write(grapheme);
      at += width;
    }
    if (kept.isNotEmpty) {
      out.add(run.withText(kept.toString()));
    }
  }
  return out;
}

/// [text] safe in HTML, as ansi_up escapes it.
String escapeHtml(String text) => text.replaceAllMapped(
  RegExp('[&<>"\']'),
  (match) => switch (match[0]) {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
    _ => '&#x27;',
  },
);

/// A run as ansi_up's `ansi_to_html` writes it with inline styles: bold,
/// faint, italic and underline, then the colours; plain text bare.
String runHtml(Run run) {
  if (run.text.isEmpty) return '';
  final text = escapeHtml(run.text);
  final styles = [
    if (run.bold) 'font-weight:bold',
    if (run.dim) 'opacity:0.7',
    if (run.italic) 'font-style:italic',
    if (run.underline) 'text-decoration:underline',
    if (run.fg case final fg?) 'color:rgb(${fg.join(',')})',
    if (run.bg case final bg?) 'background-color:rgb(${bg.join(',')})',
  ];
  return styles.isEmpty
      ? text
      : '<span style="${styles.join(';')}">$text</span>';
}

/// Rows as HTML, the terminal's colours kept inline.
String rowsHtml(List<List<Run>> frame) => [
  for (final row in frame)
    '<div class="row">${_orSpace(row.map(runHtml).join())}</div>',
].join();

String _orSpace(String html) => html.isEmpty ? ' ' : html;

const _font = '''
  @font-face { font-family: Term; src: local('JetBrains Mono'), local('JetBrainsMono-Regular'); }
  @font-face { font-family: Term; font-weight: bold; src: local('JetBrains Mono Bold'), local('JetBrainsMono-Bold'); }
''';

/// A logo alone, nothing behind it, its cell a whole 12×24 pixels: the
/// shots' fractional cell leaves seams between the block glyphs, which show
/// on white.
String logoPage(String frame) =>
    '''
<!doctype html>
<meta charset="utf-8">
<style>
  $_font
  html, body { margin: 0; background: transparent; }
  .page {
    display: inline-block; width: ${logoColumns}ch;
    font: 20px/24px Term, Menlo, monospace; white-space: pre;
    font-variant-ligatures: none;
  }
  .row { height: 24px; }
</style>
<div class="page">${rowsHtml(logoRows(frame))}</div>''';

/// A frame in Chorded's window, on its gradient.
String page(String frame) {
  final body = rowsHtml(
    styledRows(
      frame.endsWith('\n') ? frame.substring(0, frame.length - 1) : frame,
    ),
  );
  return '''
<!doctype html>
<meta charset="utf-8">
<style>
  $_font
  html, body { margin: 0; background: transparent; }
  /* The window on a gradient, as Chorded's own pictures show it (CHD-407). */
  .page {
    padding: 64px 72px 88px; display: inline-block; position: relative;
    overflow: hidden; isolation: isolate;
    background: linear-gradient(135deg, #2b3a8c 0%, #6a4bc4 38%, #c46aa8 70%, #f2a17a 100%);
  }
  /* Chorded's window: a metal rim around a dark pane, its corners round; the
     rim lets the backdrop through a little, the pane does not. */
  .rim {
    padding: 7px; border-radius: 38px;
    background: linear-gradient(180deg, rgba(142, 144, 149, 0.55) 0%, rgba(93, 95, 100, 0.55) 45%, rgba(58, 59, 64, 0.55) 100%);
    backdrop-filter: blur(24px) saturate(1.6);
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.55),
      0 24px 48px rgba(0, 0, 0, 0.28),
      0 8px 16px rgba(0, 0, 0, 0.18);
  }
  .window {
    background: $background;
    border-radius: 31px;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.6);
    overflow: hidden;
  }
  .bar {
    height: 50px; display: flex; align-items: center; gap: 14px;
    padding: 0 22px 0 24px;
    font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;
  }
  .bar svg { flex: none; }
  .lights { display: flex; gap: 8px; flex: none; margin-right: 4px; }
  .lights i { width: 12px; height: 12px; border-radius: 50%; box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.25); }
  .title { font-size: 15px; font-weight: 500; color: #ececec; }
  .screen {
    padding: 2px 22px 22px; color: $foreground;
    /* The whole window: a capture ends each row at its last cell drawn, and a
       centred page has no row that reaches the edge. */
    width: ${columns}ch;
    font: 13.5px/1.3 Term, Menlo, monospace; white-space: pre;
    font-variant-ligatures: none;
  }
  .row { height: 1.3em; }
</style>
<div class="page"><div class="rim"><div class="window">
  <div class="bar">
    <span class="lights"><i style="background: #ff5f57"></i><i style="background: #febc2e"></i><i style="background: #28c840"></i></span>
    <svg width="22" height="18" viewBox="0 0 22 18" fill="none" stroke="#c9cacd" stroke-width="1.5">
      <rect x="1" y="1" width="20" height="16" rx="3.5"/><line x1="8" y1="1" x2="8" y2="17"/>
      <line x1="3.5" y1="5" x2="5.5" y2="5" stroke-linecap="round"/><line x1="3.5" y1="8" x2="5.5" y2="8" stroke-linecap="round"/>
    </svg>
    <div class="title">Chorded</div>
  </div>
  <div class="screen">$body</div>
</div></div></div>''';
}

/// The records in [dir] that hold a prompt, the latest first, each aged by
/// its of [hours]: every time it says goes back by as much.
void age(String dir, List<int> hours) {
  final sessions = [
    for (final file in Directory(dir).listSync().whereType<File>())
      (
        path: file.path,
        lines: [
          for (final line in file.readAsLinesSync())
            if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
        ],
      ),
  ].where((record) => record.lines.any((line) => line['type'] == 'prompt'));
  int latest(List<Map<String, Object?>> lines) => lines
      .map((line) => (line['at'] as num?)?.toInt() ?? 0)
      .fold(0, (a, b) => a > b ? a : b);
  final sorted = sessions.toList()
    ..sort((a, b) => latest(b.lines) - latest(a.lines));
  for (final (index, record) in sorted.indexed) {
    final back = (index < hours.length ? hours[index] : 0) * 3600000;
    File(record.path).writeAsStringSync(
      '${[
        for (final line in record.lines) jsonEncode(switch (line['at']) {
            final num at => {...line, 'at': at.toInt() - back},
            _ => line,
          }),
      ].join('\n')}\n',
    );
  }
}

/// Where a shot's world lives: a fixed, neutral place, never the system's
/// per-user temp directory, so no path of a person's machine can reach a
/// shot, whatever chord shows of its directory.
String shotDir(String name) => '/tmp/chord-shot.$name';

/// The fake agent's command for every shot: its lead opens every member,
/// reviewer too, and a proposal is the same team in short, so the whole of
/// it fits the frame.
List<String> shotFake(String portDir) => fakeAgentCommand(null, [
  '--tokens-only',
  '--lead-opens',
  'tester,coder,reviewer',
  '--propose-team',
  p.join(portDir, 'tool', 'screenshots_proposal.md'),
]);

/// The argv that runs chord for a shot from source under [portDir], built
/// as the dev runner builds it on the fake, on [fake] when the shot names
/// an agent, with [args] and the project [project].
List<String> shotArgv({
  required String dart,
  required String portDir,
  required List<String> args,
  required List<String> fake,
  required String project,
}) => checkedShotArgv([
  dart,
  'run',
  fixtureDefine,
  fakeRuntimesDefine,
  p.join(portDir, 'bin', 'chord.dart'),
  ...args,
  if (args.isNotEmpty) ...['--agent-command', fake.map(shellWord).join(' ')],
  '-C',
  project,
]);

/// [argv] when it runs chord built to start only the fake; a
/// [StateError] otherwise, so no shot can reach a real agent.
List<String> checkedShotArgv(List<String> argv) {
  final at = argv.indexWhere((word) => word.endsWith('chord.dart'));
  final defines = at < 0 ? const <String>[] : argv.sublist(0, at);
  final chord = at < 0 ? const <String>[] : argv.sublist(at + 1);
  if (!defines.contains(fakeRuntimesDefine) ||
      !defines.contains(fixtureDefine)) {
    throw StateError(
      'A shot runs only chord built with $fakeRuntimesDefine and '
      '$fixtureDefine: ${argv.join(' ')}',
    );
  }
  // Without the fake's command, chord is given its directory alone: the
  // start page, where nothing starts.
  if (!chord.contains('--agent-command') &&
      !(chord.length == 2 && chord.first == '-C')) {
    throw StateError(
      'A shot that starts an agent starts it with --agent-command: '
      '${argv.join(' ')}',
    );
  }
  return argv;
}

/// The settings a shot's chord reads, in [theme].
Map<String, Object?> shotSettings(String theme) => {
  'theme': theme,
  'agent': 'claude',
  'agents': {
    'claude': {'model': 'claude-opus-5-5'},
    'codex': {'model': 'gpt-6.1-sol'},
  },
};

/// The environment a shot's chord runs in, under [dir] with its [home].
List<String> shotEnv(Shot shot, String dir, String home) => [
  'HOME=$home',
  'XDG_CONFIG_HOME=${p.join(home, '.config')}',
  'XDG_STATE_HOME=${p.join(dir, 'state')}',
  'COLORTERM=truecolor',
  'CHORD_FAKE_SCENARIO=${shot.scenario}',
  'CHORD_FAKE_STEP_MS=40',
  // It offers `session/fork`, as the fork shot's `/fork` asks, and the
  // `auto` mode the team's coder is on.
  'CHORD_FAKE_FORK=1',
  'CHORD_FAKE_AUTO_MODE=1',
  // The children a scenario opens run on codex, a name the settings give,
  // on its model, opened on a person's words.
  'CHORD_FAKE_CHILD_RUNTIME=codex',
  'CHORD_FAKE_CHILD_MODEL=gpt-6.1-sol',
  // A fork stays on its source's model, main's in the fork shot.
  'CHORD_FAKE_FORK_MODEL=claude-opus-5-5',
  'CHORD_FAKE_SAID=${jsonEncode({'agentchild': 'Run the parser tests and fix what fails', 'permission': 'Say in the README what changed'})}',
  ...shot.env,
];

final _socket = 'chord-screenshots-$pid';

String _tmux(List<String> argv) {
  final run = Process.runSync('tmux', [
    '-L',
    _socket,
    '-f',
    '/dev/null',
    ...argv,
  ]);
  if (run.exitCode != 0) {
    throw StateError('tmux ${argv.first}: ${run.stderr}');
  }
  return run.stdout as String;
}

String _screen() => _tmux(['capture-pane', '-p', '-t', 'shot']);

Future<void> _waitFor(
  bool Function() done,
  String what, {
  void Function()? each,
}) async {
  // chord from source compiles first, which a cold cache takes a while for.
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('$what\n${_screen()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    each?.call();
  }
}

/// How a recording labels a key tmux names, in chord_tui's spelling:
/// `Enter` is `enter`, `C-o` is `ctrl+o`, `BTab` is `shift+tab`.
String keyLabel(String tmux) {
  const named = {
    'Enter': 'enter',
    'Escape': 'escape',
    'Tab': 'tab',
    'BTab': 'shift+tab',
    'BSpace': 'backspace',
    'Space': 'space',
    'Up': 'up',
    'Down': 'down',
    'Left': 'left',
    'Right': 'right',
    'PageUp': 'pageup',
    'PageDown': 'pagedown',
    'Home': 'home',
    'End': 'end',
  };
  if (named[tmux] case final name?) return name;
  for (final (prefix, modifier) in const [
    ('C-', 'ctrl+'),
    ('M-', 'alt+'),
    ('S-', 'shift+'),
  ]) {
    if (tmux.startsWith(prefix) && tmux.length > prefix.length) {
      return '$modifier${keyLabel(tmux.substring(prefix.length))}';
    }
  }
  return tmux.toLowerCase();
}

/// What a recording calls [step]; null for waits, which add frames only.
String? stepLabel(Step step) => switch (step) {
  TypeText(:final text) => cutLabel('typed $text'),
  SendKeys(:final keys) => keys.map(keyLabel).join(' '),
  Respawn() => 'started again',
  Exited() => 'left',
  UntilShown() || Pause() || Aged() => null,
};

/// The shot's screen as chord drew it, with its colours, in a [cols] by
/// [rows] pane; with [recording], every frame it went through on the way.
Future<String> capture(
  Shot shot,
  String portDir, {
  int cols = columns,
  int rows = rows,
  RecordingWriter? recording,
}) async {
  final dir = shotDir(shot.name);
  if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
  final home = p.join(dir, 'home');
  final project = p.join(home, 'src', 'app');
  Directory(p.join(home, '.config', 'chord')).createSync(recursive: true);
  Directory(p.join(project, '.chord', 'teams')).createSync(recursive: true);
  try {
    File(
      p.join(home, '.config', 'chord', 'settings.json'),
    ).writeAsStringSync(jsonEncode(shotSettings(shot.theme)));
    if (shot.team) {
      File(p.join(project, '.chord', 'teams', 'bugfix.md')).writeAsStringSync(
        File(p.join(portDir, 'tool', 'screenshots_team.md')).readAsStringSync(),
      );
    }
    final fake = shotFake(portDir);
    String chord(List<String> args) => [
      'exec',
      'env',
      ...shotEnv(shot, dir, home),
      ...shotArgv(
        dart: dartExecutable(),
        portDir: portDir,
        args: args,
        fake: fake,
        project: project,
      ),
    ].map(shellWord).join(' ');

    _tmux([
      'new-session',
      '-d',
      '-s',
      'shot',
      '-x',
      '$cols',
      '-y',
      '$rows',
      '-c',
      portDir,
      chord(shot.args),
    ]);
    _tmux(['set', '-g', 'default-terminal', 'tmux-256color']);
    _tmux(['set', '-as', 'terminal-overrides', ',*:RGB']);
    // Its pane outlives a chord that leaves, for a respawn to start in.
    _tmux(['set', '-w', '-t', 'shot', 'remain-on-exit', 'on']);
    await _waitFor(
      () => _screen().contains(shot.first),
      '${shot.name}: "${shot.first}" never came.',
    );

    // The recording's clock starts at chord's first screen, after the
    // build from source a person would not watch.
    final clock = Stopwatch()..start();
    String colours() => _tmux(['capture-pane', '-p', '-e', '-t', 'shot']);
    void sample() => recording?.add(clock.elapsed, colours());
    Future<void> idle(Duration time) async {
      final end = clock.elapsed + time;
      while (clock.elapsed < end) {
        final left = end - clock.elapsed;
        await Future<void>.delayed(
          left < const Duration(milliseconds: 100)
              ? left
              : const Duration(milliseconds: 100),
        );
        sample();
      }
    }

    sample();
    for (final step in shot.steps) {
      if (stepLabel(step) case final label?) recording?.step(label);
      switch (step) {
        case TypeText(:final text):
          _tmux(['send-keys', '-t', 'shot', '-l', text]);
          await idle(const Duration(milliseconds: 300));
        case SendKeys(:final keys):
          _tmux(['send-keys', '-t', 'shot', ...keys]);
          await idle(const Duration(milliseconds: 300));
        case UntilShown(:final text):
          await _waitFor(
            () => _screen().contains(text),
            '${shot.name}: "$text" never came.',
            each: sample,
          );
        case Exited():
          await _waitFor(
            () =>
                _tmux(['display', '-p', '-t', 'shot', '#{pane_dead}']).trim() ==
                '1',
            '${shot.name}: chord never left.',
            each: sample,
          );
        case Aged(:final hours):
          age(p.join(dir, 'state', 'chord', 'records'), hours);
        case Respawn(:final args):
          _tmux(['respawn-pane', '-k', '-t', 'shot', chord(args)]);
        case Pause(:final ms):
          await idle(Duration(milliseconds: ms));
      }
    }

    // What the last keys set off drawn, and the spinner's frame with it.
    await idle(const Duration(milliseconds: 400));
    return colours();
  } finally {
    Process.runSync('tmux', ['-L', _socket, 'kill-server']);
    if (Directory(dir).existsSync()) Directory(dir).deleteSync(recursive: true);
  }
}

/// The system's Chrome: `CHROME`, else macOS's usual place.
String chromePath() =>
    Platform.environment['CHROME'] ??
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

Future<void> main(List<String> names) async {
  final portDir = portPackageDir();
  if (fakeAgent.reason case final reason?) {
    stderr.writeln('screenshots: the fake agent cannot run: $reason');
    exit(1);
  }
  final chrome = chromePath();
  if (!File(chrome).existsSync()) {
    stderr.writeln('screenshots: no Chrome at $chrome; set CHROME.');
    exit(1);
  }
  final images = Directory(p.join(portDir, 'docs', 'images'))
    ..createSync(recursive: true);
  final browser = await browsers.puppeteer.launch(executablePath: chrome);
  try {
    final tab = await browser.newPage();
    await tab.setViewport(
      const browsers.DeviceViewport(
        width: 1600,
        height: 1000,
        deviceScaleFactor: 2,
      ),
    );
    for (final shot in chosen(names)) {
      final frame = await capture(shot, portDir);
      await tab.setContent(
        shot.group == 'logo' ? logoPage(frame) : page(frame),
        wait: browsers.Until.load,
      );
      await tab.evaluate<Object?>('() => document.fonts.ready');
      final element = await tab.$OrNull('.page');
      if (element == null) throw StateError('${shot.name}: nothing was drawn.');
      // Square and opaque, the backdrop to the picture's edge; a logo has
      // none, for the page it sits on.
      final png = await element.screenshot(
        omitBackground: shot.group == 'logo',
      );
      File(p.join(images.path, '${shot.name}.png')).writeAsBytesSync(png);
      stdout.writeln('docs/images/${shot.name}.png');
      if (shot.group == 'logo') continue;
      // Played again at each size the site shows a recording at.
      for (final size in recordingSizes) {
        final recording = RecordingWriter(size.cols, size.rows);
        await capture(
          shot,
          portDir,
          cols: size.cols,
          rows: size.rows,
          recording: recording,
        );
        final name = recordingName(shot.name, size);
        File(p.join(images.path, name)).writeAsStringSync(recording.toJson());
        stdout.writeln('docs/images/$name');
      }
    }
  } finally {
    await browser.close();
  }
}
