import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

void main() {
  group('tester ACP terminal metadata relay', () {
    for (final declared in [true, false]) {
      test('tool metadata survives for client delta declaration $declared', () {
        fakeAsync((async) {
          final rig = Rig(async);
          rig.initialize({
            if (declared) '_meta': {'terminal_output_delta': true},
          });
          final session = rig.newSession();
          final agent = rig.agents.single;
          const meta = {
            'terminal_info': {'terminal_id': 'terminal', 'cwd': '.'},
            'terminal_output_delta': {
              'terminal_id': 'terminal',
              'data': '界🙂e\u0301\x1b[31m',
            },
            'terminal_exit': {
              'terminal_id': 'terminal',
              'exit_code': 1,
              'signal': null,
            },
          };
          agent.send({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': 's1',
              'update': {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'call',
                'title': 'Run checks',
                'status': 'failed',
                '_meta': meta,
              },
            },
          });
          rig.settle();
          final update = rig
              .notified('session/update')
              .where(
                (p) =>
                    (p['update'] as Map)['sessionUpdate'] !=
                    'available_commands_update',
              )
              .single;
          expect(update['sessionId'], session);
          expect((update['update'] as Map)['_meta'], meta);
          rig.eof();
        });
      });
    }
  });
}
