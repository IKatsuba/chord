import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';

import '../host.dart';
import '../pacing.dart';
import '../site.dart' show narrowWidth;

/// The sizes recordings come in, largest first.
const recordingSizes = [
  (cols: 120, rows: 36),
  (cols: 80, rows: 20),
  (cols: 48, rows: 32),
];

/// How a recording sits in a page: its size, whether it has its cream frame
/// and caption row, and whether even so it is clipped.
typedef RecordingFit = ({int cols, int rows, bool framed, bool clipped});

/// The recording for a page of [cols] by [rows]: the largest that fits with
/// its frame (2 columns, 2 rows), the caption row and the bar, each with a
/// blank (4 rows); else the smallest without the frame and caption; else
/// the smallest, clipped.
RecordingFit recordingFitFor(int cols, int rows) {
  for (final size in recordingSizes) {
    if (size.cols + 2 <= cols && size.rows + 6 <= rows) {
      return (cols: size.cols, rows: size.rows, framed: true, clipped: false);
    }
  }
  final smallest = recordingSizes.last;
  return (
    cols: smallest.cols,
    rows: smallest.rows,
    framed: false,
    clipped: smallest.cols > cols || smallest.rows + 2 > rows,
  );
}

/// Whether a page of [cols] by [rows] shows its recording clipped.
bool recordingClipped(int cols, int rows) =>
    recordingFitFor(cols, rows).clipped;

/// One of chord's screens, fetched from [host] when it opens and played in
/// a [Playback] above its bar.
class RecordingPage extends StatefulWidget {
  /// The recording called [name], for a page of [cols] by [rows].
  const RecordingPage({
    super.key,
    required this.host,
    required this.name,
    required this.cols,
    required this.rows,
  });

  /// Where the recording is fetched from.
  final SiteHost host;

  /// The shot's name.
  final String name;

  /// The page's width.
  final int cols;

  /// The page's height.
  final int rows;

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  String? _file;
  PlaybackController? _controller;
  var _failed = false;
  // Which fetch the page waits on: an older one that returns later, even
  // for the same file, is dropped.
  var _generation = 0;

  String get _wanted {
    final size = recordingFitFor(widget.cols, widget.rows);
    return '${widget.name}.${size.cols}x${size.rows}.rec.json';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecordingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_wanted != _file) _load();
  }

  // Called from initState and didUpdateWidget, where the build follows:
  // the page says it is loading from the moment a fetch begins.
  Future<void> _load() async {
    final file = _file = _wanted;
    final generation = ++_generation;
    _controller?.dispose();
    _controller = null;
    _failed = false;
    final text = await widget.host.recording(file);
    if (!mounted || generation != _generation) return;
    TerminalRecording? recording;
    try {
      if (text != null) {
        recording = TerminalRecording.fromJson(jsonDecode(text));
      }
    } on FormatException {
      recording = null;
    }
    setState(() {
      _controller?.dispose();
      _controller = recording == null
          ? null
          : (PlaybackController(paced(recording))..play());
      _failed = recording == null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);
    final narrow = widget.cols < narrowWidth;
    final margin = narrow ? 2 : 4;
    final orange = theme.accent.merge(Style.bold);
    final name = widget.name.toUpperCase();
    if (controller == null) {
      return Padding(
        padding: EdgeInsets.only(left: margin, top: 2),
        child: Text(
          _failed ? "COULDN'T LOAD $name" : 'LOADING $name…',
          style: theme.dim,
        ),
      );
    }
    final fit = recordingFitFor(widget.cols, widget.rows);
    final needed = fit.framed ? fit.rows + 6 : widget.rows;
    final above = ((widget.rows - needed) ~/ 2).clamp(0, widget.rows);
    // A clipped recording gets what the page has left, its bar and blank
    // below it, so Playback pans to what does not fit.
    final roomRows = fit.rows + 2 > widget.rows
        ? (widget.rows - 2).clamp(1, fit.rows)
        : fit.rows;
    final room = SizedBox(
      width: fit.cols < widget.cols ? fit.cols : widget.cols,
      height: roomRows,
      child: Playback(controller, autofocus: true),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: above),
        if (fit.framed) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: margin),
            child: Row(
              children: [
                Text(
                  narrow ? '01 / $name' : '01 / THE APP / $name',
                  style: orange,
                  softWrap: false,
                ),
                const Spacer(),
                if (!narrow)
                  ListenableBuilder(
                    listenable: controller,
                    builder: (_) {
                      final value = controller.value;
                      return value.step < 0
                          ? const SizedBox()
                          : Text(
                              'STEP ${value.step + 1} OF ${value.stepCount}',
                              style: theme.text.merge(Style.bold),
                              softWrap: false,
                            );
                    },
                  ),
              ],
            ),
          ),
          Text(''),
          Align(
            alignment: Alignment.topCenter,
            child: Box(
              background: theme.text.merge(const Style(inverse: true)),
              padding: const EdgeInsets.all(1),
              child: room,
            ),
          ),
        ] else
          Align(alignment: Alignment.topCenter, child: room),
        Text(''),
        // Inside the margins, its label shortened with … where it runs out.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          child: Align(
            alignment: Alignment.topCenter,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_) => recordingBar(theme, controller.value),
            ),
          ),
        ),
      ],
    );
  }
}

/// C's bar under a recording: an orange cell for the state, the time, and
/// the step's label in muted caps.
Widget recordingBar(ThemeData theme, PlaybackValue value) {
  final cell = theme.accent.merge(const Style(bold: true, inverse: true));
  String clock(Duration t) =>
      '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
  final (mark, words) = value.isEnded
      ? ('■', null)
      : (
          value.isPlaying ? '▶' : '❚❚',
          '${clock(value.position)} / ${clock(value.duration)}',
        );
  return Text.rich(
    TextSpan(
      '',
      children: [
        TextSpan(' $mark ', style: cell),
        if (words == null) ...[
          TextSpan(' ENDED', style: theme.text.merge(Style.bold)),
          TextSpan(' · ', style: theme.dim),
          TextSpan('R RESTART', style: theme.dim),
        ] else ...[
          TextSpan(' $words', style: theme.text.merge(Style.bold)),
          if (value.label case final label?) ...[
            TextSpan(' · ', style: theme.dim),
            TextSpan(label.toUpperCase(), style: theme.dim),
          ],
        ],
      ],
    ),
    softWrap: false,
    overflow: TextOverflow.ellipsis,
  );
}
