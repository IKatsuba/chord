import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';

import '../band.dart';
import '../giant.dart';
import '../host.dart';
import '../nav.dart';
import '../pacing.dart';
import '../page.dart';
import '../router.dart';
import '../scroll_page.dart';
import '../site.dart' show narrowWidth;

/// The sizes the home plate may play `edit` at, largest first.
const homeRecordingSizes = [
  (cols: 120, rows: 36),
  (cols: 80, rows: 20),
  (cols: 48, rows: 32),
];

/// The largest recording size whose width fits [inner] columns, else the
/// smallest.
({int cols, int rows}) homeRecordingFor(int inner) => homeRecordingSizes
    .firstWhere((s) => s.cols <= inner, orElse: () => homeRecordingSizes.last);

/// What the numbered columns say, by section.
const homeColumns = [
  (
    title: 'THE APP',
    text: 'Sessions, agents, teams, permissions and plans, in one window.',
  ),
  (
    title: 'THE FRAMEWORK',
    text: 'Flutter-shaped widgets for the terminal, in Dart, from scratch.',
  ),
  (
    title: 'THE GALLERY',
    text: "Nine of the framework's examples, running on this page.",
  ),
  (title: 'INSTALL', text: 'Homebrew, npm, or from source.'),
];

const _slogans =
    'THE TERMINAL IS THE PAGE  ✦  EVERY ACTION HAS A KEY  ✦  '
    'CLAUDE · CODEX · GEMINI · CURSOR  ✦  WRITTEN IN DART  ✦  ';

/// Home, in C: the giant `CHORD.`, the statement, paragraph and buttons,
/// the green band, the four numbered columns, FIG. 1's recorded session
/// in a cream plate, and the footer. `i` installs, `w` plays the session,
/// 1–4 go to the sections.
class HomePage extends StatefulWidget {
  /// Home on [host], opening a part through [open].
  const HomePage({super.key, required this.host, required this.open});

  /// Where the recording is fetched from.
  final SiteHost host;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scroll = ScrollController();
  final _playbackFocus = FocusNode();
  BuildContext? _plate;
  PlaybackController? _playback;
  String? _file;
  var _failed = false;
  var _generation = 0;

  // Whether the current file is still on its way; w then waits for it.
  var _loading = false;

  // w pressed before the current file came: it plays once it does.
  var _watchPending = false;

  static const _installId = 'home:install';
  static const _watchId = 'home:watch';

  @override
  void dispose() {
    _playback?.dispose();
    _playbackFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Fetches the file for [inner] columns once, and again only when another
  // size fits; an older fetch that returns later is dropped.
  void _load(int inner) {
    final size = homeRecordingFor(inner);
    final file = 'edit.${size.cols}x${size.rows}.rec.json';
    if (file == _file) return;
    _file = file;
    final generation = ++_generation;
    // A new request: what the last one ended in, and a w meant for it, no
    // longer stand.
    _loading = true;
    _failed = false;
    _watchPending = false;
    widget.host.recording(file).then((text) {
      if (!mounted || generation != _generation) return;
      TerminalRecording? recording;
      try {
        if (text != null) {
          recording = TerminalRecording.fromJson(jsonDecode(text));
        }
      } on FormatException {
        recording = null;
      }
      _loading = false;
      setState(() {
        _playback?.dispose();
        _playback = null;
        _failed = recording == null;
        if (recording != null) {
          // Paused on the last frame until w plays it.
          final paced_ = paced(recording);
          _playback = PlaybackController(paced_)..seekTo(paced_.duration);
        }
      });
      if (_watchPending) {
        _watchPending = false;
        // Once the Playback is built, so it can take the focus.
        if (recording != null) context.owner.afterLayout(_watch);
      }
    });
  }

  void _watch() {
    if (!mounted) return;
    final playback = _playback;
    if (_loading) {
      // The plate is changing size: the coming recording plays, not the
      // one it replaces.
      _watchPending = true;
    } else if (playback != null) {
      _playbackFocus.requestFocus();
      playback.restart();
    }
    // The scroll view brings a newly focused Playback into sight after
    // this frame's layout, and one taller than the view to its own top,
    // under the caption; that jump lays out again, and the second pass puts
    // the plate's top back at the view's top.
    // The owner, not the context: home may be gone before either pass.
    final owner = context.owner;
    owner.afterLayout(() {
      if (!mounted) return;
      _bringPlate();
      owner.afterLayout(_bringPlate);
    });
    setState(() {});
  }

  void _bringPlate() {
    final plate = _plate;
    if (mounted && plate != null) {
      Scrollable.ensureVisible(plate, alignment: 0);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final phone = constraints.maxWidth < narrowWidth;
      final margin = phone ? 2 : 4;
      final content = constraints.maxWidth - 1 - 2 * margin;
      _load(content - 2);
      final bold = theme.text.merge(Style.bold);
      final accent = theme.accent.merge(Style.bold);
      final statement = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A TERMINAL WINDOW', style: bold),
          Text('FOR CODING AGENTS.', style: bold),
        ],
      );
      final install = FilledButton(
        action: _installId,
        dense: true,
        canRequestFocus: false,
        child: Text('INSTALL'),
      );
      final watch = OutlinedButton(
        action: _watchId,
        dense: true,
        canRequestFocus: false,
        child: Text('WATCH IT RUN'),
      );
      const paragraph = Paragraph(
        'Claude, Codex, Gemini and Cursor side by side, every action on a '
        'key. And the Dart framework that draws it, and draws this page, '
        'cell by cell.',
      );
      // Beside the statement only where the right column gets 60; the
      // buttons side by side where they fit.
      final beside = content - 50 >= 60;
      final buttonsFit =
          cellWidth(' INSTALL  i ') + 3 + cellWidth(' WATCH IT RUN  w ') <=
          content;
      final hero = !beside
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statement,
                Text(''),
                paragraph,
                Text(''),
                if (buttonsFit)
                  Row(children: [install, const SizedBox(width: 3), watch])
                else ...[
                  Row(children: [install]),
                  Text(''),
                  Row(children: [watch]),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 44, child: statement),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      paragraph,
                      Text(''),
                      Row(children: [install, const SizedBox(width: 3), watch]),
                    ],
                  ),
                ),
              ],
            );
      final perRow = constraints.maxWidth >= 120
          ? 4
          : constraints.maxWidth >= narrowWidth
          ? 2
          : 1;
      Widget plate(int width) => Builder(
        builder: (context) {
          _plate = context;
          return _plateOf(theme, content, width);
        },
      );
      return ScrollPage(
        controller: _scroll,
        bindings: [
          Binding(
            'i',
            'install',
            () => widget.open(const InstallRoute()),
            id: _installId,
          ),
          Binding('w', 'watch', _watch, id: _watchId),
          for (final (n, s) in sections.indexed)
            Binding(
              '${n + 1}',
              'go',
              () => widget.open(s.route),
              id: 'home:go',
            ),
        ],
        sections: [
          Text(''),
          Text(''),
          const GiantWord('CHORD'),
          Text(''),
          hero,
          Text(''),
          FullBleed(Band(_slogans, width: constraints.maxWidth - 1)),
          Text(''),
          for (var r = 0; r * perRow < homeColumns.length; r++) ...[
            _columnsRow(theme, r, perRow, content),
            Text(''),
          ],
          Text(''),
          Text('FIG. 1 / A REAL SESSION, RECORDED', style: accent),
          // A recording and its frame that do not fit in the margins take
          // the window's width up to the scrollbar; past that, the Playback
          // clips and pans.
          if (homeRecordingFor(content - 2).cols + 2 > content)
            FullBleed(plate(constraints.maxWidth - 1))
          else
            plate(content),
          Text(''),
          Text('─' * content, style: theme.border, softWrap: false),
          Row(
            children: [
              Text(
                'MIT  ·  MADE WITH CHORD_TUI  ·  DRAWN BY WTERM',
                style: theme.dim,
                softWrap: false,
              ),
              const Spacer(),
              Text('?  ALL KEYS', style: theme.text, softWrap: false),
            ],
          ),
          Text(''),
        ],
      );
    },
  );

  /// Row [r] of the numbered columns, [perRow] to a row, 4 apart.
  Widget _columnsRow(ThemeData theme, int r, int perRow, int content) {
    const gap = 4;
    final room = content - gap * (perRow - 1);
    final cells = [
      for (var j = 0; j < perRow && r * perRow + j < homeColumns.length; j++)
        (
          i: r * perRow + j,
          width: room ~/ perRow + (j < room % perRow ? 1 : 0),
        ),
    ];
    // Every description in the row takes the tallest one's rows, so the
    // PRESS lines sit on one line.
    final textRows = cells.fold(0, (rows, c) {
      final h = TextLayout.compute(
        TextSpan(homeColumns[c.i].text),
        maxWidth: c.width,
      ).height;
      return h > rows ? h : rows;
    });
    return Row(
      spacing: gap,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final c in cells) _column(theme, c.i, c.width, textRows)],
    );
  }

  Widget _column(ThemeData theme, int i, int width, int textRows) {
    final column = homeColumns[i];
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.button == MouseButton.primary) {
          widget.open(sections[i].route);
        }
      },
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisplayText(
              '0${i + 1}',
              size: DisplaySize.numeral,
              style: theme.accent,
            ),
            Text(''),
            Text(column.title, style: theme.text.merge(Style.bold)),
            Text('─' * width, style: theme.border, softWrap: false),
            SizedBox(
              height: textRows,
              child: Text(column.text, style: theme.dim),
            ),
            Text(''),
            Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan('→ ', style: theme.text),
                  TextSpan('PRESS ', style: theme.text.merge(Style.bold)),
                  TextSpan('${i + 1}', style: theme.accent.merge(Style.bold)),
                ],
              ),
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }

  /// FIG. 1's cream plate, [width] wide: its caption row ink on cream, then
  /// the recording, with a cell of cream around it. The recording is the
  /// one for the [content] width.
  Widget _plateOf(ThemeData theme, int content, int width) {
    final cream = theme.text.merge(const Style(inverse: true));
    final playback = _playback;
    Widget caption(String words) => SizedBox(
      width: width,
      child: Text(' $words', style: cream.merge(Style.bold), softWrap: false),
    );
    Widget inside;
    String words;
    if (playback == null) {
      words = _failed ? "▶ EDIT · COULDN'T LOAD" : '▶ EDIT · LOADING…';
      inside = SizedBox(height: 1, width: width - 2);
    } else {
      final size = homeRecordingFor(content - 2);
      inside = SizedBox(
        width: width - 2 < size.cols ? width - 2 : size.cols,
        height: size.rows,
        child: Playback(playback, focusNode: _playbackFocus),
      );
      words = '';
    }
    return Box(
      background: cream,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('', style: cream),
          if (playback == null)
            caption(words)
          else
            ListenableBuilder(
              listenable: playback,
              builder: (context) {
                final value = playback.value;
                final d = value.duration;
                final time =
                    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
                return caption(
                  '▶ EDIT · $time · '
                  '${value.isPlaying ? 'SPACE PAUSES' : 'W PLAYS'}',
                );
              },
            ),
          Text('', style: cream),
          Padding(padding: const EdgeInsets.only(left: 1), child: inside),
          Text('', style: cream),
        ],
      ),
    );
  }
}
