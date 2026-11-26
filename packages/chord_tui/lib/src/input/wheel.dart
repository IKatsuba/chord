import '../foundation/geometry.dart';
import 'keys.dart';

/// [events] with each run of adjacent wheel reports that share a cell, the
/// modifiers and a direction merged into one report carrying their summed
/// [MouseEvent.scrollDelta].
///
/// A terminal hands a fast wheel or trackpad flick over as many reports in
/// one read. Routing each one needs current geometry, and every scroll step
/// dirties the tree, so a batch would pay one build and layout per report;
/// merged, it pays one. Reports that differ in cell, modifiers or direction,
/// or that anything else separates, stay apart, so order is kept.
List<InputEvent> coalesceWheel(List<InputEvent> events) {
  if (events.length < 2) return events;
  final merged = <InputEvent>[];
  for (final event in events) {
    final last = merged.isEmpty ? null : merged.last;
    if (event is MouseEvent && last is MouseEvent && _sameRun(last, event)) {
      merged[merged.length - 1] = MouseEvent(
        MouseEventKind.wheel,
        position: last.position,
        scrollDelta: Offset(
          last.scrollDelta.x + event.scrollDelta.x,
          last.scrollDelta.y + event.scrollDelta.y,
        ),
        shift: last.shift,
        alt: last.alt,
        ctrl: last.ctrl,
      );
    } else {
      merged.add(event);
    }
  }
  return merged.length == events.length ? events : merged;
}

bool _sameRun(MouseEvent a, MouseEvent b) =>
    a.kind == MouseEventKind.wheel &&
    b.kind == MouseEventKind.wheel &&
    a.position == b.position &&
    a.shift == b.shift &&
    a.alt == b.alt &&
    a.ctrl == b.ctrl &&
    a.scrollDelta.x.sign == b.scrollDelta.x.sign &&
    a.scrollDelta.y.sign == b.scrollDelta.y.sign;
