import 'dart:math' as math;

import '../../session/conversation.dart';
import '../transcript/message.dart' show QueueHold, queuedMessage;

/// The person's own queued prompts: not another's message, nor one out
/// with the agent already.
Iterable<QueuedPrompt> _mine(List<QueuedPrompt> queue) => queue.where(
  (prompt) => prompt.from == null && !prompt.steering && !prompt.taken,
);

/// Queued prompts, oldest first, followed by the draft present at interrupt.
/// Another's message never comes into the box.
String restoredDraft(List<QueuedPrompt> queue, String draft) => [
  ..._mine(queue).map((prompt) => prompt.text),
  draft,
].where((text) => text != '').join('\n');

/// Whether a personal row can be dispatched, rather than held, already
/// taken, or another's message.
bool sendable(List<QueuedPrompt> queue) => queue.any(
  (row) =>
      row.from == null &&
      !row.afterAnswer &&
      !row.afterCalls &&
      !row.steering &&
      !row.taken,
);

/// The queue's share of the window, never fewer than two rows.
int queueRowLimit(int rows) => math.max(2, rows ~/ 6);

/// A row of the person's prompts waiting behind the running turn.
sealed class QueueRow {
  const QueueRow();
}

/// A queued prompt's first line, with an optional reason it is held.
final class PromptQueueRow extends QueueRow {
  const PromptQueueRow(this.text, {this.header});

  final String text;
  final String? header;
}

/// A message from another agent or chord, drawn after `←`: its [header]
/// whole, then its [text], which alone is cut to the width.
final class MessageQueueRow extends QueueRow {
  const MessageQueueRow(this.header, this.text);

  final String header;
  final String text;
}

/// The number of newest prompts folded after the oldest visible prompts.
final class MoreQueueRow extends QueueRow {
  const MoreQueueRow(this.count);

  final int count;
}

/// First lines, marked for multiline prompts, folding the newest past limit.
List<QueueRow> queueRows(List<QueuedPrompt> queue, int limit) {
  final rows = <QueueRow>[
    for (final prompt in queue)
      if (prompt.from case final from?)
        _message(
          queuedMessage(
            from,
            prompt.text,
            prompt.afterAnswer
                ? QueueHold.answer
                : prompt.afterCalls
                ? QueueHold.calls
                : null,
          ),
        )
      else
        PromptQueueRow(
          prompt.text.contains('\n')
              ? '${prompt.text.split('\n').first} …'
              : prompt.text,
          header: prompt.steering
              ? 'into the running turn: '
              : prompt.afterAnswer
              ? 'after your answer: '
              : prompt.afterCalls
              ? 'after the running calls: '
              : null,
        ),
  ];
  if (rows.length <= limit) return rows;
  return [...rows.take(limit - 1), MoreQueueRow(rows.length - limit + 1)];
}

MessageQueueRow _message(({String header, String text}) row) =>
    MessageQueueRow(row.header, row.text);
