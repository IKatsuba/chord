/// The agent's replies and thoughts, as chunks run on into one block until a
/// new message, another kind or another turn starts the next.
library;

import '../../acp/schema.dart' as acp;
import 'entries.dart';
import 'text_run.dart';
import 'types.dart';

/// A chunk's words: a text block's, and nothing of an image or a link.
String textOf(acp.ContentBlock content) =>
    content.type == 'text' ? content.text! : '';

/// [state] with [content] run on into the last block of its kind, or as a
/// new block; [thought] picks a thought over a reply.
Transcript appendText(
  Transcript state,
  String turnId, {
  required bool thought,
  required acp.ContentBlock content,
  required String? messageId,
}) {
  final text = textOf(content);

  if (text.isEmpty) {
    return state;
  }

  final last = state.entries.lastOrNull;
  final continues =
      last is ChunkEntry &&
      (last is ThoughtEntry) == thought &&
      last.turnId == turnId &&
      !(last is AssistantEntry && last.planId != null) &&
      (last.messageId == null ||
          messageId == null ||
          last.messageId == messageId);

  if (continues) {
    final grown = last.text.plus(text);

    return state.withEntries(
      lastReplaced(
        state.entries,
        thought
            ? ThoughtEntry(turnId, grown, messageId: last.messageId)
            : AssistantEntry(turnId, grown, messageId: last.messageId),
      ),
    );
  }

  final started = TextRun.empty.plus(text);

  return state.withEntries(
    appended(state.entries, [
      thought
          ? ThoughtEntry(turnId, started, messageId: messageId)
          : AssistantEntry(turnId, started, messageId: messageId),
    ]),
  );
}
