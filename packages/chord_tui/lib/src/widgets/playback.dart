import 'dart:async';

import 'package:characters/characters.dart';
import 'package:clock/clock.dart';

import '../foundation/geometry.dart';
import '../foundation/notifier.dart';
import '../foundation/playback.dart';
import '../terminal/style.dart';
import '../text/ansi.dart';
import '../text/span.dart';
import '../text/width.dart';
import 'basic.dart';
import 'focus.dart';
import 'focus_manager.dart';
import 'framework.dart';
import 'layout_builder.dart';

/// What a [PlaybackController] is on: its [PlaybackState] with the
/// recording's length and the current step.
class PlaybackValue {
  /// The value of [state] in [recording].
  factory PlaybackValue(TerminalRecording recording, PlaybackState state) {
    final step = stepOf(recording, state.frame);
    return PlaybackValue._(
      state,
      recording.duration,
      recording.steps.length,
      step,
      step < 0 ? null : recording.frames[recording.steps[step]].label,
    );
  }

  PlaybackValue._(
    this.state,
    this.duration,
    this.stepCount,
    this.step,
    this.label,
  );

  /// Where the playback is.
  final PlaybackState state;

  /// How long the recording runs.
  final Duration duration;

  /// How many steps the recording has.
  final int stepCount;

  /// The index of the current step; -1 before the first one.
  final int step;

  /// The current step's label, if its frame has one.
  final String? label;

  /// How far into the recording.
  Duration get position => state.position;

  /// The index of the frame shown.
  int get frame => state.frame;

  /// Whether time advances.
  bool get isPlaying => state.isPlaying;

  /// Whether play reached the end and stopped there.
  bool get isEnded => state.isEnded;
}

/// Plays a [TerminalRecording]: the state [reducePlayback] keeps, and the
/// timer that advances it while playing by the time that really passed.
class PlaybackController extends ChangeNotifier {
  /// A paused controller at the start of [recording]; [looping] plays it
  /// again from the beginning instead of ending.
  PlaybackController(this.recording, {this.looping = false});

  /// What is played.
  final TerminalRecording recording;

  /// Whether play starts again at the end.
  final bool looping;

  var _state = const PlaybackState();
  Timer? _timer;
  // Time since the state last took in what passed: every command and tick
  // takes it in first, so pausing between frames keeps the time played.
  final Stopwatch _sinceSettled = clock.stopwatch()..start();

  /// Where the playback is now, with its step.
  PlaybackValue get value => PlaybackValue(
    recording,
    reducePlayback(
      recording,
      _state,
      PlaybackTick(_sinceSettled.elapsed),
      looping: looping,
    ),
  );

  /// Starts time; from the end, plays from the beginning.
  void play() => _dispatch(const PlaybackPlay());

  /// Stops time where it is.
  void pause() => _dispatch(const PlaybackPause());

  /// Moves to [position], keeping whether it plays.
  void seekTo(Duration position) => _dispatch(PlaybackSeek(position));

  /// Pauses at the next step, or at the end.
  void nextStep() => _dispatch(const PlaybackNextStep());

  /// Pauses at the step before the current one.
  void previousStep() => _dispatch(const PlaybackPreviousStep());

  /// Plays from the beginning.
  void restart() => _dispatch(const PlaybackRestart());

  void _dispatch([PlaybackAction? action]) {
    checkNotDisposed();
    final passed = _sinceSettled.elapsed;
    _sinceSettled.reset();
    var next = reducePlayback(
      recording,
      _state,
      PlaybackTick(passed),
      looping: looping,
    );
    if (action != null) {
      next = reducePlayback(recording, next, action, looping: looping);
    }
    _schedule(next);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  // The next tick lands on the next frame or the next whole second, so the
  // bar's clock moves as the frames do.
  void _schedule(PlaybackState state) {
    _timer?.cancel();
    _timer = null;
    if (!state.isPlaying || recording.frames.isEmpty) return;
    final frames = recording.frames;
    var wait = state.frame + 1 < frames.length
        ? frames[state.frame + 1].at - state.position
        : recording.duration - state.position;
    final toSecond = Duration(
      microseconds:
          Duration.microsecondsPerSecond -
          state.position.inMicroseconds % Duration.microsecondsPerSecond,
    );
    if (toSecond < wait) wait = toSecond;
    if (wait < Duration.zero) wait = Duration.zero;
    _timer = Timer(wait, _dispatch);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Draws the frame a [PlaybackController] is on, at the recording's size
/// from the top left, and binds its keys while focused.
///
/// A room smaller than the recording cuts it at the bottom and right, marks
/// the cut edges with a dim `›` column and `⌄` row, and Shift+arrows pan.
/// Playback draws no focus mark: its container does.
class Playback extends StatefulWidget {
  /// Plays [controller]'s recording.
  const Playback(
    this.controller, {
    super.key,
    this.autofocus = false,
    this.focusNode,
  });

  /// What is played.
  final PlaybackController controller;

  /// Whether it takes focus when first built.
  final bool autofocus;

  /// The node that holds its focus; one of its own when null.
  final FocusNode? focusNode;

  @override
  State<Playback> createState() => _PlaybackState();
}

class _PlaybackState extends State<Playback> {
  FocusNode? _ownNode;
  var _panX = 0;
  var _panY = 0;
  var _room = Size.zero;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(Playback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _panX = 0;
      _panY = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _ownNode?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = widget.controller;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  void _pan(int dx, int dy) {
    final recording = widget.controller.recording;
    setState(() {
      _panX = _clampPan(_panX + dx, recording.cols, _room.width);
      _panY = _clampPan(_panY + dy, recording.rows, _room.height);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _layout);

  // The keys are bound under the layout: panning is offered only where the
  // room cuts the recording, so the help lists no key that does nothing.
  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final controller = widget.controller;
    final recording = controller.recording;
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : recording.cols;
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : recording.rows;
    final across = recording.cols > width;
    final down = recording.rows > height;
    return Actions(
      bindings: [
        Binding('space', 'Play/pause', _toggle),
        Binding('right', 'Next', controller.nextStep),
        Binding('l', 'Next', controller.nextStep),
        Binding('left', 'Previous', controller.previousStep),
        Binding('h', 'Previous', controller.previousStep),
        Binding('r', 'Restart', controller.restart),
        Binding('shift+right', 'Pan', () => _pan(1, 0), enabled: across),
        Binding('shift+left', 'Pan', () => _pan(-1, 0), enabled: across),
        Binding('shift+down', 'Pan', () => _pan(0, 1), enabled: down),
        Binding('shift+up', 'Pan', () => _pan(0, -1), enabled: down),
      ],
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        child: _frame(width, height),
      ),
    );
  }

  Widget _frame(int width, int height) {
    final recording = widget.controller.recording;
    _room = Size(width, height);
    // A wider room after a resize may leave less to pan over.
    _panX = _clampPan(_panX, recording.cols, width);
    _panY = _clampPan(_panY, recording.rows, height);
    if (recording.frames.isEmpty) return const SizedBox();
    final frame = recording.frames[widget.controller.value.frame];
    final cutRight = _panX + width < recording.cols;
    final cutBottom = _panY + height < recording.rows;
    final shownRows = height < recording.rows ? height : recording.rows;
    final shownCols = width < recording.cols ? width : recording.cols;
    const mark = Style(dim: true);
    return Column(
      children: [
        for (var row = 0; row < shownRows; row++)
          if (cutBottom && row == shownRows - 1)
            Text('⌄' * shownCols, style: mark, softWrap: false)
          else
            Text.rich(
              TextSpan(
                '',
                children: [
                  ...sliceColumns(
                    parseAnsi(
                      _panY + row < frame.rows.length
                          ? frame.rows[_panY + row]
                          : '',
                    ),
                    _panX,
                    cutRight ? shownCols - 1 : shownCols,
                  ),
                  if (cutRight) const TextSpan('›', style: mark),
                ],
              ),
              softWrap: false,
            ),
      ],
    );
  }
}

int _clampPan(int pan, int recorded, int room) {
  final most = recorded - room;
  if (most <= 0 || pan < 0) return 0;
  return pan > most ? most : pan;
}

/// The cells [start] to [start] + [width] of [span]'s runs, each run keeping
/// its style; a wide character cut by either edge becomes spaces, and a
/// short row is padded with spaces to [width].
List<TextSpan> sliceColumns(TextSpan span, int start, int width) {
  final out = <TextSpan>[];
  var column = 0;
  final end = start + width;
  for (final (text, style) in span.flatten()) {
    final taken = StringBuffer();
    for (final grapheme in text.characters) {
      final cells = graphemeWidth(grapheme);
      final from = column;
      column += cells;
      if (column <= start || from >= end) continue;
      final inside =
          (column < end ? column : end) - (from > start ? from : start);
      taken.write(from < start || column > end ? ' ' * inside : grapheme);
    }
    if (taken.isNotEmpty) out.add(TextSpan(taken.toString(), style: style));
    if (column >= end) break;
  }
  final shown = column < start ? 0 : (column < end ? column : end) - start;
  if (shown < width) out.add(TextSpan(' ' * (width - shown)));
  return out;
}

/// One row for a [PlaybackController]: `▶ 0:04 / 0:12 · step 3 of 7 ·
/// label` while playing, `❚❚` for paused, `■ ended · r restart` at the end,
/// and `no frames` for an empty recording. Before the first step there is
/// no step to name.
class PlaybackBar extends StatelessWidget {
  /// The bar of [controller].
  const PlaybackBar(this.controller, {super.key});

  /// What the bar reports.
  final PlaybackController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context) =>
        Text(playbackBarText(controller.value), softWrap: false),
  );
}

/// The text [PlaybackBar] shows for [value].
String playbackBarText(PlaybackValue value) {
  if (value.stepCount == 0) return 'no frames';
  if (value.isEnded) return '■ ended · r restart';
  return [
    '${value.isPlaying ? '▶' : '❚❚'} '
        '${_clock(value.position)} / ${_clock(value.duration)}',
    if (value.step >= 0) 'step ${value.step + 1} of ${value.stepCount}',
    ?value.label,
  ].join(' · ');
}

String _clock(Duration time) =>
    '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';
