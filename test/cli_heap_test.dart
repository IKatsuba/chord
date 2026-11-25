// The heap signal is watched where the original's main does it: on the
// way to the window, past one-shot runs and subcommands (CTUI-103).
import 'package:chord/cli.dart';
import 'package:test/test.dart';

void main() {
  Future<(CliOutcome, List<String Function()>)> run(List<String> args) async {
    final watched = <String Function()>[];
    final outcome = await runCli(
      args,
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      cwd: '/home/me/src/app',
      home: '/home/me',
      lookup: (command) async => '/bin/$command',
      stateDirectory: () => '/state/chord',
      watchHeap: watched.add,
    );
    return (outcome, watched);
  }

  test(
    'a window watches the signal, into heaps in the state directory',
    () async {
      final (outcome, watched) = await run(['claude']);
      expect(outcome.launch, isNotNull);
      expect(watched.single(), '/state/chord/heaps');
    },
  );

  test('help, the version and the agents list watch nothing', () async {
    for (final args in [
      ['--help'],
      ['--version'],
      ['agents'],
    ]) {
      final (_, watched) = await run(args);
      expect(watched, isEmpty, reason: '$args');
    }
  });
}
