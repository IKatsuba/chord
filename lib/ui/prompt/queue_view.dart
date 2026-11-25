import 'package:chord_tui/chord_tui.dart';

import '../../session/conversation.dart';
import '../transcript/tools/tool.dart';
import 'queue.dart';

/// Dim prompts waiting below the working line and above the prompt box.
class Queue extends StatelessWidget {
  const Queue({super.key, required this.queue, required this.limit});

  final List<QueuedPrompt> queue;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).dim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        children: [
          for (final row in queueRows(queue, limit))
            Row(
              children: [
                Gutter(row is MessageQueueRow ? '←' : '›', style: dim),
                // Whole, so the cut lands in the text after it: a long name
                // would otherwise take why the message waits with it.
                if (switch (row) {
                      PromptQueueRow(:final header) => header,
                      MessageQueueRow(:final header) => header,
                      MoreQueueRow() => null,
                    }
                    case final header?)
                  Text.ansi(header, style: dim, softWrap: false),
                Expanded(
                  child: Text.ansi(
                    switch (row) {
                      PromptQueueRow(:final text) ||
                      MessageQueueRow(:final text) => text,
                      MoreQueueRow(:final count) => '… +$count more',
                    },
                    style: dim,
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.middle,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
