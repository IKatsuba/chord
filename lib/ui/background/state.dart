/// The background's part of the window's state: its view, while open, and
/// the actions that change it, as plain Dart. From the original's
/// `ui/background/state.ts`.
library;

import '../../session/transcript/types.dart';
import 'background.dart' show ItemRef;
import 'view.dart' show noStopHint;

/// The background view, open over the window, with the `❯` on the item
/// [focus] names, or on the first while it names none still listed.
final class BackgroundView {
  const BackgroundView({
    this.focus,
    this.top,
    this.laid,
    this.over = const [],
    this.hint,
    this.stopping,
    this.detail,
  });

  final ItemRef? focus;

  /// The line of all the rows' on top of the frame, for the size [laid] it
  /// was laid out at.
  final int? top;
  final String? laid;

  /// The requests already waiting on the person as it opened, which it
  /// stays over, holding the keys, as the agents list did.
  final List<String> over;

  /// What the hint line says in place of the keys, about the focused
  /// item's stop, until the `❯` moves.
  final String? hint;

  /// The stop `x` last asked for, by its item and a token of its own, while
  /// the `❯` has stayed on that item since: only that stop's answer, if it
  /// comes later, is said.
  final ({ItemRef focus, String token})? stopping;

  /// The monitor whose detail is open in place of the rows, which `↑ ↓`
  /// step from item to item.
  final ItemRef? detail;
}

/// What changes the background view.
sealed class BackgroundAction {
  const BackgroundAction();
}

/// `enter` on the summary line opened the view over the requests [over]
/// already waiting; esc closes it.
final class BackgroundOpened extends BackgroundAction {
  const BackgroundOpened([this.over = const []]);
  final List<String> over;
}

/// The view closed.
final class BackgroundClosed extends BackgroundAction {
  const BackgroundClosed();
}

/// The window took another size: the frame is found again from the `❯`, a
/// tall row from its first line.
final class BackgroundResized extends BackgroundAction {
  const BackgroundResized();
}

/// ↑ ↓ in the view put the `❯` on [focus]; [top] is the line on top of the
/// frame at the size [laid], kept if not given.
final class BackgroundFocused extends BackgroundAction {
  const BackgroundFocused(this.focus, {this.top, this.laid});
  final ItemRef focus;
  final int? top;
  final String? laid;
}

/// `x` asked to stop [focus], which may answer later, under [token].
final class BackgroundStopAsked extends BackgroundAction {
  const BackgroundStopAsked(this.focus, this.token);
  final ItemRef focus;
  final String token;
}

/// The stop [token] asked for could not be made, as [hint] says; said only
/// while the `❯` has stayed on its item since, and no later stop was asked.
final class BackgroundHinted extends BackgroundAction {
  const BackgroundHinted(this.token, this.hint);
  final String token;
  final String hint;
}

/// The agent at [focus] now offers a stop, which an agent that says so only
/// after its announcement can, so a refusal saying it offers none is false.
final class BackgroundStopOffered extends BackgroundAction {
  const BackgroundStopOffered(this.focus);
  final ItemRef focus;
}

/// `enter` on a monitor's row opened its detail.
final class BackgroundDetailOpened extends BackgroundAction {
  const BackgroundDetailOpened(this.focus);
  final ItemRef focus;
}

/// `esc` or `←` in the detail went back to the rows, the `❯` where it was.
final class BackgroundDetailClosed extends BackgroundAction {
  const BackgroundDetailClosed();
}

/// The ids of the requests waiting on the person: permissions, forms and
/// links, and plans not answered yet.
List<String> askedIds(Transcript transcript) => [
  if (transcript.turn case AwaitingPermission(:final permissions))
    for (final wait in permissions) wait.id,
  for (final wait in transcript.asking) wait.id,
  for (final ask in transcript.planAsks)
    if (ask.answer == null) ask.wait.id,
];

/// Whether the background view is on screen: open, and not hidden by a
/// permission or form the session asked since it opened, as every picker
/// is; it comes back as it was once that is answered. Those already waiting
/// as it opened it stays over, the keys its own.
bool backgroundShown(BackgroundView? view, Transcript transcript) =>
    view != null && askedIds(transcript).every(view.over.contains);

/// Whether the list under the prompt has the keys: focused, and the view
/// opened from its summary line not open, which takes them while it is up
/// and hands them to what the session asks while it is hidden.
bool agentsHaveKeys({required bool agentsFocus, BackgroundView? view}) =>
    agentsFocus && view == null;

bool _same(ItemRef? a, ItemRef? b) => a != null && b != null && a == b;

/// [view] after [action]; none while the view is closed.
BackgroundView? reduceBackground(
  BackgroundView? view,
  BackgroundAction action,
) {
  switch (action) {
    case BackgroundOpened(:final over):
      return BackgroundView(over: over);
    case BackgroundClosed():
      return null;
    case BackgroundResized():
      if (view == null || (view.top == null && view.laid == null)) return view;
      return BackgroundView(
        focus: view.focus,
        over: view.over,
        hint: view.hint,
        stopping: view.stopping,
        detail: view.detail,
      );
    case BackgroundFocused(:final focus, :final top, :final laid):
      if (view == null) return view;
      // The hint, and a stop awaiting its answer, stay while the `❯` stays
      // on their item.
      final stays = _same(view.focus, focus);
      // Where in a tall row it is stays with the row, unless a move says.
      final (keptTop, keptLaid) = top != null
          ? (top, laid)
          : stays
          ? (view.top, view.laid)
          : (null, null);
      return BackgroundView(
        focus: focus,
        top: keptTop,
        laid: keptLaid,
        over: view.over,
        hint: stays ? view.hint : null,
        stopping: _same(view.stopping?.focus, focus) ? view.stopping : null,
        // An open detail follows the `❯` to the item it moved to.
        detail: view.detail == null ? null : focus,
      );
    case BackgroundDetailOpened(:final focus):
      if (view == null) return view;
      return BackgroundView(
        focus: focus,
        over: view.over,
        stopping: view.stopping,
        detail: focus,
      );
    case BackgroundDetailClosed():
      if (view?.detail == null) return view;
      return BackgroundView(
        focus: view!.focus,
        top: view.top,
        laid: view.laid,
        over: view.over,
        stopping: view.stopping,
      );
    case BackgroundStopAsked(:final focus, :final token):
      if (view == null) return view;
      return BackgroundView(
        focus: view.focus,
        top: view.top,
        laid: view.laid,
        over: view.over,
        hint: view.hint,
        stopping: (focus: focus, token: token),
        detail: view.detail,
      );
    case BackgroundStopOffered(:final focus):
      if (view == null ||
          view.hint != noStopHint ||
          !_same(view.focus, focus)) {
        return view;
      }
      return BackgroundView(
        focus: view.focus,
        top: view.top,
        laid: view.laid,
        over: view.over,
        stopping: view.stopping,
        detail: view.detail,
      );
    case BackgroundHinted(:final token, :final hint):
      if (view == null || view.stopping?.token != token) return view;
      return BackgroundView(
        focus: view.focus,
        top: view.top,
        laid: view.laid,
        over: view.over,
        hint: hint,
        detail: view.detail,
      );
  }
}
