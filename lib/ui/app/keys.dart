import 'package:chord_tui/chord_tui.dart';

import '../../session/modes.dart';
import '../pickers/state.dart' show settingsSessionInitialized;

import '../dialogs/permission.dart' show askedPermission;
import '../dialogs/permission_scroll.dart';
import '../prompt/commands.dart'
    show CommandItem, LocalSubmitted, SendSubmitted, submitted;
import '../prompt/history.dart' as prompt_history;
import '../prompt/images.dart';
import '../prompt/bash.dart';
import '../prompt/state.dart' show runningShell;
import '../prompt/prompt.dart';
import '../prompt/queue.dart' show sendable;
import '../prompt/search.dart' as search;
import '../shortcuts/bindings.dart' as keymap show actions, KeyContext;
import '../shortcuts/state.dart';
import '../start_state.dart';
import 'state.dart';
import 'selection.dart' show SelectionKind;
import '../background/state.dart'
    show BackgroundClosed, BackgroundDetailClosed, BackgroundOpened, askedIds;

/// The plain state read by one ordered key decision.
final class KeyContext {
  const KeyContext({
    required this.state,
    required this.history,
    required this.rows,
    this.columns = 1,
    this.selection = SelectionKind.none,
    this.picking = false,
    this.canEdit = true,
    this.completing = false,
    this.searchEnabled = true,
    this.splash = false,
    this.takesImages,
    this.home,
    this.submitting = false,
    this.highlighted,
    this.agents = false,
    this.listKeys = false,
    this.onSummary = false,
    this.viewKeys = false,
    this.inDetail = false,
    this.notePages = false,
  });
  final AppState state;
  final prompt_history.History history;
  final int rows;
  final int columns;
  final SelectionKind selection;
  final bool picking;
  final bool canEdit;
  final bool completing;
  final bool searchEnabled;

  /// The startup splash holds the screen in front of the window.
  final bool splash;

  /// Whether the agent takes images in a prompt; unknown until it is up.
  final bool? takesImages;

  /// The person's home, which a `~/` path names.
  final String? home;

  /// Enter is still reading the image paths of a prompt it sends: a
  /// second one sends nothing, nor a later draft ahead of it.
  final bool submitting;

  /// The command the open list highlights, which Enter runs or sends in
  /// the draft's place; none when no list is open.
  final CommandItem? highlighted;

  /// The window has children, or a background, so the list of its agents
  /// or its summary line is under the prompt for ↓ to go into.
  final bool agents;

  /// The list of the window's agents has the keys: ↑ ↓ j k pick, Enter and
  /// Esc go back, `agents:close` closes, and no other key types.
  final bool listKeys;

  /// The list's `❯` is on the background's summary line, which is no
  /// agent: `agents:close` there closes nothing.
  final bool onSummary;

  /// The background view is on screen and has the keys: ↑ ↓ j k move,
  /// Enter opens a detail, `agents:close` stops, Esc closes or goes back.
  final bool viewKeys;

  /// A detail is open in the view, in place of its rows.
  final bool inDetail;

  /// The plan on screen has its `❯` on a Note taller than its room, which
  /// then takes the page keys.
  final bool notePages;
}

/// Whether [key] pages the plan's Note rather than the transcript, as the
/// original's keyCommand: only page up and down, while the plan has the
/// keys and its Note overflows.
bool _pagesNote(String key, KeyContext context) =>
    context.notePages &&
    inputHasKeys(context.state) &&
    askedPlan(context.state.transcript) != null &&
    switch (permissionScrollSteps[key]) {
      ScrollStep.pageUp || ScrollStep.pageDown => true,
      _ => false,
    };

/// One reducer update or effect, played in order by the live window.
sealed class Step {
  const Step();
}

final class Dispatch extends Step {
  const Dispatch(this.action);
  final AppAction action;
}

final class ShowDraft extends Step {
  const ShowDraft(this.text, this.cursor);
  final String text;
  final Cursor cursor;
}

final class HistoryStep extends Step {
  const HistoryStep(this.history);
  final prompt_history.History history;
}

final class Send extends Step {
  const Send(this.text);
  final String text;
}

/// A mode selected by Shift+Tab in the agent's order.
final class SetMode extends Step {
  const SetMode(this.id);
  final String id;
}

/// Dismisses popup state after search recall, before any later key.
final class CloseCompletions extends Step {
  const CloseCompletions();
}

/// Insert the highlighted command and a space.
final class CompleteCommand extends Step {
  const CompleteCommand();
}

/// Runs an already accepted local command, after history and editor reset.
final class RunShellCommand extends Step {
  const RunShellCommand(this.command);
  final String command;
}

/// Stops the session's current local command ahead of agent interruption.
final class StopShellCommand extends Step {
  const StopShellCommand();
}

/// Dispatches the oldest eligible personal row without editing the draft.
final class Steer extends Step {
  const Steer();
}

final class Interrupt extends Step {
  const Interrupt();
}

final class RejectPermission extends Step {
  const RejectPermission(this.id);
  final String id;
}

final class ChoosePermission extends Step {
  const ChoosePermission(this.id, this.optionId);
  final String id;
  final String optionId;
}

final class ScrollRequest extends Step {
  const ScrollRequest(this.step);
  final ScrollStep step;
}

final class ScrollPanel extends Step {
  const ScrollPanel(this.step);
  final ScrollStep step;
}

/// Copies the current synchronized selection without editing the draft.
final class CopySelection extends Step {
  const CopySelection();
}

/// Starts or changes the current framework-issued code target.
final class StartCodePick extends Step {
  const StartCodePick();
}

final class MoveCodePick extends Step {
  const MoveCodePick(this.by);
  final int by;
}

final class CopyCodePick extends Step {
  const CopyCodePick();
}

/// ↑ or ↓ in the list of agents: the pick [by] rows on, the view following.
final class MoveAgent extends Step {
  const MoveAgent(this.by);
  final int by;
}

/// ↑ or ↓ in the background view: the `❯` [by] rows on, or, in a detail,
/// the next item's detail.
final class MoveBackground extends Step {
  const MoveBackground(this.by);
  final int by;
}

/// `agents:close` in the background view: the focused item stops.
final class StopBackground extends Step {
  const StopBackground();
}

/// Enter in the background view: a row's detail, or, in one, its call.
final class GoToCall extends Step {
  const GoToCall();
}

/// A page key in the background view: a detail, or a hint taller than its
/// room, scrolls by [step].
final class ScrollBackground extends Step {
  const ScrollBackground(this.step);
  final ScrollStep step;
}

/// `agents:close` in the list: the picked child closed, or armed first.
final class CloseAgent extends Step {
  const CloseAgent();
}

/// ctrl+x a with no request of the front agent's held: the agent that
/// waits longest on the person, if one does.
final class AttendSession extends Step {
  const AttendSession();
}

final class ShowDraftHeld extends Step {
  const ShowDraftHeld();
}

/// Code insertion follows the original empty-draft policy, without execution.
List<Step> promptSteps(String command, KeyContext context) =>
    context.state.draft.isNotEmpty
    ? [const ShowDraftHeld()]
    : [
        const Dispatch(BashModeAction(true)),
        ShowDraft(command, endOf(command)),
      ];

final class RunCodePick extends Step {
  const RunCodePick();
}

final class EndCodePick extends Step {
  const EndCodePick();
}

/// Semantic actions remain independent of their current key spelling.
enum CodePickCommand { previous, next, copy, run, cancel }

const codePickKeyDescriptions = {
  CodePickCommand.previous: ('up', 'Previous code block'),
  CodePickCommand.next: ('down', 'Next code block'),
  CodePickCommand.copy: ('c', 'Copy picked block'),
  CodePickCommand.run: ('r', 'Put picked block in the prompt'),
  CodePickCommand.cancel: ('esc', 'Stop picking code'),
};

/// The keybindings file's names for the code-pick commands.
const codePickActions = {
  CodePickCommand.previous: 'codeBlock:previous',
  CodePickCommand.next: 'codeBlock:next',
  CodePickCommand.copy: 'codeBlock:copy',
  CodePickCommand.run: 'codeBlock:prompt',
  CodePickCommand.cancel: 'codeBlock:cancel',
};
List<Binding> codePickBindings(
  KeyContext Function() context,
  void Function(List<Step>) play,
) => [
  if (context().picking)
    for (final entry in codePickKeyDescriptions.entries)
      Binding(
        entry.value.$1,
        entry.value.$2,
        () => play(codePickSteps(entry.key, context())),
        id: codePickActions[entry.key],
      ),
];
List<Step> codePickSteps(CodePickCommand command, KeyContext context) =>
    !context.picking
    ? []
    : switch (command) {
        CodePickCommand.previous => [const MoveCodePick(-1)],
        CodePickCommand.next => [const MoveCodePick(1)],
        CodePickCommand.copy => [const CopyCodePick()],
        CodePickCommand.run => [const RunCodePick()],
        CodePickCommand.cancel => [const EndCodePick()],
      };

final class Quit extends Step {
  const Quit();
}

/// ctrl+g: the draft in the user's editor and back.
final class OpenEditor extends Step {
  const OpenEditor();
}

/// ctrl+v: the clipboard's image at the cursor; a [quiet] one, an empty
/// paste's, says nothing when the clipboard holds no image.
final class PasteImage extends Step {
  const PasteImage({this.quiet = false});
  final bool quiet;
}

/// A pasted path to an image file: the image in its place; [draft] is read
/// on both sides of [end], where the paste ended.
final class TakePastedPaths extends Step {
  const TakePastedPaths(this.draft, this.end);
  final String draft;
  final int end;
}

/// Enter on a draft that names image files by path: each read and put in as
/// `[Image #N]` before the prompt goes.
final class SendWithPaths extends Step {
  const SendWithPaths(this.text);
  final String text;
}

/// Whether a pasted image would go into the draft now: ctrl+v's, and an
/// empty bracketed paste's. An image is a prompt's, not a shell command's.
bool takesImagePaste(KeyContext context) =>
    context.canEdit &&
    context.state.search == null &&
    !context.state.bash &&
    !context.state.closing;

/// ctrl+w straight after a held image's placeholder and its space takes
/// them whole, where the textarea's own cut would take the space alone;
/// none elsewhere, where ctrl+w is the textarea's word cut.
List<Step> placeholderCutSteps(KeyContext context) {
  final state = context.state;
  if (!context.canEdit || state.search != null) return [];
  final before = state.draft.substring(0, state.cursor);
  final length = placeholderBefore(before, state.images);
  if (length == 0) return [];
  final text =
      before.substring(0, before.length - length) +
      state.draft.substring(state.cursor);
  final cursor = state.cursor - length;
  return [Dispatch(DraftEditedAction(text, cursor)), ShowDraft(text, cursor)];
}

/// The splash gives way to the window before the agent is up.
final class LeaveSplash extends Step {
  const LeaveSplash();
}

/// Registered app chords; their callbacks feed the same chord to [keySteps].
const windowKeyDescriptions = {
  'tab': 'Complete command',
  'shift+tab': 'Cycle permission mode',
  'ctrl+shift+c': 'Copy selection',
  'ctrl+c': 'Clear draft or quit',
  'ctrl+d': 'Quit on an empty draft',
  'ctrl+x a': 'Answer waiting request',
  'ctrl+x b': 'Pick a code block',
  'esc': 'Interrupt turn or stop command',
  '!': 'Enter bash mode',
  'backspace': 'Leave empty bash prompt',
  'shift+backspace': 'Leave empty bash prompt',
  'ctrl+o': 'Toggle transcript details',
  'ctrl+r': 'Search prompts',
  'ctrl+g': r'Edit the prompt in $EDITOR',
  'ctrl+v': 'Paste an image',
  '?': 'Show shortcuts',
  'pageup': 'Scroll up a page',
  'shift+pageup': 'Scroll up a page',
  'pagedown': 'Scroll down a page',
  'shift+pagedown': 'Scroll down a page',
  'shift+up': 'Scroll up a line',
  'shift+down': 'Scroll down a line',
  'home': 'Scroll to the top',
  'shift+home': 'Scroll to the top',
  'end': 'Scroll to the bottom',
  'shift+end': 'Scroll to the bottom',
};

/// The actual app bindings and the catalog's source of app chord declarations.
List<Binding> windowBindings(
  KeyContext Function() context,
  void Function(List<Step>) play, {
  Binding? selectionCopy,
  List<Binding>? pickedBindings,
}) {
  final picked = pickedBindings ?? codePickBindings(context, play);
  final list = context().listKeys;
  return [
    for (final entry in windowKeyDescriptions.entries)
      // The view's own keys stand in for the window's of the same name.
      if (!(context().viewKeys &&
              backgroundKeyDescriptions.containsKey(entry.key)) &&
          (entry.key != 'esc' || (picked.isEmpty && !list)))
        if (entry.key == 'ctrl+shift+c')
          selectionCopy ?? selectionCopyBinding(context, play)
        else
          Binding(
            entry.key,
            _bindingDescription(entry.key, entry.value, context()),
            () => play(keySteps(Chord.parse(entry.key), context())),
            id: windowAction(entry.key, context()),
          ),
    if (context().state.search != null)
      Binding(
        'enter',
        'Take search match',
        () => play(keySteps(Chord.parse('enter'), context())),
        id: 'historySearch:accept',
      ),
    ...picked,
    if (list)
      for (final MapEntry(:key, value: (id, does))
          in listKeyDescriptions.entries)
        Binding(
          key,
          does,
          () => play(keySteps(Chord.parse(key), context())),
          id: id,
        ),
    if (context().viewKeys)
      for (final MapEntry(:key, value: (id, does))
          in backgroundKeyDescriptions.entries)
        Binding(
          key,
          does,
          () => play(keySteps(Chord.parse(key), context())),
          id: id,
        ),
  ];
}

/// The keys of the background view while it has them, each with its action
/// id where the keybindings file may move it, and its description. Only
/// `agents:close` is rebindable, one action for an agent's close and an
/// item's stop, as in the original.
const backgroundKeyDescriptions = {
  'up': (null, 'Move up in the background'),
  'k': (null, 'Move up in the background'),
  'down': (null, 'Move down in the background'),
  'j': (null, 'Move down in the background'),
  'enter': (null, "Open the item's details"),
  'left': (null, 'Back from the details'),
  'esc': (null, 'Close the background or its details'),
  'x': ('agents:close', 'Stop the focused item'),
  'pageup': (null, 'Scroll the details up a page'),
  'pagedown': (null, 'Scroll the details down a page'),
  'home': (null, 'Scroll the details to the top'),
  'end': (null, 'Scroll the details to the bottom'),
};

/// What a key does while the background view has the keys: it moves, opens
/// a detail, stops, scrolls or goes back; ctrl+c, ctrl+d and ctrl+x a keep
/// their own; every other key does nothing.
List<Step> backgroundSteps(String key, KeyContext context) {
  final state = context.state;
  return switch (key) {
    'up' || 'k' => [const MoveBackground(-1)],
    'down' || 'j' => [const MoveBackground(1)],
    'enter' => [const GoToCall()],
    'x' => [const StopBackground()],
    'pageup' => [const ScrollBackground(ScrollStep.pageUp)],
    'pagedown' => [const ScrollBackground(ScrollStep.pageDown)],
    'home' => [const ScrollBackground(ScrollStep.top)],
    'end' => [const ScrollBackground(ScrollStep.bottom)],
    // Out of a detail, esc and ← go back to the rows; ← on the rows does
    // nothing, and esc there closes the view.
    'left' when context.inDetail => [
      const Dispatch(BackgroundChangedAction(BackgroundDetailClosed())),
    ],
    'escape' => [
      Dispatch(
        BackgroundChangedAction(
          context.inDetail
              ? const BackgroundDetailClosed()
              : const BackgroundClosed(),
        ),
      ),
    ],
    'ctrl+c' =>
      state.quitArmed ? [const Quit()] : [const Dispatch(QuitArmedAction())],
    'ctrl+d' => [const Quit()],
    _ => const <Step>[],
  };
}

/// The keys of the list of agents while it has them, each with its action
/// id where the keybindings file may move it, and its description. Only
/// `agents:close` is rebindable, as in the original.
const listKeyDescriptions = {
  'up': (null, 'Pick the agent above'),
  'k': (null, 'Pick the agent above'),
  'down': (null, 'Pick the agent below'),
  'j': (null, 'Pick the agent below'),
  'enter': (null, 'Write to the picked agent'),
  'esc': (null, 'Back to the picked agent'),
  'x': ('agents:close', 'Close the picked agent'),
};

/// What a key does while the list of agents has the keys: it moves the
/// pick, goes back or closes; ctrl+c, ctrl+d, ctrl+o and the transcript's
/// scrolling keep their own; every other key does nothing, so a stray one
/// never lands in a child's prompt. [keySteps] disarms a close.
List<Step> listSteps(String key, KeyContext context) {
  final state = context.state;
  final steps = switch (key) {
    'up' || 'k' => [const MoveAgent(-1)],
    'down' || 'j' => [const MoveAgent(1)],
    // Enter on the summary line opens the view over the requests waiting.
    'enter' when context.onSummary => [
      Dispatch(
        BackgroundChangedAction(BackgroundOpened(askedIds(state.transcript))),
      ),
    ],
    'enter' || 'escape' => [const Dispatch(AgentsFocusedAction(false))],
    // The summary line is no item: `x` there stops nothing.
    'x' => context.onSummary ? const <Step>[] : [const CloseAgent()],
    'ctrl+c' =>
      state.quitArmed ? [const Quit()] : [const Dispatch(QuitArmedAction())],
    'ctrl+d' => [const Quit()],
    'ctrl+o' => [const Dispatch(ToggleExpandedAction())],
    _ => switch (permissionScrollSteps[key]) {
      final step? => [Dispatch(TranscriptScrolledAction(step))],
      null => const <Step>[],
    },
  };
  return steps;
}

/// The semantic selection action, independent of its current key spelling.
Binding selectionCopyBinding(
  KeyContext Function() context,
  void Function(List<Step>) play, {
  String keys = 'ctrl+shift+c',
}) => Binding(
  keys,
  'Copy selection',
  () => play(selectionCopySteps(context())),
  id: 'selection:copy',
);

/// The keybindings file's action a window key does in [context], by which
/// the file moves it; none for a key no file may move. One key is several
/// actions, each in the context on screen, as the original's contexts.
String? windowAction(String key, KeyContext context) {
  final state = context.state;
  final searching = state.search != null && context.canEdit;
  return switch (key) {
    'tab' when searching => 'historySearch:accept',
    // A list shown takes its keys first, then steering; with neither,
    // tab is no action the file may move.
    'tab' when context.completing => 'autocomplete:accept',
    'tab' when canSteer(context) => 'chat:steer',
    'tab' => null,
    'shift+tab' => 'chat:cycleMode',
    'ctrl+shift+c' => 'selection:copy',
    'ctrl+x a' => 'session:attention',
    'ctrl+x b' => 'codeBlock:pick',
    // Esc leaving the splash is the splash's, and no file moves it.
    'esc' when context.splash => null,
    // The list's Esc goes back, and no file moves it.
    'esc' when context.listKeys => null,
    'esc' when state.shortcuts.help => 'help:dismiss',
    'esc' when searching => 'historySearch:cancel',
    'esc' when context.completing => 'autocomplete:dismiss',
    'esc'
        when askedPermission(state.transcript.turn) != null &&
            !heldBack(state) =>
      'confirm:no',
    'esc' => 'chat:cancel',
    'ctrl+o' => 'app:toggleTranscript',
    'ctrl+r' when searching => 'historySearch:next',
    'ctrl+r' => 'history:search',
    'ctrl+g' => 'chat:externalEditor',
    'ctrl+v' => 'chat:imagePaste',
    '?' => 'help:toggle',
    _ => switch (permissionScrollSteps[key]) {
      ScrollStep.pageUp => 'scroll:pageUp',
      ScrollStep.pageDown => 'scroll:pageDown',
      ScrollStep.lineUp => 'scroll:lineUp',
      ScrollStep.lineDown => 'scroll:lineDown',
      ScrollStep.top => 'scroll:top',
      ScrollStep.bottom => 'scroll:bottom',
      null => null,
    },
  };
}

/// The key [binding] does what it does as: its action's own default key,
/// wherever a keybindings file moved it; its chord when it has no action.
Chord actionChord(Binding binding) {
  final spec = keymap.actions[binding.id];
  return spec == null ? binding.chord : Chord.parse(spec.keys.first);
}

/// A copying range consumes repeats without starting another adapter.
List<Step> selectionCopySteps(KeyContext context) =>
    context.selection == SelectionKind.shown ||
        context.selection == SelectionKind.copying
    ? [const CopySelection()]
    : [];

/// Applies selection policy before the existing focused/modal binding route.
/// Binding-only preview never pretends to consume ordinary printable form input.
bool selectionKeyCapture(
  KeyEvent event, {
  required FocusManager manager,
  required Binding selectionCopy,
  required Binding ordinaryCtrlC,
  required List<Binding> bindings,
  required KeyContext Function() context,
  required void Function() clearSelection,
  void Function()? endPicking,
  List<Binding> pickedBindings = const [],
  bool closing = false,
}) {
  if (closing) return false;
  final kind = context().selection;
  final held = kind == SelectionKind.shown || kind == SelectionKind.copying;
  if (held) {
    final explicit = manager.matchKey(
      event,
      where: (b) => identical(b, selectionCopy),
    );
    if (explicit.kind == KeyBindingMatchKind.exact ||
        explicit.kind == KeyBindingMatchKind.prefix) {
      return explicit.dispatch();
    }
  }
  if (event.combo == KeyCombo.parse('ctrl+c') &&
      manager.pendingChord.isNotEmpty) {
    clearSelection();
    endPicking?.call();
    manager.cancelPendingChord();
    return false;
  }
  if (held && event.combo == KeyCombo.parse('ctrl+c')) {
    return manager
        .matchKey(event, where: (b) => identical(b, ordinaryCtrlC))
        .dispatch();
  }
  bool isStart(Binding binding) =>
      bindings.any((b) => identical(b, binding) && b.id == 'codeBlock:pick');
  final start = manager.matchKey(event, where: isStart);
  if (start.kind == KeyBindingMatchKind.prefix) return start.dispatch();
  if (start.kind == KeyBindingMatchKind.exact) {
    clearSelection();
    return manager.matchKey(event, where: isStart).dispatch();
  }
  if (context().picking) {
    bool isPick(Binding binding) =>
        pickedBindings.any((b) => identical(b, binding));
    final picked = manager.matchKey(event, where: isPick);
    if (picked.kind == KeyBindingMatchKind.prefix) return picked.dispatch();
    if (picked.kind == KeyBindingMatchKind.exact) {
      clearSelection();
      return manager.matchKey(event, where: isPick).dispatch();
    }
  }
  final match = manager.matchKey(event);
  final prefix =
      match.kind == KeyBindingMatchKind.prefix &&
      preservesSelectionPrefix(event);
  final appBinding =
      match.binding != null && bindings.any((b) => identical(b, match.binding));
  final preserve =
      prefix ||
      appBinding &&
          preservesSelection(keySteps(actionChord(match.binding!), context()));
  if (!preserve) {
    clearSelection();
    endPicking?.call();
  }
  return false;
}

/// The decisions for a matched binding, without another chord recognizer.
/// A close armed in the list goes with any key but the close itself, ahead
/// of whatever the key does, as the original disarms before every command.
List<Step> keySteps(Chord press, KeyContext context) {
  final steps = _keySteps(press, context);
  if (context.state.agentCloseArmed == null ||
      (context.listKeys && press.toString() == 'x')) {
    return steps;
  }
  return [const Dispatch(AgentCloseDisarmedAction()), ...steps];
}

List<Step> _keySteps(Chord press, KeyContext context) {
  final state = context.state;
  final key = press.toString();
  // Esc is the splash's one way into the window early, and the window never
  // hears it; every other key goes to the window behind it, as typed there.
  if (context.splash && key == 'escape') return [const LeaveSplash()];
  if (key == 'ctrl+x b') return [const StartCodePick()];
  if (context.picking) {
    final command = switch (key) {
      'up' => CodePickCommand.previous,
      'down' => CodePickCommand.next,
      'c' => CodePickCommand.copy,
      'r' => CodePickCommand.run,
      'escape' => CodePickCommand.cancel,
      _ => null,
    };
    if (command != null) return codePickSteps(command, context);
  }
  if (key == 'ctrl+x a') return attentionSteps(context);
  if (context.viewKeys) return backgroundSteps(key, context);
  if (context.listKeys) return listSteps(key, context);
  if (context.canEdit && !state.closing && !state.shortcuts.help) {
    if (key == 'ctrl+r') {
      if (!context.searchEnabled) return [];
      return [
        Dispatch(
          SearchChangedAction(
            state.search == null
                ? search.emptySearch
                : search.searchedOlder(state.search!, context.history.prompts),
          ),
        ),
      ];
    }
    if (state.search != null) {
      if (!context.searchEnabled) return [];
      if (key == 'escape' || key == 'ctrl+c') {
        return [const Dispatch(SearchChangedAction(null))];
      }
      if (key == 'enter' || key == 'tab') {
        final text = search.matched(state.search!, context.history.prompts);
        return [
          const Dispatch(SearchChangedAction(null)),
          if (text != null) ...[
            HistoryStep(prompt_history.left(context.history)),
            ..._recallSteps(text, state.bash, context.history),
            const CloseCompletions(),
          ],
        ];
      }
    }
  }
  if (context.canEdit && key == '!' && !state.bash && state.draft.isEmpty) {
    return [
      const Dispatch(BashModeAction(true)),
      const ShowDraft('', startCursor),
    ];
  }
  if (context.canEdit &&
      state.bash &&
      state.draft.isEmpty &&
      (key == 'backspace' || key == 'shift+backspace')) {
    return [const Dispatch(BashModeAction(false))];
  }
  if (key == 'shift+tab') {
    if (!settingsSessionInitialized(
      state.start.phase,
      closing: state.closing,
    )) {
      return [];
    }
    final modes = modesFrom(state.agent.configOptions, state.agent.modes);
    final next = modes == null
        ? null
        : nextMode(modes.available, state.pendingMode ?? modes.current);
    return next == null ? [] : [SetMode(next)];
  }
  if (key == 'ctrl+shift+c') {
    return selectionCopySteps(context);
  }
  if (key == 'ctrl+c') {
    if (context.selection == SelectionKind.shown ||
        context.selection == SelectionKind.copying) {
      return [const CopySelection()];
    }
    // A form takes ctrl+c to stop the turn, which takes the form with it,
    // as the original's keyCommand does.
    if (inputHasKeys(state)) return [const Interrupt()];
    if (state.draft.isNotEmpty) {
      return [
        ..._keptLeft(context),
        const Dispatch(DraftClearedAction()),
        const ShowDraft('', startCursor),
      ];
    }
    return state.quitArmed
        ? [const Quit()]
        : [const Dispatch(QuitArmedAction())];
  }
  if (key == 'tab') {
    return canSteer(context) && !context.completing
        ? [const Steer()]
        : [const CompleteCommand()];
  }
  if (key == 'ctrl+d') return state.draft.isEmpty ? [const Quit()] : [];
  if (key == 'escape') {
    if (state.shortcuts.help) {
      return [const Dispatch(ShortcutsChangedAction(HelpClosed()))];
    }
    final wait = askedPermission(state.transcript.turn);
    if (wait != null && !heldBack(state)) return [RejectPermission(wait.id)];
    return runningShell(state.transcript) != null
        ? [const StopShellCommand()]
        : [const Interrupt()];
  }
  if (key == 'ctrl+o') return [const Dispatch(ToggleExpandedAction())];
  // The draft is the prompt box's; a picker or a permission has the keys,
  // and the search shows a match in its place. During a turn the draft is
  // the next prompt, so it opens then too.
  if (key == 'ctrl+g') {
    return state.search == null && context.canEdit && !state.closing
        ? [const OpenEditor()]
        : [];
  }
  if (key == 'ctrl+v') {
    return takesImagePaste(context) ? [const PasteImage()] : [];
  }
  if (key == '?') {
    return state.draft.isEmpty
        ? [const Dispatch(ShortcutsChangedAction(HelpToggled()))]
        : [];
  }
  final step = permissionScrollSteps[key];
  if (step != null) {
    if (_pagesNote(key, context)) return [ScrollRequest(step)];
    if (state.shortcuts.help && state.shortcuts.panelOverflows) {
      return [ScrollPanel(step)];
    }
    if (askedPermission(state.transcript.turn) != null &&
        !heldBack(state) &&
        state.requestOverflows) {
      return [ScrollRequest(step)];
    }
    return [Dispatch(TranscriptScrolledAction(step))];
  }
  return [];
}

/// Enter continues a line or delegates commands before the agent send guard.
List<Step> submitSteps(String value, KeyContext context) {
  final next = continued(value, context.state.cursor);
  if (next != null) return [ShowDraft(next.text, next.cursor)];
  if (context.state.bash) {
    if (context.state.closing ||
        value.trim().isEmpty ||
        runningShell(context.state.transcript) != null) {
      return [];
    }
    return [
      ..._keptLeft(context),
      HistoryStep(
        prompt_history.recorded(context.history, typedText(true, value)),
      ),
      const Dispatch(BashModeAction(false)),
      const ShowDraft('', startCursor),
      RunShellCommand(value),
    ];
  }
  final phase = context.state.start.phase;
  // chord's own commands run while the agent starts, as the original's;
  // a prompt for the agent waits for it, in the box.
  if (context.state.closing ||
      value.trim().isEmpty ||
      (phase != StartPhase.connected &&
          phase != StartPhase.gone &&
          phase != StartPhase.failed &&
          submitted(value, context.highlighted) is SendSubmitted)) {
    return [];
  }
  // A prompt for the agent waits for the one whose paths are being read;
  // chord's own commands do not.
  if (context.submitting &&
      submitted(value, context.highlighted) is SendSubmitted) {
    return [];
  }
  // A kept draft sent leaves the stack as it leaves the box; a prompt the
  // agent cannot take yet stays in the box, and on the stack.
  final leaving = switch (submitted(value, context.highlighted)) {
    LocalSubmitted() => _keptLeft(context),
    SendSubmitted() when phase == StartPhase.connected => _keptLeft(context),
    _ => const <Step>[],
  };
  if (context.takesImages == true && namesImage(value, context.home)) {
    return [...leaving, SendWithPaths(value)];
  }
  return [...leaving, Send(value)];
}

/// ↑ on the first line, or `k` there in normal mode: the agent's newest
/// kept draft, then older ones, then an older prompt.
List<Step> olderSteps(KeyContext context) {
  final step = prompt_history.older(
    context.history,
    typedText(context.state.bash, context.state.draft),
    _keptTexts(context.state),
  );
  return step == null ? [] : _walkedTo(context, step);
}

/// ↓ on the last line, or `j` there in normal mode: a newer one; or, from
/// a draft that is not walking history, the draft set aside, as if the
/// history ended in an empty prompt; or, from an empty one, into the list
/// of the window's agents, where ↓ did nothing before there was one.
List<Step> newerSteps(KeyContext context) {
  final state = context.state;
  final step = prompt_history.newer(context.history, _keptTexts(state));
  if (step != null) return _walkedTo(context, step);
  if (state.draft.isNotEmpty && context.history.index == null) {
    return const [Dispatch(DraftKeptAction()), ShowDraft('', startCursor)];
  }
  return context.agents && state.draft.isEmpty && context.history.index == null
      ? const [Dispatch(AgentsFocusedAction(true))]
      : const [];
}

/// ctrl+x a: the front agent's own request held between turns is what
/// needs the person first, and the keys go into its box; else the agent
/// that waits longest.
List<Step> attentionSteps(KeyContext context) => heldBack(context.state)
    ? const [Dispatch(AttendRequestAction())]
    : const [AttendSession()];

/// The texts of the agent's kept drafts, oldest first.
List<String> _keptTexts(AppState state) => [
  for (final draft in state.kept) draft.text,
];

/// A step of the walk into the box: a kept draft whole, as it was set
/// aside, its cursor too; else a prompt or the walk's own draft, the cursor
/// at its end.
List<Step> _walkedTo(KeyContext context, prompt_history.Walked step) {
  final state = context.state;
  final kept = step.kept == null ? null : state.kept[step.kept!];
  final shown = _shownKept(context);
  return [
    // A kept draft walked off stays as it was left, edits and all.
    if (shown != null) Dispatch(KeptEditedAction(shown)),
    HistoryStep(step.history),
    if (kept == null)
      ..._recallSteps(step.text, state.bash, step.history)
    else ...[
      if (state.bash != kept.bash) Dispatch(BashModeAction(kept.bash)),
      if (kept.images.isNotEmpty) Dispatch(ImagesAddedAction(kept.images)),
      ShowDraft(kept.text, kept.cursor),
    ],
  ];
}

/// Which of the agent's kept drafts the walk shows; none off them.
int? _shownKept(KeyContext context) {
  final index = context.history.index;
  if (index == null) return null;
  final own = index - context.history.prompts.length;
  return own >= 0 && own < context.state.kept.length ? own : null;
}

/// The kept draft the box shows, leaving it: sent, or cleared; it goes off
/// the stack, and the walk ends.
List<Step> _keptLeft(KeyContext context) => switch (_shownKept(context)) {
  null => const [],
  final index => [
    Dispatch(KeptTakenAction(index)),
    HistoryStep(prompt_history.left(context.history)),
  ],
};

/// A Picker choice intent after the framework has handled its keys.
List<Step> chooseSteps(String id, String optionId, KeyContext context) {
  final wait = askedPermission(context.state.transcript.turn);
  return wait?.id == id &&
          !heldBack(context.state) &&
          wait!.options.any((option) => option.optionId == optionId)
      ? [ChoosePermission(id, optionId)]
      : [];
}

/// The original Tab eligibility, after actual modal/completion key ownership.
bool canSteer(KeyContext context) =>
    context.rows > 0 &&
    context.columns > 0 &&
    context.canEdit &&
    !context.completing &&
    !context.picking &&
    !context.state.shortcuts.help &&
    !context.state.closing &&
    !context.state.bash &&
    context.state.search == null &&
    isBusy(context.state) &&
    sendable(context.state.queue);

String _bindingDescription(String key, String fallback, KeyContext context) {
  if (context.splash && key == 'esc') return 'Show the window';
  if (context.state.search != null && context.canEdit) {
    if (key == 'tab' || key == 'enter') return 'Take search match';
    if (key == 'esc' || key == 'ctrl+c') return 'Cancel search';
    if (key == 'ctrl+r') return 'Older matching prompt';
  }
  if (key == 'tab' && canSteer(context) && !context.completing) {
    return 'Send oldest queued prompt now';
  }
  final state = context.state;
  final step = permissionScrollSteps[key];
  if (_pagesNote(key, context)) {
    return step == ScrollStep.pageUp ? 'Read note above' : 'Read note below';
  }
  if (step == null ||
      !state.requestOverflows ||
      heldBack(state) ||
      askedPermission(state.transcript.turn) == null) {
    return fallback;
  }
  return switch (step) {
    ScrollStep.pageUp || ScrollStep.lineUp => 'Read permission above',
    ScrollStep.pageDown || ScrollStep.lineDown => 'Read permission below',
    ScrollStep.top => 'Read permission from top',
    ScrollStep.bottom => 'Read permission to bottom',
  };
}

/// Whether an existing matched command preserves a logical selection.
bool preservesSelection(List<Step> steps) =>
    steps.length == 1 &&
    (steps.single is CopySelection ||
        steps.single is Dispatch &&
            (steps.single as Dispatch).action is TranscriptScrolledAction);

/// Printable form input cannot be preserved by an outer binding-only preview.
bool preservesSelectionPrefix(KeyEvent event) =>
    event.ctrl || event.alt || event.char == null;

List<Step> _recallSteps(
  String text,
  bool currentBash,
  prompt_history.History history,
) {
  final command = bashCommand(text);
  final images = prompt_history.recalledImages(history, text);
  return [
    if (currentBash != (command != null))
      Dispatch(BashModeAction(command != null)),
    // A recalled prompt brings back the images it sent.
    if (images.isNotEmpty) Dispatch(ImagesAddedAction(images)),
    ShowDraft(command ?? text, endOf(command ?? text)),
  ];
}

/// A typed or pasted ! is the mode's prefix only from an empty ordinary draft.
List<Step> changeSteps(String value, Cursor cursor, KeyContext context) {
  final state = context.state;
  final command = entersBash(state.bash, state.draft, value);
  if (command != null) {
    return [
      const Dispatch(BashModeAction(true)),
      ShowDraft(command, endOf(command)),
    ];
  }
  // Half a placeholder stands for nothing: the whole one goes.
  final cut = cutPlaceholder(state.draft, value, state.images);
  if (cut != null) {
    return [
      Dispatch(DraftEditedAction(cut.text, cut.cursor)),
      ShowDraft(cut.text, cut.cursor),
    ];
  }
  final pasted = pastedText(state.draft, value);
  return [
    Dispatch(DraftEditedAction(value, cursor)),
    // A path pasted, as a terminal puts a dropped file in, is the image it
    // names.
    if (pasted != null &&
        !state.bash &&
        context.takesImages == true &&
        namesImage(pasted.text, context.home))
      TakePastedPaths(value, pasted.end),
  ];
}

/// An input/paste edit owned by the active query, never by the saved editor.
List<Step> searchEditSteps(
  String input,
  KeyContext context, {
  bool ctrl = false,
  bool meta = false,
  bool backspace = false,
  bool delete = false,
}) {
  final current = context.state.search;
  if (current == null ||
      !context.searchEnabled ||
      !context.canEdit ||
      context.state.closing ||
      context.state.shortcuts.help) {
    return [];
  }
  final query = search.editedQuery(
    current.query,
    input,
    ctrl: ctrl,
    meta: meta,
    backspace: backspace,
    delete: delete,
  );
  return query == null
      ? []
      : [
          Dispatch(
            SearchChangedAction(
              search.searched(current, context.history.prompts, query),
            ),
          ),
        ];
}

/// The keybindings file's contexts open over the prompt in [context], which
/// take the keys they bind ahead of the window's others.
Set<keymap.KeyContext> liveContexts(KeyContext context) => {
  if (context.completing) keymap.KeyContext.autocomplete,
  if (context.state.shortcuts.help) keymap.KeyContext.help,
  if (context.listKeys) keymap.KeyContext.agents,
};
