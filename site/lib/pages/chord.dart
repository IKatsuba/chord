import 'package:chord_tui/chord_tui.dart';

import '../band.dart';
import '../giant.dart';
import '../live/permission.dart';
import '../live/plan.dart';
import '../live/prompt.dart';
import '../live/start.dart';
import '../live_plate.dart';
import '../page.dart';
import '../router.dart';
import '../screens.dart';
import '../scroll_page.dart';
import '../site.dart' show narrowWidth, panelOnly;
import '../version.dart';

/// Below this many columns a live section stacks: its text, then the plate
/// at full width.
const chordStackWidth = 139;

/// A live plate's width beside its text: 80 inside and 2 of cream each side.
const chordPlateWidth = 84;

/// The lede under `APP.`.
const chordLede =
    "One window, every agent you run, every action on a key. These are "
    "chord's own screens, running live in this page with no agent behind "
    'them; whole sessions further down are recordings.';

/// The band's slogans.
const chordSlogans =
    'LIVE  ✦  NO AGENT BEHIND IT  ✦  TYPE, ANSWER, APPROVE  ✦  ';

/// One live section: its caps title, its key, what it says, how tall its
/// room is, and whether its fixture binds Esc.
typedef ChordSection = ({
  String title,
  String name,
  String key,
  String text,
  int rows,
  bool ownsEscape,
});

/// The four live sections, in order.
const chordSections = <ChordSection>[
  (
    title: 'THE PROMPT',
    name: 'PROMPT',
    key: 'p',
    text:
        'Write, edit, send. Multiline editing, history on the arrows, files '
        'with @ and commands with /.',
    rows: 4,
    ownsEscape: false,
  ),
  (
    title: 'PERMISSIONS',
    name: 'PERMISSION',
    key: 'a',
    text:
        'Asked first, every time: the diff or the command in front of you. '
        'Allow once, always, or deny.',
    // The fixture whole: its title, the 13-line diff, the question and
    // Esc to reject.
    rows: 28,
    ownsEscape: true,
  ),
  (
    title: 'PLANS',
    name: 'PLAN',
    key: 'l',
    text:
        "The agent's plan as a live checklist: steps tick off as the work "
        'goes, and the current one shows it is running. Here ctrl+t sets it '
        'working.',
    rows: 14,
    ownsEscape: false,
  ),
  (
    title: 'START',
    name: 'START',
    key: 's',
    text:
        'Every ACP agent in one list. Pick one with the arrows, a digit or '
        'Enter, and chord installs and starts it. Here nothing starts: the '
        'pick shows as one line, and r asks again.',
    rows: 19,
    ownsEscape: true,
  ),
];

/// chord, in C: `01 / THE APP`, the giant `APP.`, the lede and the band,
/// then chord's own screens live in four plates (p, a, l, s or Tab and
/// Enter), then the recorded flows as a ruled index.
class ChordPage extends StatefulWidget {
  /// The page, listing [recordings] (with their [lengths]) and opening one
  /// through [open].
  const ChordPage(
    this.recordings,
    this.open, {
    super.key,
    this.lengths = const {},
    required this.home,
  });

  /// The recorded screens, by name.
  final List<String> recordings;

  /// How long each plays, where known.
  final Map<String, Duration> lengths;

  /// Opens a route.
  final void Function(SiteRoute route) open;

  /// Goes home.
  final void Function() home;

  @override
  State<ChordPage> createState() => _ChordPageState();
}

class _ChordPageState extends State<ChordPage> {
  final _page = FocusNode(debugLabel: 'chord page');
  final _plates = [
    for (final _ in chordSections) FocusNode(debugLabel: 'chord plate'),
  ];
  final _flows = FocusNode(debugLabel: 'chord flows');
  final _controllers = [for (final _ in chordSections) LivePlateController()];
  var _promptLines = 1;
  var _selected = 0;

  @override
  void initState() {
    super.initState();
    _flows.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flows.removeListener(_changed);
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in [_page, ..._plates, _flows]) {
      n.dispose();
    }
    super.dispose();
  }

  List<String> get _names => orderedScreens(widget.recordings);

  // Tab's ring: the four plates, the flows index, then the page.
  void _cycle(int step) {
    final ring = [..._plates, _flows, _page];
    var at = ring.indexWhere((n) => n.hasPrimaryFocus);
    if (at < 0) at = ring.length - 1;
    var next = (at + step) % ring.length;
    if (next < 0) next += ring.length;
    // No recordings: the index has no row to take the focus.
    if (ring[next] == _flows && _names.isEmpty) {
      next = (next + step) % ring.length;
      if (next < 0) next += ring.length;
    }
    ring[next].requestFocus();
  }

  // Each flow row, as last built, to bring the selected one into sight.
  final _rows = <int, BuildContext>{};

  void _move(int step) {
    setState(() => _selected = (_selected + step).clamp(0, _names.length - 1));
    // The scroll view brings the focused index back to its own top after a
    // key it took; the second pass, after that, puts the row back in sight.
    void reveal() {
      final row = _rows[_selected];
      if (mounted && row != null) Scrollable.ensureVisible(row);
    }

    // The owner, not the context: the page may be gone before either pass.
    final owner = context.owner;
    owner.afterLayout(() {
      if (!mounted) return;
      reveal();
      owner.afterLayout(reveal);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final width = constraints.maxWidth;
      final margin = width < narrowWidth ? 2 : 4;
      final content = width - 1 - 2 * margin;
      final stacked = width < chordStackWidth;
      return ScrollPage(
        focusNode: _page,
        bindings: [
          for (final (i, s) in chordSections.indexed)
            Binding(
              s.key,
              'try',
              () => _controllers[i].enter(),
              id: 'chord:try',
            ),
          Binding('tab', 'next', () => _cycle(1), id: 'chord:next'),
          Binding(
            'shift+tab',
            'previous',
            () => _cycle(-1),
            id: '${panelOnly}chord:previous',
          ),
        ],
        sections: [
          Text(''),
          const Kicker(1, 'THE APP'),
          Text(''),
          const GiantWord('APP'),
          Text(''),
          const Paragraph(chordLede),
          Text(''),
          FullBleed(Band(chordSlogans, width: width - 1)),
          for (final (i, s) in chordSections.indexed) ...[
            Text(''),
            Text(''),
            _section(theme, i, s, content, stacked),
          ],
          Text(''),
          Text(''),
          Text(
            '05 / WHOLE FLOWS, RECORDED',
            style: theme.accent.merge(Style.bold),
          ),
          Text(''),
          _index(theme, content, narrow: width < narrowWidth),
          Text(''),
        ],
      );
    },
  );

  Widget _section(
    ThemeData theme,
    int i,
    ChordSection s,
    int content,
    bool stacked,
  ) {
    final number = '0${i + 1}';
    final textWidth = stacked ? content : content - 6 - chordPlateWidth;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            '',
            children: [
              TextSpan('$number  ', style: theme.accent.merge(Style.bold)),
              TextSpan(s.title, style: theme.text.merge(Style.bold)),
            ],
          ),
          softWrap: false,
        ),
        Text(
          '─' * (textWidth < 40 ? textWidth : 40),
          style: theme.border,
          softWrap: false,
        ),
        Text(s.text, style: theme.dim),
        Text(''),
        Text.rich(
          TextSpan(
            '',
            children: [
              TextSpan('→ TRY IT  ', style: theme.text),
              TextSpan(
                s.key.toUpperCase(),
                style: theme.accent.merge(Style.bold),
              ),
            ],
          ),
          softWrap: false,
        ),
      ],
    );
    final rows = i == 0 ? (3 + _promptLines).clamp(4, 8) : s.rows;
    final plate = LivePlate(
      controller: _controllers[i],
      focusNode: _plates[i],
      onEscape: _page.requestFocus,
      figure: i + 1,
      figureDigits: 2,
      title: 'LIVE · ${s.name}',
      idle: 'LIVE · PRESS ${s.key.toUpperCase()}',
      rows: rows,
      ownsEscape: s.ownsEscape,
      home: widget.home,
      child: (_) => switch (i) {
        0 => LivePrompt(
          onLines: (lines) => setState(() => _promptLines = lines),
        ),
        1 => const LivePermission(),
        2 => const LivePlan(),
        _ => const LiveStart(version: chordVersion),
      },
    );
    // One tree either way, so the fixture keeps its state across the
    // stacking width: the plate is always the row's last cell, under the
    // text when stacked.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: stacked ? 0 : textWidth, child: stacked ? null : text),
        SizedBox(width: stacked ? 0 : 6),
        SizedBox(
          width: stacked ? content : chordPlateWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              stacked ? text : const SizedBox(),
              stacked ? Text('') : const SizedBox(),
              plate,
            ],
          ),
        ),
      ],
    );
  }

  /// The recordings, one ruled row each: number, caps name, what it shows
  /// and its length, or `⏎ PLAY` on the selected row while the index has
  /// the focus.
  Widget _index(ThemeData theme, int content, {required bool narrow}) {
    final names = _names;
    if (names.isEmpty) {
      return Text('No screens were recorded.', style: theme.dim);
    }
    final focused = _flows.hasPrimaryFocus;
    String clock(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    Widget row(int i) {
      final name = names[i];
      final selected = focused && i == _selected;
      final length = widget.lengths[name];
      final end = selected
          ? Text('⏎ PLAY', style: theme.accent.merge(Style.bold))
          : Text(
              // A one-frame shot has no length to give: it is a still.
              length == null
                  ? ''
                  : length == Duration.zero
                  ? 'STILL'
                  : clock(length),
              style: theme.dim,
            );
      final caption = screenCaptions[name] ?? '';
      final head = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 4,
            child: Text(
              (i + 1).toString().padLeft(2, '0'),
              style: theme.accent.merge(Style.bold),
            ),
          ),
          SizedBox(
            width: 14,
            child: Text(
              name.toUpperCase(),
              style: selected
                  ? theme.accent.merge(const Style(bold: true, inverse: true))
                  : theme.text.merge(Style.bold),
              softWrap: false,
            ),
          ),
          Expanded(
            child: narrow
                ? const SizedBox()
                : Text(caption, style: theme.dim, softWrap: false),
          ),
          const SizedBox(width: 2),
          end,
        ],
      );
      return Builder(
        builder: (context) {
          _rows[i] = context;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (event.button == MouseButton.primary) {
                widget.open(RecordingRoute(name));
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                if (narrow)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(caption, style: theme.dim),
                  ),
                Text(
                  '─' * content,
                  style: selected ? theme.accent : theme.border,
                  softWrap: false,
                ),
              ],
            ),
          );
        },
      );
    }

    return Actions(
      bindings: [
        Binding('up', 'move', () => _move(-1), id: 'chord:flows-move'),
        Binding('down', 'move', () => _move(1), id: 'chord:flows-move'),
        Binding(
          'enter',
          'play',
          () => widget.open(RecordingRoute(names[_selected])),
        ),
        Binding('esc', 'leave', _page.requestFocus, id: 'chord:flows-leave'),
      ],
      child: Focus(
        focusNode: _flows,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('─' * content, style: theme.border, softWrap: false),
            for (var i = 0; i < names.length; i++) row(i),
          ],
        ),
      ),
    );
  }
}
