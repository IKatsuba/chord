// What Cliffy refuses that args lets pass (CTUI-165): a non-collect option
// given twice, named as typed the second time, and help or version beside
// another option. Main and `agents` print their help and the error, exit
// 2; `acp` prints only `chord: <message>` on stderr, exit 2. The expected
// words are Cliffy's: flags.js's DuplicateOptionError and the standalone
// check in _validate_flags.ts (OptionNotCombinableError).
import 'package:chord/cli.dart';
import 'package:test/test.dart';

import 'cli_test.dart' show chord, refused;

String twice(String name) =>
    'Option "$name" can only occur once, but was found several times.';
String alone(String name) =>
    'Option "$name" cannot be combined with other options.';

void main() {
  group('main', () {
    for (final (argv, message) in [
      (['-m', 'a', '-m', 'b'], twice('-m')),
      (['-m', 'a', '--model', 'b'], twice('--model')),
      (['--model=a', '-mb'], twice('-m')),
      (['-p', 'x', '-p', 'y'], twice('-p')),
      (['-C', 'a', '-C', 'b'], twice('-C')),
      (['--effort', 'a', '--effort', 'b'], twice('--effort')),
      (['--no-mcp-servers', '--no-mcp-servers'], twice('--no-mcp-servers')),
      (['fake', '-m', 'a', '-m', 'b'], twice('-m')),
      // Read in order: the twice-given option before the unknown one.
      (['-m', 'a', '-m', 'b', '--nope'], twice('-m')),
      (['-h', '-m', 'x'], alone('--help')),
      (['-m', 'x', '-h'], alone('--help')),
      (['-V', '-m', 'x'], alone('--version')),
      (['--version', '--no-mcp-servers'], alone('--version')),
      // Cliffy names the last standalone option read.
      (['-h', '-V', '-m', 'x'], alone('--version')),
      (['-h', '-h'], twice('-h')),
      // Help and version are each another option to the other.
      (['-h', '-V'], alone('--version')),
      (['-V', '-h'], alone('--help')),
      (['--version', '--help'], alone('--help')),
      (['--help', '--version'], alone('--version')),
      (['-hV'], alone('--version')),
      // Cliffy takes a subcommand only as the first word: here `agents` is
      // the agent, and -C is given twice.
      (['-C', 'a', 'agents', '-C', 'b'], twice('-C')),
      (['custom', '--agent-command', 'x', '--help'], alone('--help')),
    ]) {
      test(argv.join(' '), () async {
        refused(await chord(argv), message);
      });
    }

    test('help or version beside only an agent is no refusal', () async {
      final help = await chord(['fake', '-h']);
      expect(help.outcome.code, 0);
      expect(help.stdout, '$chordHelp\n');
      final shown = await chord(['-V', 'fake']);
      expect(shown.outcome.code, 0);
    });
  });

  group('agents', () {
    for (final (argv, message) in [
      (['agents', '--json', '--json'], twice('--json')),
      (['agents', '-C', 'a', '--cwd', 'b'], twice('--cwd')),
      (['agents', '-h', '--json'], alone('--help')),
      // -C takes the next word as its value, whatever it looks like.
      (['agents', '-C', '--model', '-C', 'x'], twice('-C')),
    ]) {
      test(argv.join(' '), () async {
        refused(await chord(argv), message, help: agentsHelp);
      });
    }
  });

  group('acp', () {
    for (final (argv, message) in [
      (['acp', '-m', 'a', '-m', 'b'], twice('-m')),
      (
        ['acp', '--no-mcp-servers', '--no-mcp-servers'],
        twice('--no-mcp-servers'),
      ),
      (['acp', '-h', '-m', 'x'], alone('--help')),
    ]) {
      test(argv.join(' '), () async {
        final call = await chord(argv);
        expect(call.outcome.code, 2);
        expect(call.outcome.acp, isNull);
        expect(call.stdout, isEmpty);
        expect(call.stderr, 'chord: $message\n');
      });
    }
  });
}
