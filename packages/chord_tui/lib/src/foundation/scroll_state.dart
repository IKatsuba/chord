import 'package:meta/meta.dart';

/// The item at a row of a list, and how many rows into it that row is.
@immutable
class ListAnchor {
  /// The anchor at row [rowsInto] of item [index].
  const ListAnchor(this.index, this.rowsInto);

  /// The item.
  final int index;

  /// How many of the item's rows are above the anchored row.
  final int rowsInto;

  @override
  bool operator ==(Object other) =>
      other is ListAnchor && other.index == index && other.rowsInto == rowsInto;

  @override
  int get hashCode => Object.hash(index, rowsInto);

  @override
  String toString() => 'ListAnchor($index, $rowsInto)';
}

/// Whether a list keeps its end in sight as it grows.
enum Follow {
  /// The view stays where it is.
  none,

  /// The view follows the last row while it is at the bottom.
  bottom,
}

/// One step a key takes a scrolling view by.
enum ScrollStep {
  /// Up by a page.
  pageUp,

  /// Down by a page.
  pageDown,

  /// Up by a row.
  lineUp,

  /// Down by a row.
  lineDown,

  /// To the first row.
  top,

  /// To the last row.
  bottom,
}

/// Where a scrolling view is, in rows: the follow rule's state.
/// A hold freezes the current offset independently of the input mechanism.
@immutable
class ScrollState {
  /// A state with the given counts.
  const ScrollState({
    this.content = 0,
    this.view = 0,
    this.top = 0,
    this.following = false,
    this.news = false,
    this.held = false,
  });

  /// The state a list starts in before it is measured.
  factory ScrollState.initial(Follow follow, {int top = 0}) =>
      follow == Follow.bottom
      ? const ScrollState(following: true)
      : ScrollState(top: top < 0 ? 0 : top);

  /// Rows the content takes, as last measured.
  final int content;

  /// Rows the view has.
  final int view;

  /// Rows above the view while not following; unused while following.
  final int top;

  /// The view shows the content's end: all of it, from the top, while it
  /// fits, and its bottom on the view's once it does not.
  final bool following;

  /// Something new arrived since the view left the end.
  final bool news;

  /// Following is paused until the current interaction releases its hold.
  final bool held;

  /// The furthest the view goes down: its bottom on the content's.
  int get bottomTop => content > view ? content - view : 0;

  /// Whether the content fits in the view.
  bool get fits => content <= view;

  /// Rows above the view, following or not.
  int get offset => following ? bottomTop : top;

  /// Rows below the view.
  int get rowsBelow {
    final below = content - offset - view;
    return below > 0 ? below : 0;
  }

  /// One page: the view less two rows, so a line of the last page stays.
  int get pageRows => view - 2 > 1 ? view - 2 : 1;

  ScrollState _copy({
    int? content,
    int? view,
    int? top,
    bool? following,
    bool? news,
    bool? held,
  }) => ScrollState(
    content: content ?? this.content,
    view: view ?? this.view,
    top: top ?? this.top,
    following: following ?? this.following,
    news: news ?? this.news,
    held: held ?? this.held,
  );

  @override
  bool operator ==(Object other) =>
      other is ScrollState &&
      other.content == content &&
      other.view == view &&
      other.top == top &&
      other.following == following &&
      other.news == news &&
      other.held == held;

  @override
  int get hashCode => Object.hash(content, view, top, following, news, held);

  @override
  String toString() =>
      'ScrollState(content: $content, view: $view, top: $top, '
      'following: $following, news: $news, held: $held)';
}

/// The end of the content: followed, or for [Follow.none] its last row.
ScrollState _atBottom(ScrollState s, Follow follow) {
  if (s.held) {
    return !s.following && s.top == s.bottomTop && !s.news
        ? s
        : s._copy(following: false, top: s.bottomTop, news: false);
  }
  if (follow == Follow.bottom) {
    return s.following && !s.news ? s : s._copy(following: true, news: false);
  }
  return s.top == s.bottomTop ? s : s._copy(top: s.bottomTop);
}

/// The list measured [content] rows in a view of [view]; [top] is the row to
/// keep at the top once a relayout has moved it.
///
/// Returns [s] itself when nothing changed, so a caller can skip notifying.
ScrollState reduceMeasured(
  ScrollState s, {
  required int content,
  required int view,
  int? top,
  required Follow follow,
}) {
  if (content == s.content && view == s.view && (top == null || top == s.top)) {
    return s;
  }
  final next = s._copy(content: content, view: view);
  if (next.fits && !next.held) return _atBottom(next, follow);
  if (next.following) return next;
  final to = top ?? s.top;
  final clamped = to > next.bottomTop ? next.bottomTop : (to < 0 ? 0 : to);
  return clamped == next.top ? next : next._copy(top: clamped);
}

/// A key moved the view by [step].
ScrollState reduceScrolled(ScrollState s, ScrollStep step, Follow follow) {
  if (step == ScrollStep.bottom) return _atBottom(s, follow);
  if (s.fits) return s;
  final from = s.offset;
  final by = switch (step) {
    ScrollStep.pageUp => -s.pageRows,
    ScrollStep.pageDown => s.pageRows,
    ScrollStep.lineUp => -1,
    ScrollStep.lineDown => 1,
    ScrollStep.top => -from,
    ScrollStep.bottom => 0,
  };
  return _moved(s, from, from + by, by > 0, follow);
}

/// The view was moved to row [to], clamped to the content.
ScrollState reduceJump(ScrollState s, int to, Follow follow) {
  if (s.fits) return s;
  final from = s.offset;
  // Reaching the end is a move down, S4, even from the end itself.
  return _moved(s, from, to, to > from || to >= s.bottomTop, follow);
}

ScrollState _moved(
  ScrollState s,
  int from,
  int target,
  bool down,
  Follow follow,
) {
  final bottom = s.bottomTop;
  final to = target > bottom ? bottom : (target < 0 ? 0 : target);
  if (down) {
    if (s.following) return s;
    return to >= bottom ? _atBottom(s, follow) : s._copy(top: to);
  }
  if (to == from && !s.following) return s;
  return s._copy(following: false, top: to);
}

/// Holds the current offset, disabling following even while content fits.
ScrollState reduceHeld(ScrollState s) => s.held
    ? s
    : s._copy(
        held: true,
        following: false,
        top: s.offset,
        news: s.following ? false : s.news,
      );

/// Releases a hold; only fitting content normalizes its follow policy here.
ScrollState reduceReleased(ScrollState s, Follow follow) {
  if (!s.held) return s;
  final released = s._copy(held: false);
  return released.fits ? _atBottom(released, follow) : released;
}

/// Something new arrived: news while the view is off the end.
ScrollState reduceNews(ScrollState s, Follow follow) =>
    follow == Follow.none || s.following || s.news ? s : s._copy(news: true);
