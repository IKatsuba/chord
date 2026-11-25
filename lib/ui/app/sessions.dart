import 'package:cancellation_token/cancellation_token.dart';

import '../../notices.dart';
import '../../session/config.dart' show optionsFromConfigOptions;
import '../../session/conversation.dart'
    show AgentStateChanged, Cleared, Closing, Connected, ConversationEvent;
import '../../session/sessions.dart';
import '../../session/state_dir.dart';
import '../../session/transcript/types.dart';

/// A fresh cancellable discovery operation for a live resume command.
typedef ReadResumeRecords =
    Future<List<SessionRecord>> Function({
      CancellationToken? cancellationToken,
    });

/// Production discovery; no permanent cache survives an opening.
Future<List<SessionRecord>> readResumeRecords({
  CancellationToken? cancellationToken,
}) => readRecords(chordStateDir(), cancellationToken: cancellationToken);

/// Original busy refusal, naming the current chat-cancel key when it is bound.
String? resumeRefusal(Transcript transcript, {String? cancelKey = 'Esc'}) =>
    transcript.turn is Idle
    ? null
    : cancelKey == null
    ? 'A turn is running. Wait for it to end, then /resume.'
    : 'A turn is running. Wait for it to end, or press $cancelKey to interrupt it, then /resume.';

/// dimcode's one-time notice for a window: it comes due the first time any
/// of the window's sessions, main, a child, a team member or a task, has its
/// permission option at anything but read-only, unless dismissed on this
/// machine; a record that does not read shows it, and a session that left
/// that moment, closed or was cleared while the record was read shows none.
final class WindowNotices {
  /// The notices of a window whose record is beside the user settings in
  /// [configHome], none without one; [opened] hears one come due.
  WindowNotices({String? configHome, required this.opened})
    : _gate = NoticeGate(() => dismissedNotices(noticesFile(configHome)), (
        id,
      ) async {
        final file = noticesFile(configHome);
        if (file != null) await dismissNotice(file, id);
      });

  /// Hears a notice, by its id, come due to show.
  final void Function(String id) opened;
  final _watch = NoticeWatch();
  final NoticeGate _gate;

  /// Session [id], of [agent], heard [event], ahead of its being told.
  void watched(String id, String agent, ConversationEvent event) {
    // A session cleared is gone as one closed is: the one after it, under
    // the same id, comes due of its own.
    if (event is Closing || event is Cleared) _watch.gone(id);
    final state = switch (event) {
      Connected(:final state) || AgentStateChanged(:final state) => state,
      _ => null,
    };
    if (state == null) return;
    final ticket = _watch.heard(
      id,
      agent,
      optionsFromConfigOptions(state.configOptions),
    );
    if (ticket == null) return;
    _gate.due(dimcodeNotice, () => _watch.holds(id, ticket)).then((shows) {
      if (shows) opened(dimcodeNotice);
    });
  }

  /// Dismisses notice [id] for good on this machine: the person's `1`.
  void dismiss(String id) => _gate.dismiss(id);
}
