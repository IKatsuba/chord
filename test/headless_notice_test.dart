// dimcode's notice on `chord -p`'s stderr, a `chord: ` line per paragraph,
// stdout keeping the reply (the original's src/headless.ts:329).
import 'package:chord/headless.dart';
import 'package:chord/notices.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'session/oneshot_notice_test.dart' show NoticeAgent;

({String stdout, String stderr}) _headless(NoticeAgent agent, String name) {
  final out = StringBuffer(), err = StringBuffer();
  fakeAsync((async) {
    agent.drive(
      async,
      runHeadless(
        agent: name,
        command: 'memory',
        cwd: '/w',
        prompt: 'hello',
        format: 'text',
        open: agent.open,
        stdout: (text) async => out.write(text),
        stderr: (text) async => err.write(text),
      ),
    );
  });
  return (stdout: '$out', stderr: '$err');
}

void main() {
  test('stderr says both paragraphs once; stdout is the reply alone', () {
    final call = _headless(
      NoticeAgent(
        start: 'read-only',
        moves: ['full-access', 'workspace-write'],
      ),
      'dimcode',
    );

    expect(
      call.stderr,
      'chord: ${dimcodeWords.paragraphs[0]}\n'
      'chord: ${dimcodeWords.paragraphs[1]}\n',
    );
    expect(call.stdout, startsWith('before'));
    expect(call.stdout, isNot(contains('dimcode may start')));
  });

  test('another agent at full-access says nothing of it', () {
    final call = _headless(NoticeAgent(start: 'full-access'), 'codex');

    expect(call.stderr, isEmpty);
  });
}
