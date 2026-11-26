import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';

import '../host.dart';
import '../pacing.dart';

/// The sizes recordings come in, largest first.
const recordingSizes = [(cols: 120, rows: 36), (cols: 80, rows: 20)];

/// Whether a page of [cols] by [rows], its bar's row included, shows its
/// recording clipped.
bool recordingClipped(int cols, int rows) {
  final size = recordingSizeFor(cols, rows - 1);
  return size.cols > cols || size.rows > rows - 1;
}

/// The recording size for a room of [cols] by [rows]: the largest that
/// fits, else the smallest, shown clipped.
({int cols, int rows}) recordingSizeFor(int cols, int rows) =>
    recordingSizes.firstWhere(
      (size) => size.cols <= cols && size.rows <= rows,
      orElse: () => recordingSizes.last,
    );

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

  /// The page's height, the bar's row included.
  final int rows;

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  String? _file;
  PlaybackController? _controller;
  var _failed = false;

  String get _wanted {
    final size = recordingSizeFor(widget.cols, widget.rows - 1);
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

  Future<void> _load() async {
    final file = _file = _wanted;
    final text = await widget.host.recording(file);
    // A newer fetch, or the page gone, wins.
    if (!mounted || file != _file) return;
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
    if (controller == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Text(
          _failed ? "couldn't load ${widget.name}" : 'loading ${widget.name}…',
          style: theme.dim,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Playback(controller, autofocus: true)),
        // In line with the help row under it.
        Padding(
          padding: const EdgeInsets.only(left: 1),
          child: PlaybackBar(controller),
        ),
      ],
    );
  }
}
