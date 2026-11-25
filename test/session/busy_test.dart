import 'package:chord/session/busy.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  group('CTUI-35 tester: busy session reasons', () {
    test('an idle turn remains busy until its local command ends', () {
      for (final running in [true, false]) {
        final transcript = Transcript(
          entries: [
            ShellEntry(
              'shell',
              ShellRun(command: 'scripted', running: running),
            ),
          ],
        );
        expect(
          busyOf(transcript, const []),
          running ? isA<BusyWorking>() : isNull,
        );
      }
    });

    test(
      'only the person\'s untaken, unsteered queue delays an idle close',
      () {
        const own = QueuedPrompt('own', 'personal');
        const others = [
          QueuedPrompt('message', 'from main', from: MessageFrom('main')),
          QueuedPrompt('steer', 'personal steer', steering: true),
          QueuedPrompt('taken', 'already sent', taken: true),
        ];
        expect(mine([own, ...others]), [own]);
        expect(busyOf(Transcript.empty, others), isNull);
        expect(
          busyOf(Transcript.empty, [own, ...others]),
          isA<BusyQueued>().having((busy) => busy.count, 'count', 1),
        );
      },
    );

    test('a pending plan hides a later form until the plan is answered', () {
      const plan = PlanAsk(
        'turn',
        PlanWait('plan', PlanAgent.cursor, toolCallId: 'call'),
      );
      Transcript pending(PlanAsk ask) => Transcript(
        turn: const Working('turn', 0),
        planAsks: [ask],
        asking: const [FormWait('form', 'Name it')],
      );
      expect(busyOf(pending(plan), const []), isA<BusyWorking>());
      expect(
        busyOf(pending(plan.answered(const PlanAccepted())), const []),
        isA<BusyInput>(),
      );
    });
  });
}
