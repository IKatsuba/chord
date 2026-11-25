import 'dart:async';
import 'dart:convert';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart' show ChangeNotifier, stripAnsi;

/// The window's policy over the framework's logical range.
enum SelectionKind { none, dragging, shown, copying }

/// Selection policy without geometry, widgets or an editable caret.
class Selection {
  const Selection.none()
    : kind = SelectionKind.none,
      wasFollowing = false,
      moved = false;
  const Selection.dragging({required this.wasFollowing, this.moved = false})
    : kind = SelectionKind.dragging;
  const Selection.shown()
    : kind = SelectionKind.shown,
      wasFollowing = false,
      moved = false;
  const Selection.copying()
    : kind = SelectionKind.copying,
      wasFollowing = false,
      moved = false;
  final SelectionKind kind;
  final bool wasFollowing, moved;
}

/// Starts a fresh drag at the current follow rule.
Selection pressed(bool following) =>
    Selection.dragging(wasFollowing: following);

/// Records even an explicit scroll that was clamped at an edge.
Selection scrolled(Selection selection) =>
    selection.kind == SelectionKind.dragging
    ? Selection.dragging(wasFollowing: selection.wasFollowing, moved: true)
    : selection;

/// Ends a drag and says whether its former following rule may resume.
({Selection selection, bool follow}) released(
  Selection selection,
  String text,
) => (
  selection: text.isEmpty ? const Selection.none() : const Selection.shown(),
  follow:
      selection.kind == SelectionKind.dragging &&
      selection.wasFollowing &&
      !selection.moved,
);

/// Only a shown range can begin a new selection copy.
bool copyable(Selection selection) => selection.kind == SelectionKind.shown;

/// An adapter reports terminal transmission, confirmed host copy, or failure.
enum CopyResultKind { sent, copied, failed }

/// An adapter outcome; the coordinator counts the captured text itself.
class CopyResult {
  const CopyResult.sent() : kind = CopyResultKind.sent, reason = null;
  const CopyResult.copied() : kind = CopyResultKind.copied, reason = null;
  const CopyResult.failed(this.reason) : kind = CopyResultKind.failed;
  final CopyResultKind kind;
  final String? reason;
}

/// Writes only while its cancellation/ownership token remains live.
typedef Copy =
    FutureOr<CopyResult> Function(
      String text,
      CancellationToken cancellationToken,
    );

/// Maximum UTF-8 payload accepted before any adapter is called.
const copyByteLimit = 8 * 1024 * 1024;

/// Bound for an adapter that has not settled; synchronous writes do not wait.
const copyBound = Duration(milliseconds: 1200);

/// Successful and code-origin notes live independently of the highlight.
const copyNoteLifetime = Duration(milliseconds: 3000);

/// A sanitized one-line reason suitable for the terminal status row.
String copyReason(Object? error) {
  final message = stripAnsi(error?.toString() ?? '')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return message.isEmpty ? 'no clipboard to write to' : message;
}

/// Original selection-note wording, with sent distinct from confirmed copied.
String copyNote(
  CopyResult result,
  int chars, {
  bool block = false,
}) => switch (result.kind) {
  CopyResultKind.sent => "sent $chars chars to the terminal's clipboard",
  CopyResultKind.copied => 'copied $chars chars to clipboard',
  CopyResultKind.failed =>
    'could not copy: ${copyReason(result.reason)}${block ? '' : ' · ctrl + c to try again'}',
};

/// One current feedback note; its ID protects against an older expiry.
class CopyNote {
  const CopyNote(
    this.id,
    CopyResult this.result,
    this.chars, {
    this.block = false,
  }) : notice = null;
  const CopyNote.notice(this.id, String this.notice)
    : result = null,
      chars = 0,
      block = true;
  final int id, chars;
  final CopyResult? result;
  final String? notice;
  final bool block;
  bool get failed => result?.kind == CopyResultKind.failed;
  String get text => notice ?? copyNote(result!, chars, block: block);
}

/// One window's selection policy and copy generations, independent of widgets.
class SelectionCopies extends ChangeNotifier {
  SelectionCopies({required Copy copy, required Object session})
    : this._(copy, session);

  SelectionCopies._(this._copy, this._session);
  final Copy _copy;
  Object _session;
  Selection _selection = const Selection.none();
  CopyNote? _note;
  int _epoch = 0, _generation = 0, _noteId = 0;
  CancellationToken? _pending;
  bool _pendingSelection = false;
  Timer? _expiry;

  Selection get selection => _selection;
  CopyNote? get note => _note;
  int get epoch => _epoch;

  void _cancelCopy() {
    _generation++;
    final pending = _pending;
    _pending = null;
    pending?.cancel();
  }

  void _clearNote() {
    _expiry?.cancel();
    _expiry = null;
    _note = null;
  }

  /// A session replacement releases all old copies, notes and logical policy.
  void replaceSession(Object session) {
    if (isDisposed || _session == session) return;
    _cancelCopy();
    _clearNote();
    _session = session;
    _epoch++;
    _selection = const Selection.none();
    notifyListeners();
  }

  /// Starts a new range, superseding any copy and previous copy note.
  void press(bool following) {
    if (isDisposed) return;
    _cancelCopy();
    _clearNote();
    _epoch++;
    _selection = pressed(following);
    notifyListeners();
  }

  /// Explicit transcript scrolling counts even when its offset did not move.
  void scroll() {
    if (isDisposed) return;
    final next = scrolled(_selection);
    if (identical(next, _selection)) return;
    _selection = next;
    notifyListeners();
  }

  /// Settles release or cancellation; callers own the corresponding scroll hold.
  bool release(String text) {
    if (isDisposed) return false;
    final next = released(_selection, text);
    _selection = next.selection;
    notifyListeners();
    return next.follow;
  }

  /// Clears a range without destroying a code-origin note or in-flight copy.
  bool clear() {
    if (isDisposed) return false;
    final follow = released(_selection, '').follow;
    _epoch++;
    if (_pendingSelection) _cancelCopy();
    _selection = const Selection.none();
    if (_note case final note? when note.failed && !note.block) _clearNote();
    notifyListeners();
    return follow;
  }

  /// Captures an already-synchronized current range before invoking the adapter.
  void copySelection(String text, {required bool auto}) {
    if (isDisposed || !copyable(_selection) || text.isEmpty) return;
    _selection = const Selection.copying();
    _start(text, auto: auto, block: false);
  }

  /// Copies nonempty code without letting an empty block supersede feedback.
  void copyBlock(String text) {
    if (isDisposed || text.isEmpty) return;
    if (_selection.kind == SelectionKind.copying) {
      _selection = const Selection.shown();
    }
    _start(text, auto: false, block: true);
  }

  /// Empty catalog feedback shares the current guarded note expiry owner.
  void noCodeBlock() {
    if (isDisposed) return;
    _showNote(
      CopyNote.notice(++_noteId, 'No code block to pick'),
      expires: true,
    );
  }

  void _showNote(CopyNote note, {required bool expires}) {
    _expiry?.cancel();
    _expiry = null;
    _note = note;
    if (expires) {
      _expiry = Timer(copyNoteLifetime, () {
        if (!isDisposed && _note?.id == note.id) {
          _note = null;
          _expiry = null;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  bool _owns(int generation, Object session, CancellationToken token) =>
      !isDisposed &&
      _generation == generation &&
      _session == session &&
      identical(_pending, token);

  void _start(String text, {required bool auto, required bool block}) {
    _cancelCopy();
    _clearNote();
    final generation = _generation, session = _session, epoch = _epoch;
    final token = CancellationToken();
    final chars = text.characters.length;
    _pending = token;
    _pendingSelection = !block;
    notifyListeners();
    if (!_owns(generation, session, token)) return;

    void finish(CopyResult result) {
      if (!_owns(generation, session, token)) return;
      _pending = null;
      if (!block &&
          (_epoch != epoch || _selection.kind != SelectionKind.copying)) {
        return;
      }
      if (!block) {
        _selection = !auto && result.kind != CopyResultKind.failed
            ? const Selection.none()
            : const Selection.shown();
      }
      final note = CopyNote(++_noteId, result, chars, block: block);
      _showNote(note, expires: block || !note.failed);
    }

    try {
      if (utf8.encode(text).length > copyByteLimit) {
        finish(const CopyResult.failed('too large to copy'));
        return;
      }
      final result = _copy(text, token);
      if (result is Future<CopyResult>) {
        result
            .asCancellable(token)
            .timeout(
              copyBound,
              onTimeout: () {
                token.cancel();
                return const CopyResult.failed('the clipboard did not answer');
              },
            )
            .then(
              finish,
              onError: (Object error) {
                if (!token.isCancelled) {
                  finish(CopyResult.failed(copyReason(error)));
                }
              },
            );
      } else {
        finish(result);
      }
    } catch (error) {
      finish(CopyResult.failed(copyReason(error)));
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _cancelCopy();
    _clearNote();
    super.dispose();
  }
}
