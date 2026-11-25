import 'package:chord/cli.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-149: emitted help alignment', () {
    for (final columns in [80, 120]) {
      test(
        'both help spellings retain optional resume id at $columns columns',
        () async {
          for (final flag in ['-h', '--help']) {
            final output = StringBuffer(), errors = StringBuffer();
            final outcome = await runCli(
              [flag],
              stdout: output,
              stderr: errors,
              cwd: '.',
              home: '.',
              columns: columns,
              lookup: (_) async =>
                  throw StateError('help must not look up an agent'),
            );
            expect(outcome.code, 0);
            expect(outcome.launch, isNull);
            expect(errors.toString(), isEmpty);
            final rows = output.toString().split('\n');
            final resume = rows.singleWhere(
              (r) => r.startsWith('  -r, --resume'),
            );
            final continued = rows.singleWhere(
              (r) => r.startsWith('  -c, --continue'),
            );
            final description = RegExp(r'\S {2,}').firstMatch(resume)!.end;
            expect(resume, contains('--resume [id]'));
            expect(description, RegExp(r'\S {2,}').firstMatch(continued)!.end);
            expect(output.toString(), '$chordHelp\n');
          }
        },
      );
    }
  });
}
