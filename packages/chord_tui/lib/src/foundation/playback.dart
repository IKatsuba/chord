/// One screen of a recorded terminal: its rows, each carrying its own SGR
/// sequences, from [at] after the recording began.
class TerminalRecordingFrame {
  /// A frame shown from [at], with an optional step [label].
  const TerminalRecordingFrame({
    required this.at,
    required this.rows,
    this.label,
  });

  /// When the frame appears.
  final Duration at;

  /// The frame's rows, top first, with their SGR sequences.
  final List<String> rows;

  /// What happened by this frame; a labelled frame starts a step.
  final String? label;
}

/// A terminal recorded from a real program: its size and its frames in
/// time order.
class TerminalRecording {
  /// A recording of a [cols] by [rows] terminal.
  const TerminalRecording({
    required this.cols,
    required this.rows,
    required this.frames,
  });

  /// Reads the JSON a recorder writes: `version` 1, `cols`, `rows`, and
  /// `frames` of `at` in milliseconds, `rows` and `label`. Throws a
  /// [FormatException] for anything else.
  factory TerminalRecording.fromJson(Object? json) {
    if (json case {
      'version': 1,
      'cols': final int cols,
      'rows': final int rows,
      'frames': final List<Object?> frames,
    }) {
      return TerminalRecording(
        cols: cols,
        rows: rows,
        frames: [
          for (final frame in frames)
            if (frame
                case {'at': final int at, 'rows': final List<Object?> lines}
                when lines.every((line) => line is String) &&
                    (frame['label'] == null || frame['label'] is String))
              TerminalRecordingFrame(
                at: Duration(milliseconds: at),
                rows: lines.cast<String>(),
                label: frame['label'] as String?,
              )
            else
              throw FormatException('Not a recording frame: $frame'),
        ],
      );
    }
    throw const FormatException('Not a version 1 recording.');
  }

  /// The terminal's width, in cells.
  final int cols;

  /// The terminal's height, in cells.
  final int rows;

  /// The frames, earliest first.
  final List<TerminalRecordingFrame> frames;

  /// How long the recording runs: until its last frame appears.
  Duration get duration => frames.isEmpty ? Duration.zero : frames.last.at;

  /// The indexes of the frames that start a step: the labelled ones, or
  /// every frame when none is labelled.
  List<int> get steps {
    final labelled = [
      for (var i = 0; i < frames.length; i++)
        if (frames[i].label != null) i,
    ];
    return labelled.isEmpty && frames.isNotEmpty
        ? List.generate(frames.length, (i) => i)
        : labelled;
  }
}

/// Where a recording is played: the time, the frame shown, and whether it
/// plays or has ended.
class PlaybackState {
  /// The state at [position], showing frame [frame].
  const PlaybackState({
    this.position = Duration.zero,
    this.frame = 0,
    this.isPlaying = false,
    this.isEnded = false,
  });

  /// How far into the recording.
  final Duration position;

  /// The index of the frame shown.
  final int frame;

  /// Whether time advances.
  final bool isPlaying;

  /// Whether play reached the last frame and stopped there.
  final bool isEnded;

  /// A copy with the given fields replaced.
  PlaybackState copyWith({
    Duration? position,
    int? frame,
    bool? isPlaying,
    bool? isEnded,
  }) => PlaybackState(
    position: position ?? this.position,
    frame: frame ?? this.frame,
    isPlaying: isPlaying ?? this.isPlaying,
    isEnded: isEnded ?? this.isEnded,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.position == position &&
      other.frame == frame &&
      other.isPlaying == isPlaying &&
      other.isEnded == isEnded;

  @override
  int get hashCode => Object.hash(position, frame, isPlaying, isEnded);

  @override
  String toString() =>
      'PlaybackState($position, frame $frame'
      '${isPlaying ? ', playing' : ''}${isEnded ? ', ended' : ''})';
}

/// What can happen to a playback.
sealed class PlaybackAction {
  const PlaybackAction();
}

/// Starts time; from the end, starts again from the beginning.
final class PlaybackPlay extends PlaybackAction {
  /// Play.
  const PlaybackPlay();
}

/// Stops time where it is.
final class PlaybackPause extends PlaybackAction {
  /// Pause.
  const PlaybackPause();
}

/// Moves to [position], keeping whether it plays.
final class PlaybackSeek extends PlaybackAction {
  /// Seek to [position].
  const PlaybackSeek(this.position);

  /// Where to move, clamped to the recording.
  final Duration position;
}

/// Pauses at the start of the next step, or at the end.
final class PlaybackNextStep extends PlaybackAction {
  /// Next step.
  const PlaybackNextStep();
}

/// Pauses at the start of the latest step before the frame shown, or at
/// the beginning.
final class PlaybackPreviousStep extends PlaybackAction {
  /// Previous step.
  const PlaybackPreviousStep();
}

/// Plays from the beginning.
final class PlaybackRestart extends PlaybackAction {
  /// Restart.
  const PlaybackRestart();
}

/// Time passed while playing: [elapsed] more of the recording.
final class PlaybackTick extends PlaybackAction {
  /// A tick of [elapsed].
  const PlaybackTick(this.elapsed);

  /// How much time passed.
  final Duration elapsed;
}

/// The frame shown at [position]: the last one that has appeared by then.
int frameAt(TerminalRecording recording, Duration position) {
  var frame = 0;
  for (var i = 0; i < recording.frames.length; i++) {
    if (recording.frames[i].at > position) break;
    frame = i;
  }
  return frame;
}

/// The index in [TerminalRecording.steps] of the step [frame] is in: the last step
/// starting at or before it; -1 before the first step.
int stepOf(TerminalRecording recording, int frame) {
  final steps = recording.steps;
  var step = -1;
  for (var i = 0; i < steps.length; i++) {
    if (steps[i] > frame) break;
    step = i;
  }
  return step;
}

/// The playback of [recording] after [action]; [looping] plays again from
/// the beginning instead of ending. A recording with no frames does not
/// move.
PlaybackState reducePlayback(
  TerminalRecording recording,
  PlaybackState state,
  PlaybackAction action, {
  bool looping = false,
}) {
  if (recording.frames.isEmpty) return const PlaybackState();
  final end = recording.duration;
  PlaybackState at(Duration position, {required bool isPlaying}) {
    final clamped = position < Duration.zero
        ? Duration.zero
        : position > end
        ? end
        : position;
    return PlaybackState(
      position: clamped,
      frame: frameAt(recording, clamped),
      isPlaying: isPlaying,
    );
  }

  PlaybackState toFrame(int frame) =>
      at(recording.frames[frame].at, isPlaying: false);

  switch (action) {
    case PlaybackPlay():
      return state.isEnded || state.position >= end
          ? at(Duration.zero, isPlaying: true)
          : state.copyWith(isPlaying: true);
    case PlaybackPause():
      return state.copyWith(isPlaying: false);
    case PlaybackSeek(:final position):
      return at(position, isPlaying: state.isPlaying);
    case PlaybackRestart():
      return at(Duration.zero, isPlaying: true);
    case PlaybackNextStep():
      final steps = recording.steps;
      final next = steps.where((frame) => frame > state.frame);
      return next.isEmpty
          ? toFrame(recording.frames.length - 1).copyWith(isEnded: true)
          : toFrame(next.first);
    case PlaybackPreviousStep():
      final before = recording.steps.where((frame) => frame < state.frame);
      return toFrame(before.isEmpty ? 0 : before.last);
    case PlaybackTick(:final elapsed):
      if (!state.isPlaying) return state;
      final position = state.position + elapsed;
      if (position < end) return at(position, isPlaying: true);
      if (looping && end > Duration.zero) {
        return at(
          Duration(microseconds: position.inMicroseconds % end.inMicroseconds),
          isPlaying: true,
        );
      }
      return at(end, isPlaying: false).copyWith(isEnded: true);
  }
}
