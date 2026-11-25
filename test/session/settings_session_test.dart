@Tags(['fake_agent'])
library;

import 'package:chord/session/config.dart';
import 'package:chord/session/models.dart';
import 'package:chord/session/modes.dart';
import 'package:test/test.dart';
import 'session_fake.dart';

void main() {
  test(
    'mode, model and config setters reach original fake and keep its answer',
    () async {
      await withSession((session, traffic) async {
        await session.setMode('plan');
        expect(
          modesFrom(session.state.configOptions, session.state.modes)?.current,
          'plan',
        );
        await session.setModel('fake-small');
        expect(
          modelsFrom(
            session.state.configOptions,
            session.state.models,
          )?.current,
          'fake-small',
        );
        await session.setOption('effort', 'high');
        expect(
          optionsFromConfigOptions(
            session.state.configOptions,
          ).firstWhere((o) => o.id == 'effort').current,
          'high',
        );
        await expectLater(session.setModel('fake-huge'), throwsA(anything));
        expect(
          modelsFrom(
            session.state.configOptions,
            session.state.models,
          )?.current,
          'fake-small',
        );
        await expectLater(session.setMode('yolo'), throwsA(anything));
        expect(
          modesFrom(session.state.configOptions, session.state.modes)?.current,
          'plan',
        );
      });
    },
    skip: fakeAgentSkip,
  );
  test('silent mode ACK is filled before a following prompt', () async {
    await withSession((session, _) async {
      for (final mode in ['plan', 'acceptEdits', 'default']) {
        await session.setMode(mode);
        expect(
          modesFrom(session.state.configOptions, session.state.modes)?.current,
          mode,
        );
      }
      await run(session, 'text');
      expect(
        modesFrom(session.state.configOptions, session.state.modes)?.current,
        'default',
      );
    }, flags: ['--silent-set-mode']);
  }, skip: fakeAgentSkip);
  test(
    'agent without modes receives the legacy request and refuses it',
    () async {
      await withSession((session, _) async {
        await expectLater(session.setMode('plan'), throwsA(anything));
        expect(
          modesFrom(session.state.configOptions, session.state.modes),
          isNull,
        );
      }, flags: ['--no-modes']);
    },
    skip: fakeAgentSkip,
  );
}
