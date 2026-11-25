/// What `chord acp` keeps of each of a host's sessions for the host and the
/// server to read back, folded as each event comes, from the original's
/// `acp/host_fold.ts`. It has no window, so nothing lags: the fold is as
/// fresh as the event just heard.
library;

import '../session/conversation.dart';
import '../session/transcript/entries.dart' show replayTranscript;
import '../session/transcript/reducer.dart' show noted, reduceTranscript;
import '../session/transcript/types.dart' show Transcript;

/// What the host reads of one session: its transcript, and the person's
/// prompts held behind its turn.
typedef FoldedSession = ({Transcript transcript, List<QueuedPrompt> queue});

/// A session nothing has been heard of. Its queue stays empty: the host
/// reads it only for a person's prompts held behind a child's turn, and
/// every prompt to a child here is a message.
const FoldedSession noFold = (
  transcript: Transcript.empty,
  queue: <QueuedPrompt>[],
);

/// The events [foldEvent] folds into the transcript, by their type's name.
const hostFolded = {
  'Cleared',
  'HistoryReplayed',
  'SettingNoted',
  'Transcribed',
};

/// Every event that is no transcript action, by its type's name: the
/// fold leaves itself as it is for them. A test fails when an event type
/// is in neither list, as the original's `bun check` does.
const hostNotActions = {
  'AgentClosed',
  'AgentStateChanged',
  'Closing',
  'ConnectFailed',
  'Connected',
  'Gone',
  'ModePending',
  'QueueWithdrawn',
  'Queued',
  'RanTyped',
  'Renamed',
  'MonitorsChanged',
  'RetiredUpdate',
  'RetiredUsage',
};

/// [fold] with [event] in; a clear starts it again, as it does the session.
FoldedSession foldEvent(FoldedSession? fold, ConversationEvent event) {
  final had = fold ?? noFold;
  // No default: a new event type fails to compile here until it is placed.
  final Transcript transcript;
  switch (event) {
    case Cleared():
      return noFold;
    case Transcribed(:final action):
      transcript = reduceTranscript(had.transcript, action);
    // The past a resume or a load replays, as the window draws it.
    case HistoryReplayed(:final actions):
      transcript = replayTranscript(actions);
    case SettingNoted(:final id, :final command, :final text, :final failed):
      transcript = noted(had.transcript, id, command, text, failed: failed);
    case RanTyped() ||
        AgentClosed() ||
        RetiredUpdate() ||
        RetiredUsage() ||
        Connected() ||
        ConnectFailed() ||
        AgentStateChanged() ||
        ModePending() ||
        Queued() ||
        QueueWithdrawn() ||
        Gone() ||
        Renamed() ||
        MonitorsChanged() ||
        Closing():
      return had;
  }
  return identical(transcript, had.transcript)
      ? had
      : (transcript: transcript, queue: had.queue);
}
