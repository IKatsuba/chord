/// Only a new unnamed interactive invocation asks which agent to start.
bool chooseAgentAtStart({
  String? named,
  String? agentCommand,
  String? print,
  bool continuing = false,
  Object? resume,
  required bool stdinTTY,
  required bool stdoutTTY,
}) =>
    named == null &&
    agentCommand == null &&
    print == null &&
    !continuing &&
    resume == null &&
    stdinTTY &&
    stdoutTTY;

/// A start page's first pick or cancellation, settled exactly once.
class StartupSelection {
  bool _settled = false;
  String? _selected;

  /// Whether a pick or cancellation has already won.
  bool get settled => _settled;

  /// The picked name, or null for cancellation or no answer yet.
  String? get selected => _selected;

  /// Accepts only the first outcome, including a null cancellation.
  bool settle(String? value) {
    if (_settled) return false;
    _settled = true;
    _selected = value;
    return true;
  }
}
