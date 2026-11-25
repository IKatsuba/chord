import 'package:meta/meta.dart';

import '../foundation/item_extents.dart';
import '../foundation/notifier.dart';
import '../foundation/scroll_state.dart';

/// What a list gives the controller attached to it: where its items are.
abstract interface class ScrollClient {
  /// Row of the item's first row in the content.
  int itemTop(int index);

  /// Rows the item takes.
  int itemRows(int index);

  /// The item at [row] of the content; -1 when there is none.
  int itemAtRow(int row);

  /// A step moved the view: the list needs a new frame.
  void scrollChanged();
}

/// Where a scrolling list is, and the steps that move it.
class ScrollController extends ChangeNotifier {
  /// A controller; [initialOffset] is for [Follow.none], since a
  /// [Follow.bottom] list starts at the bottom.
  ScrollController({this.follow = Follow.none, int initialOffset = 0})
    : _state = ScrollState.initial(follow, top: initialOffset);

  /// Whether the list keeps its end in sight as it grows.
  final Follow follow;

  ScrollState _state;
  ScrollClient? _client;
  bool _changedInLayout = false;
  bool _notifying = false;
  int _explicitScrollEpoch = 0;

  /// Counts explicit scroll commands, including clamped ones, for projection.
  @internal
  int get explicitScrollEpoch => _explicitScrollEpoch;
  final List<ScrollState Function(ScrollState)> _queued = [];

  /// The item at the view's top row while not following, kept across
  /// lists so one attached again comes back on the same item.
  @internal
  ListAnchor? anchor;

  /// The measured heights of the items of the list last attached, kept
  /// across lists so one built again over this controller measures only
  /// the items whose version changed while it was away.
  @internal
  final ItemExtents itemExtents = ItemExtents();

  /// The follow rule's state, as the list last measured and the steps moved.
  ScrollState get state => _state;

  /// Every item's rows at the list's width; zero until attached.
  int get contentRows => _state.content;

  /// The rows the list has.
  int get viewRows => _state.view;

  /// Rows above the view.
  int get offset => _state.offset;

  /// Rows below the view.
  int get rowsBelow => _state.rowsBelow;

  /// [Follow.bottom] only: the view shows the end and keeps it.
  bool get isFollowing => _state.following;

  /// [Follow.bottom] only: [markNews] was called since the view left the end.
  bool get hasNews => _state.news;

  /// The item at the view's top row; -1 when empty.
  int get firstVisible => _visibleAt(offset);

  /// The item at the view's last row; -1 when empty.
  int get lastVisible {
    final end = offset + viewRows;
    return _visibleAt((end < contentRows ? end : contentRows) - 1);
  }

  int _visibleAt(int row) {
    final client = _client;
    if (client == null || viewRows <= 0 || contentRows <= 0 || row < 0) {
      return -1;
    }
    return client.itemAtRow(row);
  }

  /// Row of the item's first row in the content.
  int itemTop(int index) => _requireClient().itemTop(index);

  /// Rows the item takes at the list's width.
  int itemRows(int index) => _requireClient().itemRows(index);

  ScrollClient _requireClient() =>
      _client ?? (throw StateError('The ScrollController is not attached.'));

  /// Scrolls up a page: the view less two rows.
  void pageUp() => _step(ScrollStep.pageUp);

  /// Scrolls down a page.
  void pageDown() => _step(ScrollStep.pageDown);

  /// Scrolls up a row.
  void lineUp() => _step(ScrollStep.lineUp);

  /// Scrolls down a row.
  void lineDown() => _step(ScrollStep.lineDown);

  /// Scrolls to the first row.
  void toTop() => _step(ScrollStep.top);

  /// Scrolls to the end; with [Follow.bottom] follows again and clears news.
  void toBottom() => _step(ScrollStep.bottom);

  /// Puts row [offset] at the top, clamped; a move off the end stops
  /// following.
  void jumpTo(int offset) {
    checkNotDisposed();
    _explicitScrollEpoch++;
    _mutate((s) => reduceJump(s, offset, follow));
  }

  /// Puts row [ListAnchor.rowsInto] of item [ListAnchor.index] at the top,
  /// clamped, as [jumpTo] does: a row inside an item, such as a call's own
  /// box in an entry, rather than the item's first. The list keeps that row
  /// on top while it does not follow, as heights above it change.
  void jumpToAnchor(ListAnchor anchor) =>
      jumpTo(itemTop(anchor.index) + anchor.rowsInto);

  /// Freezes the current offset and following until [release].
  void hold() => _mutate(reduceHeld);

  /// Ends a hold; fitting content normalizes, overflow keeps its current top.
  void release() => _mutate((state) => reduceReleased(state, follow));

  /// Something new arrived below; a no-op while following or with
  /// [Follow.none].
  void markNews() => _mutate((s) => reduceNews(s, follow));

  void _step(ScrollStep step) {
    checkNotDisposed();
    _explicitScrollEpoch++;
    _mutate((s) => reduceScrolled(s, step, follow));
  }

  void _mutate(ScrollState Function(ScrollState) reduce) {
    checkNotDisposed();
    if (_notifying) {
      _queued.add(reduce);
      return;
    }
    final next = reduce(_state);
    if (next == _state) return;
    _dropStaleAnchor(next);
    _state = next;
    _client?.scrollChanged();
    notifyListeners();
  }

  // Detached, there are no heights to read a new top against, so a step
  // that moves the view drops the anchor and its rows win on the next
  // attach; one that does not move it keeps the anchor.
  void _dropStaleAnchor(ScrollState next) {
    if (_client != null) return;
    if (next.top != _state.top || next.following != _state.following) {
      anchor = null;
    }
  }

  bool _renotify = false;

  /// Calls the listeners. Called while they are being called, it notifies
  /// once more after the round instead of from inside it.
  @override
  void notifyListeners() {
    checkNotDisposed();
    if (_notifying) {
      _renotify = true;
      return;
    }
    _notifying = true;
    try {
      // Rounds are drained in a loop, so a listener that steps on every
      // round never deepens the stack.
      var again = true;
      while (again && !isDisposed) {
        super.notifyListeners();
        // A listener that disposed the controller ends the work queued.
        if (isDisposed) break;
        again = _renotify;
        _renotify = false;
        if (_queued.isEmpty) continue;
        var next = _state;
        for (final reduce in _queued) {
          next = reduce(next);
        }
        _queued.clear();
        if (next == _state) continue;
        _dropStaleAnchor(next);
        _state = next;
        _client?.scrollChanged();
        again = true;
      }
    } finally {
      _notifying = false;
      _renotify = false;
      _queued.clear();
    }
  }

  /// Drops queued steps and the attached list with the listeners.
  @override
  void dispose() {
    _queued.clear();
    _client = null;
    anchor = null;
    itemExtents.dispose();
    super.dispose();
  }

  /// Binds this controller to the list [client]; one list at a time.
  @internal
  void attach(ScrollClient client) {
    checkNotDisposed();
    if (_client != null && !identical(_client, client)) {
      throw StateError('A ScrollController can drive only one list at once.');
    }
    _client = client;
  }

  /// Lets go of [client], when it is the attached list.
  @internal
  void detach(ScrollClient client) {
    if (identical(_client, client)) _client = null;
  }

  /// Sets the state from the list's layout without notifying, since
  /// listeners are never called during layout; returns whether it changed.
  @internal
  bool setFromLayout(ScrollState next) {
    checkNotDisposed();
    if (next == _state) return false;
    _state = next;
    _changedInLayout = true;
    return true;
  }

  /// Notifies, after layout, when layout changed the state.
  @internal
  void notifyAfterLayout() {
    if (!_changedInLayout || isDisposed) return;
    _changedInLayout = false;
    notifyListeners();
  }
}
