import 'package:chord_tui/chord_tui.dart';

/// How long a step's frame stays before the next, at least: recordings are
/// made at chord's own speed, which a visitor cannot read.
const stepHold = Duration(milliseconds: 1500);

/// [recording] retimed for a visitor: every labelled frame holds at least
/// [hold] before the next one, and every frame after it moves later by the
/// same amount. Frames, rows and labels are unchanged.
TerminalRecording paced(
  TerminalRecording recording, {
  Duration hold = stepHold,
}) {
  final frames = recording.frames;
  var shift = Duration.zero;
  final out = <TerminalRecordingFrame>[];
  for (var i = 0; i < frames.length; i++) {
    final frame = frames[i];
    out.add(
      TerminalRecordingFrame(
        at: frame.at + shift,
        rows: frame.rows,
        label: frame.label,
      ),
    );
    if (frame.label != null && i + 1 < frames.length) {
      final gap = frames[i + 1].at - frame.at;
      if (gap < hold) shift += hold - gap;
    }
  }
  return TerminalRecording(
    cols: recording.cols,
    rows: recording.rows,
    frames: out,
  );
}
