import 'package:chord_tui/chord_tui.dart';

import 'permission.dart';

/// The original scroll keys handed to an overflowing active request.
const permissionScrollSteps = {
  'pageup': ScrollStep.pageUp,
  'shift+pageup': ScrollStep.pageUp,
  'pagedown': ScrollStep.pageDown,
  'shift+pagedown': ScrollStep.pageDown,
  'shift+up': ScrollStep.lineUp,
  'shift+down': ScrollStep.lineDown,
  'home': ScrollStep.top,
  'shift+home': ScrollStep.top,
  'end': ScrollStep.bottom,
  'shift+end': ScrollStep.bottom,
};

/// The request's physical offset and the room supplied by its box.
class PermissionScroll extends ChangeNotifier {
  int _top = 0;
  int _total = 0;
  int _room = 0;

  /// Whether request content exceeds its allocated physical room.
  bool get overflows => _total > _room;

  /// The offset clamped to the current request and room.
  int get top => _top;

  /// Settles geometry during the box's build without notifying listeners.
  void configure(int total, int room) {
    _total = total;
    _room = room;
    _top = requestView(total, room, _top).top;
  }

  /// Moves by an original request step, without passing over rows.
  void step(ScrollStep step) {
    final next = requestStep(step, _total, _room, _top);
    if (next == _top) return;
    _top = next;
    notifyListeners();
  }
}
