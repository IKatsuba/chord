/// Where a scrollbar's thumb sits on its track, and the offset a dragged
/// thumb asks for: plain arithmetic, apart from the widget that draws it.
library;

/// A scrollbar thumb: its first row on the track and how many rows it takes.
typedef ScrollbarThumb = ({int top, int length});

/// The thumb on a track of [track] rows for a list showing [view] of
/// [content] rows, [offset] rows down; null when the content fits, or there
/// is no track.
///
/// Its length is `track × view / content`, rounded, at least 1; its top is
/// `(track − length) × offset / (content − view)`, rounded.
ScrollbarThumb? scrollbarThumb({
  required int track,
  required int view,
  required int content,
  required int offset,
}) {
  if (track <= 0 || view <= 0 || content <= view) return null;
  final length = (track * view / content).round().clamp(1, track);
  final travel = content - view;
  final top = ((track - length) * offset.clamp(0, travel) / travel).round();
  return (top: top, length: length);
}

/// The list offset that puts the thumb's top on row [top] of the track, as
/// [scrollbarThumb] measures it; 0 when the thumb cannot move.
int scrollbarOffsetFor({
  required int top,
  required int track,
  required int view,
  required int content,
}) {
  final thumb = scrollbarThumb(
    track: track,
    view: view,
    content: content,
    offset: 0,
  );
  if (thumb == null || thumb.length >= track) return 0;
  final room = track - thumb.length;
  return (top.clamp(0, room) * (content - view) / room).round();
}
