/// The recordings `tool/screenshots.dart` writes beside its pictures: each
/// shot's screens as it played, frame by frame, in the version 1 format
/// `TerminalRecording.fromJson` reads.
library;

import 'dart:convert';

import 'package:chord_tui/chord_tui.dart' show truncate;

/// The sizes each shot is recorded at: the rooms the site gives a
/// recording in a 120x40 and an 80x24 window.
const recordingSizes = [(cols: 120, rows: 36), (cols: 80, rows: 20)];

/// The file under docs/images a shot's recording at a size is written to.
String recordingName(String shot, ({int cols, int rows}) size) =>
    '$shot.${size.cols}x${size.rows}.rec.json';

/// The rows of a `capture-pane -p -e` pane, exactly [rows] of them.
List<String> paneRows(String pane, int rows) {
  final lines = pane.split('\n');
  // capture-pane ends its last row with a newline of its own.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return [for (var i = 0; i < rows; i++) i < lines.length ? lines[i] : ''];
}

/// A recording being made: frames that differ from the one before, each at
/// its time, the first after a step labelled with it.
class RecordingWriter {
  /// A recording of a [cols] by [rows] pane.
  RecordingWriter(this.cols, this.rows);

  /// The pane's width.
  final int cols;

  /// The pane's height.
  final int rows;

  final _frames = <Map<String, Object?>>[];
  final _pending = <String>[];
  List<String>? _last;

  /// How many frames are kept.
  int get length => _frames.length;

  /// Marks a step: its [label] goes on the next frame that differs.
  void step(String label) => _pending.add(label);

  /// Takes [pane] as the screen at [at], unless it is the screen before.
  void add(Duration at, String pane) {
    final next = paneRows(pane, rows);
    final last = _last;
    if (last != null && _same(last, next)) return;
    _last = next;
    _frames.add({
      'at': at.inMilliseconds,
      'rows': next,
      'label': _pending.isEmpty ? null : _pending.join(' · '),
    });
    _pending.clear();
  }

  /// The recording as JSON.
  String toJson() =>
      jsonEncode({'version': 1, 'cols': cols, 'rows': rows, 'frames': _frames});
}

bool _same(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return a.length == b.length;
}

/// A step's label, cut to [width] cells with `…`, graphemes whole.
String cutLabel(String label, {int width = 40}) => truncate(label, width);
