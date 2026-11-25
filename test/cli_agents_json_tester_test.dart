import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('tester CTUI-100: agents JSON boundaries', () {
    late Directory root;
    late String config, here, there;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-agents-tester-');
      config = p.join(root.path, 'config');
      here = p.join(root.path, 'here');
      there = p.join(root.path, '界 😀 é');
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String file, Object value) => File(file)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(value));

    Future<({int code, String out, String err})> call(
      List<String> args, {
      int columns = 80,
    }) async {
      final out = StringBuffer(), err = StringBuffer();
      final result = await runCli(
        args,
        cwd: here,
        home: p.join(root.path, 'home'),
        environment: {'XDG_CONFIG_HOME': config},
        columns: columns,
        stdout: out,
        stderr: err,
        lookup: (_) async => null,
      );
      expect(result.launch, isNull);
      return (code: result.code, out: '$out', err: '$err');
    }

    test('cwd before and after agents is refused as a repeated option', () async {
      write(p.join(here, '.chord/settings.json'), {'agent': 'claude'});
      write(p.join(there, '.chord/settings.json'), {'agent': 'codex'});
      final parent = await call(['-C', there, 'agents', '--json']);
      final child = await call(['-C', here, 'agents', '-C', there, '--json']);
      expect(jsonDecode(parent.out)['preferred'], 'claude');
      expect(parent.code, 0);
      expect(child.code, 2);
      expect(child.out, '$chordHelp\n');
      expect(
        child.err,
        '\n  error: Option "-C" can only occur once, but was found several times.\n\n',
      );
    });

    test('project command repairs a user refusal and stays private', () async {
      const name = '界😀é"\\\nagent';
      write(p.join(config, 'chord/settings.json'), {
        'offeredAgents': [name],
        'agents': {
          name: {'command': 7},
        },
      });
      write(p.join(there, '.chord/settings.json'), {
        'agents': {
          name: {
            'command': ['private-command', 'private-token'],
          },
        },
      });
      final result = await call(['agents', '-C', there, '--json']);
      final value = jsonDecode(result.out) as Map;
      final row = (value['agents'] as List).cast<Map>().singleWhere(
        (row) => row['name'] == name,
      );
      expect(result.code, 0);
      expect(row['via'], 'settings');
      expect(row['startable'], isTrue);
      expect(row['offered'], isTrue);
      expect(row['found'], isNull);
      expect(result.out.split('\n'), hasLength(2));
      expect(result.out, isNot(contains('private-command')));
      expect(result.out, isNot(contains('private-token')));
      expect(result.err, contains('expected a string'));
      expect(value['problems'], isNotEmpty);
    });

    test('JSON output does not depend on terminal width', () async {
      final narrow = await call(['agents', '--json'], columns: 1);
      for (final width in [0, 80, 120]) {
        final result = await call(['agents', '--json'], columns: width);
        expect(result.out, narrow.out);
        expect(result.err, narrow.err);
        expect(result.code, 0);
      }
    });
  });
}
