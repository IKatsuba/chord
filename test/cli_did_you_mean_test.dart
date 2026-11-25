// CTUI-111: `chord agents` refuses an unknown option with Cliffy's
// nearest-option line, as `didYouMeanOption` in @cliffy/flags words it
// through @std/text's closestString. Each expected line is what the
// original (../chord, `bun src/main.tsx <args>`) printed.
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _original = {
  'agents --model x': 'Unknown option "--model". Did you mean option "--help"?',
  'agents --jsn': 'Unknown option "--jsn". Did you mean option "--json"?',
  'agents -x': 'Unknown option "-x". Did you mean option "-h"?',
  'agents --JSON': 'Unknown option "--JSON". Did you mean option "--json"?',
  'agents --c': 'Unknown option "--c". Did you mean option "-C"?',
  'agents --agent-command x':
      'Unknown option "--agent-command". Did you mean option "--cwd"?',
  'agents -V': 'Unknown option "-V". Did you mean option "-h"?',
  'agents -p x': 'Unknown option "-p". Did you mean option "-h"?',
  'agents --no-mcp-servers':
      'Unknown option "--no-mcp-servers". Did you mean option "--help"?',
  'agents --nope': 'Unknown option "--nope". Did you mean option "--help"?',
  'agents --version':
      'Unknown option "--version". Did you mean option "--json"?',
  'agents -m x': 'Unknown option "-m". Did you mean option "-h"?',
  'agents --effort x':
      'Unknown option "--effort". Did you mean option "--json"?',
  'agents --permission-mode x':
      'Unknown option "--permission-mode". Did you mean option "--json"?',
  'agents --no-json':
      'Unknown option "--no-json". Did you mean option "--json"?',
  'agents --no-help':
      'Unknown option "--no-help". Did you mean option "--help"?',
  // Code points, not UTF-16 units: -h and --cwd are both 3 away, and -h
  // comes first (CTUI-111 review).
  'agents --d😀': 'Unknown option "--d😀". Did you mean option "-h"?',
  // Words args reads as no option, refused before any argument.
  'agents --a.b': 'Unknown option "--a.b". Did you mean option "--cwd"?',
  'agents -é': 'Unknown option "-é". Did you mean option "-h"?',
  'agents x --a.b': 'Unknown option "--a.b". Did you mean option "--cwd"?',
  'agents --a.b=x': 'Unknown option "--a.b". Did you mean option "--cwd"?',
  'agents --d😀=x': 'Unknown option "--d😀". Did you mean option "-h"?',
  'agents --continue':
      'Unknown option "--continue". Did you mean option "--cwd"?',
};

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('chord-dym-'));
  tearDown(() => root.deleteSync(recursive: true));

  for (final MapEntry(key: call, value: line) in _original.entries) {
    test('chord $call says the nearest option, as the original', () async {
      final err = StringBuffer();
      final outcome = await runCli(
        call.split(' '),
        stdout: StringBuffer(),
        stderr: err,
        cwd: root.path,
        home: p.join(root.path, 'home'),
        environment: {'XDG_CONFIG_HOME': p.join(root.path, 'config')},
        lookup: (command) async => null,
        readSessionRecords: () async => const [],
      );
      expect(outcome.code, 2);
      expect(err.toString(), '\n  error: $line\n\n');
    });
  }

  test('the first of equally near options wins, case ignored', () {
    // -x is one edit from both -h and -C; -h is declared first.
    expect(unknownAgentsOption('-x'), endsWith('"-h"?'));
    expect(unknownAgentsOption('-c'), endsWith('"-C"?'));
  });

  group('tester CTUI-111: literal malformed options', () {
    for (final word in ['--a.b=x', '--d😀=x', '-é']) {
      test(
        '$word after the terminator is ignored without a suggestion',
        () async {
          final out = StringBuffer(), err = StringBuffer();
          final outcome = await runCli(
            ['agents', '--json', '--', word],
            stdout: out,
            stderr: err,
            cwd: root.path,
            home: p.join(root.path, 'home'),
            environment: {'XDG_CONFIG_HOME': p.join(root.path, 'config')},
            lookup: (_) async => null,
            readSessionRecords: () async => const [],
          );
          expect(outcome.code, 0);
          expect(outcome.launch, isNull);
          expect(err.toString(), isEmpty);
          expect(out.toString(), startsWith('{"version":1,'));
        },
      );
    }
  });
}
