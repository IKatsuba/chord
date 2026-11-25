import 'package:chord/cli.dart' show agentsHelp, chordHelp;
import 'package:test/test.dart';

import 'cli_test.dart' show chord, refused;

String _twice(String option) =>
    'Option "$option" can only occur once, but was found several times.';

void main() {
  group('tester CTUI-165: non-collect coverage and literal operands', () {
    for (final (args, option) in const [
      (['--permission-mode=a', '--permission-mode=b'], '--permission-mode'),
      (['--agent-command=a', '--agent-command=b'], '--agent-command'),
      (['-c', '--continue'], '--continue'),
      (['--resume=a', '--resume=b'], '--resume'),
      (['--print=x', '-py'], '-p'),
      (['--output-format=text', '--output-format=json'], '--output-format'),
      (
        [
          '--dangerously-skip-permissions',
          '--dangerously-skip-permissions',
          '-p',
          'x',
        ],
        '--dangerously-skip-permissions',
      ),
    ]) {
      test('main refuses $option before any runtime lookup', () async {
        refused(
          await chord(
            args,
            lookup: (_) => throw StateError('must not look up a runtime'),
          ),
          _twice(option),
        );
      });
    }

    for (final option in ['--effort', '--permission-mode', '--agent-command']) {
      test('ACP refuses repeated $option without printing help', () async {
        final call = await chord(['acp', '$option=a', '$option=b']);
        expect(call.outcome.code, 2);
        expect(call.outcome.acp, isNull);
        expect(call.stdout, isEmpty);
        expect(call.stderr, 'chord: ${_twice(option)}\n');
      });
    }

    test(
      'agents keeps attached cwd values separate from option spellings',
      () async {
        refused(
          await chord(['agents', '--cwd=-C', '-C=--cwd']),
          _twice('-C'),
          help: agentsHelp,
        );
      },
    );

    test(
      'a literal help-looking agent after -- is no repeated option',
      () async {
        final call = await chord(['--help', '--', '--help']);
        expect(call.outcome.code, 0);
        expect(call.outcome.launch, isNull);
        expect(call.stdout, '$chordHelp\n');
        expect(call.stderr, isEmpty);
      },
    );
  });
}
