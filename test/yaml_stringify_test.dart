import 'dart:convert';
import 'dart:io';

import 'package:chord/yaml_stringify.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/fake.dart' show portPackageDir;

final _fixtures = p.join(
  portPackageDir(),
  'test',
  'fixtures',
  'yaml_stringify',
);

void main() {
  // Recorded from npm yaml 2.9.1, as the TypeScript chord wrote teams.
  final cases =
      (jsonDecode(File(p.join(_fixtures, 'cases.json')).readAsStringSync())
              as List)
          .cast<Map<String, Object?>>();

  test('the recorded cases are the original teams, quoting and blocks', () {
    expect(cases.map((each) => each['name']).take(4), [
      'original fixture bugfix',
      'original fake bugfix',
      'repository architects',
      'repository ship',
    ]);
    expect(cases, hasLength(greaterThan(100)));
  });

  group('writes what npm yaml 2.9.1 writes', () {
    for (final each in cases) {
      test('${each['name']}', () {
        expect(yamlStringify(each['value']!), each['yaml']);
      });
    }
  });

  test('a multi-line instruction stays a block a person can edit', () {
    expect(
      yamlStringify({
        'lead': {'instructions': 'Read the job.\nThen split it.\n'},
      }),
      'lead:\n  instructions: |\n    Read the job.\n    Then split it.\n',
    );
  });

  test('anything but a map, a list or a string is refused', () {
    expect(() => yamlStringify({'a': 1}), throwsArgumentError);
  });
}
