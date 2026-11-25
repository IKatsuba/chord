// The original's tests/ui/transcript/compaction_test.ts.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/compaction.dart';
import 'package:test/test.dart';

Compaction base({
  String status = 'in_progress',
  String summary = '',
  String? error,
  bool unasked = false,
}) =>
    Compaction('k1', status, summary: summary, error: error, unasked: unasked);

void main() {
  test('a compaction that runs reads as Claude Code says it', () {
    expect(compactionLine(base(), false, 'ctrl+o'), (
      text: 'Compacting conversation…',
      tone: CompactionTone.running,
    ));
    // A status ACP may add later is not taken for an ending.
    expect(
      compactionLine(base(status: 'paused'), false, 'ctrl+o').tone,
      CompactionTone.running,
    );
  });

  test('a completed compaction names the key to its summary only while '
      'there is one to see', () {
    final done = base(status: 'completed', summary: 'Kept this.');
    expect(compactionLine(done, false, 'ctrl+o'), (
      text: 'Conversation compacted (ctrl+o for history)',
      tone: CompactionTone.done,
    ));
    expect(compactionLine(done, true, 'ctrl+o').text, 'Conversation compacted');
    expect(compactionLine(done, false, null).text, 'Conversation compacted');
    // Codex's adapter sends no summary.
    expect(
      compactionLine(base(status: 'completed'), false, 'ctrl+o').text,
      'Conversation compacted',
    );
  });

  test('a failed or cancelled compaction says so', () {
    expect(
      compactionLine(
        base(status: 'failed', error: 'Not enough messages.\n'),
        false,
        'ctrl+o',
      ),
      (
        text: 'Compaction failed: Not enough messages.',
        tone: CompactionTone.failed,
      ),
    );
    expect(
      compactionLine(base(status: 'failed'), false, 'ctrl+o').text,
      'Compaction failed',
    );
    expect(compactionLine(base(status: 'cancelled'), false, 'ctrl+o'), (
      text: 'Compaction cancelled',
      tone: CompactionTone.failed,
    ));
  });

  test('a compaction running in the turn that is goes to the spinner, any '
      'other stays in the transcript', () {
    const working = Working('t2', 0);
    Entry entry(String turnId, String status) =>
        CompactionEntry(turnId, base(status: status));

    expect(inSpinner(entry('t2', 'in_progress'), working), isTrue);
    // No spinner outside a turn, so the transcript says it.
    expect(inSpinner(entry('t2', 'in_progress'), const Idle()), isFalse);
    // One a past turn left unended is not this turn's work.
    expect(inSpinner(entry('t1', 'in_progress'), working), isFalse);
    // An ended one is the transcript's line.
    expect(inSpinner(entry('t2', 'completed'), working), isFalse);
    expect(inSpinner(const UserEntry('t2', 'hi'), working), isFalse);
  });

  test('an unasked compaction says it ran while idle, in every status', () {
    final done = base(
      status: 'completed',
      summary: 'Kept this.',
      unasked: true,
    );
    expect(compactionLine(base(unasked: true), false, 'ctrl+o'), (
      text: 'Compacting conversation while idle…',
      tone: CompactionTone.running,
    ));
    expect(compactionLine(done, false, 'ctrl+o'), (
      text: 'Conversation compacted while idle (ctrl+o for history)',
      tone: CompactionTone.done,
    ));
    expect(
      compactionLine(done, true, 'ctrl+o').text,
      'Conversation compacted while idle',
    );
    expect(
      compactionLine(
        base(status: 'completed', unasked: true),
        false,
        'ctrl+o',
      ).text,
      'Conversation compacted while idle',
    );
    expect(
      compactionLine(
        base(status: 'failed', error: 'Not enough messages.', unasked: true),
        false,
        'ctrl+o',
      ),
      (
        text: 'Compaction failed while idle: Not enough messages.',
        tone: CompactionTone.failed,
      ),
    );
    expect(
      compactionLine(base(status: 'cancelled', unasked: true), false, 'ctrl+o'),
      (text: 'Compaction cancelled while idle', tone: CompactionTone.failed),
    );
  });

  test('an unasked compaction still running when a turn starts is that '
      "turn's, so the spinner says it", () {
    const working = Working('t2', 0);
    Entry entry(String status) =>
        CompactionEntry('t1', base(status: status, unasked: true));
    expect(inSpinner(entry('in_progress'), working), isTrue);
    expect(inSpinner(entry('in_progress'), const Idle()), isFalse);
    expect(inSpinner(entry('completed'), working), isFalse);
    // Waiting on a permission or cancelling is still the turn.
    expect(
      inSpinner(entry('in_progress'), const AwaitingPermission('t2', 0, [])),
      isTrue,
    );
    expect(
      inSpinner(entry('in_progress'), const Cancelling('t2', 0, 1)),
      isTrue,
    );
  });
}
