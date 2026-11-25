import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/resume_args.dart';
import 'package:test/test.dart';

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/cli/resume_oracle.json').readAsStringSync(),
          )
          as List;
  for (final raw in cases) {
    final vector = (raw['argv'] as List).cast<String>();
    test('original resume oracle ${jsonEncode(vector)}', () {
      Map<String, Object?> parse() {
        final adapted = adaptResumeArguments(vector);
        final parsed = chordParser.parse(adapted.arguments);
        final rest = parsed.rest.map(adapted.positional).toList();
        if (rest.length > 1) {
          throw ResumeArgumentsError(
            'Too many arguments: ${rest.skip(1).join(' ')}',
          );
        }
        if (parsed.flag('help') || parsed.flag('version')) {
          return {'noAction': true};
        }
        return {
          // Existing approved port handling of literal words after -- differs
          // from Cliffy; this flag oracle compares only its untouched intent.
          if (rest.isNotEmpty && !vector.contains('--')) 'agent': rest.first,
          if (adapted.intent.kind == ResumeKind.pick) 'resume': true,
          if (adapted.intent.kind == ResumeKind.id) 'resume': adapted.intent.id,
          if (adapted.intent.kind == ResumeKind.continuing) 'continue': true,
          if (parsed.option('agent-command') != null)
            'agentCommand': parsed.option('agent-command'),
        };
      }

      if (raw['error'] case final String error) {
        if (vector.singleOrNull == '-raaa') {
          expect(parse, throwsA(isA<Exception>()));
        } else {
          expect(
            parse,
            throwsA(
              isA<ResumeArgumentsError>().having(
                (e) => e.message,
                'original refusal',
                error,
              ),
            ),
          );
        }
      } else if (raw['value'] == 'no action') {
        expect(parse(), {'noAction': true});
      } else {
        expect(parse(), raw['value']);
      }
    });
  }
  test(
    'option values and literal suffixes remain owned and intent has no empty sentinel',
    () {
      for (final option in [
        '--agent-command',
        '-C',
        '--cwd',
        '-m',
        '--model',
        '--effort',
        '--permission-mode',
        '-p',
        '--print',
        '--output-format',
      ]) {
        final result = adaptResumeArguments([
          option,
          '--resume',
          '-r',
          'id',
          '--',
          '-r',
        ]);
        expect(result.intent.kind, ResumeKind.id);
        expect(result.intent.id, 'id');
        expect(result.arguments, [option, '--resume', '--', '-r']);
        final attached = adaptResumeArguments([
          option,
          '-raaa',
          '--resume=id',
          '--',
          '-cr',
        ]);
        expect(attached.intent.id, 'id');
        expect(attached.arguments, [option, '-raaa', '--', '-cr']);
      }
      expect(
        adaptResumeArguments(['--resume=']).intent.kind,
        ResumeKind.absent,
      );
      expect(adaptResumeArguments(['-c']).intent.kind, ResumeKind.continuing);
      expect(
        () => adaptResumeArguments(['-cr']),
        throwsA(isA<ResumeArgumentsError>()),
      );
      expect(
        () => adaptResumeArguments(['-rr']),
        throwsA(isA<ResumeArgumentsError>()),
      );
      final collision = adaptResumeArguments([
        '--resume',
        '-x',
        '__chord_resume_positional_0__',
      ]);
      expect(collision.arguments.first, '__chord_resume_positional_0___');
      expect(collision.positional(collision.arguments.first), '-x');
      expect(
        collision.positional(collision.arguments.last),
        '__chord_resume_positional_0__',
      );
    },
  );
}
