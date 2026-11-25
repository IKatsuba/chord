import '../../session/sessions.dart';
import '../../session/efforts.dart';
import '../../session/parameters.dart';
import '../start_state.dart';

/// A session setting picker and its unsent selection.
final class SettingsPickerState {
  const SettingsPickerState(
    this.kind, {
    this.option,
    this.from,
    this.effort,
    this.highlighted,
  });
  final String kind;
  final String? option;
  final String? from;
  final PendingEffort? effort;
  final String? highlighted;
}

/// Moves the unsent effort in agent order, clamping at either end.
SettingsPickerState movedEffort(
  SettingsPickerState state,
  AgentEfforts efforts,
  int by,
) {
  final current = state.effort?.option == efforts.option
      ? state.effort!.value
      : efforts.current;
  final index = efforts.available.indexWhere((e) => e.id == current);
  final start = index >= 0
      ? index
      : efforts.available.indexWhere((e) => e.id == efforts.current);
  if (start < 0 || efforts.available.isEmpty) return state;
  final next = (start + by).clamp(0, efforts.available.length - 1);
  final value = efforts.available[next];
  return SettingsPickerState(
    state.kind,
    option: state.option,
    from: state.from,
    highlighted: state.highlighted,
    effort: value.id == efforts.current
        ? null
        : (option: efforts.option, value: value.id, name: value.name),
  );
}

/// Original ready means initialized even after the agent exits: a later
/// request follows its normal refusal path. Startup failure never was ready.
bool settingsSessionInitialized(StartPhase phase, {bool closing = false}) =>
    !closing && (phase == StartPhase.connected || phase == StartPhase.gone);

/// A setting picker intent, reduced against live state between key presses.
sealed class SettingsPickerAction {
  const SettingsPickerAction();
}

/// Move the pending effort one place in the current agent offer.
final class EffortMoved extends SettingsPickerAction {
  const EffortMoved(this.by);
  final int by;
}

/// Preview a model without overwriting another pending setting.
final class ModelHighlighted extends SettingsPickerAction {
  const ModelHighlighted(this.id);
  final String id;
}

/// Applies one key's intent to the latest unsent picker state.
SettingsPickerState settingsPickerChanged(
  SettingsPickerState state,
  SettingsPickerAction action,
  AgentEfforts? efforts,
) => switch (action) {
  EffortMoved(:final by) =>
    efforts == null ? state : movedEffort(state, efforts, by),
  ModelHighlighted(:final id) => SettingsPickerState(
    state.kind,
    option: state.option,
    from: state.from,
    effort: state.effort,
    highlighted: id,
  ),
};

/// Immutable discovery snapshot; callers own asynchronous reading and visibility.
final class ResumePickerState {
  ResumePickerState({
    required Iterable<EarlierSession> sessions,
    required this.cwd,
    required this.opening,
    required this.openedAt,
    this.everywhere = false,
  }) : sessions = List.unmodifiable(sessions);

  final List<EarlierSession> sessions;
  final String cwd;
  final Object opening;
  final num openedAt;
  final bool everywhere;
}

/// Keeps the original newest-first order within the selected directory scope.
List<EarlierSession> resumeChoices(ResumePickerState picker) =>
    picker.everywhere
    ? picker.sessions
    : sessionsIn(picker.sessions, picker.cwd);

/// Opens the opposite scope with a fresh, frozen age reference.
ResumePickerState toggledResumeScope(ResumePickerState picker, num now) =>
    ResumePickerState(
      sessions: picker.sessions,
      cwd: picker.cwd,
      opening: picker.opening,
      openedAt: now,
      everywhere: !picker.everywhere,
    );
