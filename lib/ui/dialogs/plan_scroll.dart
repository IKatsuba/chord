import 'package:chord_tui/chord_tui.dart';

import 'permission.dart';

/// Where an overflowing plan Note's view starts, as the original's
/// PlanBox keeps its `top`: following the cursor, the Note's tail, until
/// the page keys move it, and back to the tail when the note is typed.
class PlanNoteScroll extends ChangeNotifier {
  // None follows the tail; a row once paged, kept as the original keeps it
  // and clamped only where it is read, so a room that grows and shrinks
  // back finds it where it was.
  int? _top;
  int _total = 0;
  int _room = 0;

  /// Whether the Note is taller than its room.
  bool get overflows => _total > _room;

  /// Where the view is asked to start: the row paged to, or past the
  /// Note's end while it follows the tail; [requestView] clamps it.
  int get at => _top ?? _total;

  /// The view's first row, clamped to the Note and room last laid out.
  int get top => requestView(_total, _room, at).top;

  /// Settles the Note's lines and room during the box's build, without
  /// notifying listeners.
  void configure(int total, int room) {
    _total = total;
    _room = room;
  }

  /// Moves by one of the original's request steps.
  void step(ScrollStep step) {
    final at = _top == null || _top! > _total ? _total : _top!;
    final was = top;
    _top = requestStep(step, _total, _room, at);
    if (top != was) notifyListeners();
  }

  /// Typing brings the view back to the cursor.
  void follow() {
    if (_top == null) return;
    _top = null;
    notifyListeners();
  }
}
