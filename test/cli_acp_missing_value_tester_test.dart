import 'package:test/test.dart';

import 'cli_test.dart' show chord;

void main() {
  group('tester CTUI-166: missing ACP value after explicit agent', () {
    for (final (option, named) in const [
      ('-m', '--model'),
      ('--model', '--model'),
      ('--effort', '--effort'),
      ('--permission-mode', '--permission-mode'),
      ('--agent-command', '--agent-command'),
    ]) {
      test('$option still reports only the ACP error', () async {
        final call = await chord(['acp', '--no-mcp-servers', 'claude', option]);
        expect(call.outcome.code, 2);
        expect(call.outcome.acp, isNull);
        expect(call.outcome.launch, isNull);
        expect(call.stdout, isEmpty);
        expect(call.stderr, 'chord: Missing value for option "$named".\n');
      });
    }
  });
}
