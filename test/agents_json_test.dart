// `chord agents --json`'s object, as the original's tests/agents_test.ts
// checks agentsJson (CHD-598).
import 'package:chord/agents.dart';
import 'package:chord/settings.dart';
import 'package:test/test.dart';

const _listed = [
  ListedAgent(
    name: 'claude',
    title: 'Claude',
    start: 'npx claude',
    from: AgentRunner.npx,
  ),
  ListedAgent(
    name: 'fast',
    title: 'Fast',
    start: 'uvx fast',
    from: AgentRunner.uvx,
  ),
  ListedAgent(
    name: 'goose',
    title: 'goose',
    start: 'goose acp',
    from: AgentRunner.cli,
    found: true,
  ),
  ListedAgent(
    name: 'cursor',
    title: 'Cursor',
    start: 'cursor-agent acp',
    from: AgentRunner.cli,
    found: false,
  ),
  ListedAgent(
    name: 'codex',
    title: 'Codex',
    start: 'my-codex',
    from: AgentRunner.settings,
  ),
  ListedAgent(
    name: 'mine',
    title: null,
    start: 'mine --acp',
    from: AgentRunner.settings,
  ),
];

Map<String, Object?> _json({
  List<ListedAgent> listed = _listed,
  List<String>? offered,
  String preferred = 'claude',
  List<SettingsProblem> problems = const [],
  Set<String> refused = const {},
}) => agentsJson(
  listed: listed,
  offered: offered,
  preferred: preferred,
  problems: problems,
  refused: refused,
);

List<Map<String, Object?>> _agents(Map<String, Object?> json) =>
    (json['agents']! as List).cast<Map<String, Object?>>();

Map<String, Object?> _named(String name) =>
    _agents(_json()).firstWhere((agent) => agent['name'] == name);

Future<List<ListedAgent>> _catalog() => listedAgents((_) async => null);

void main() {
  test(
    'the object carries the version, the preferred agent and every field',
    () {
      expect(_json(preferred: 'goose'), {
        'version': 1,
        'preferred': 'goose',
        'agents': [
          {
            'name': 'claude',
            'title': 'Claude',
            'via': 'npx',
            'found': null,
            'offered': true,
            'startable': true,
          },
          {
            'name': 'fast',
            'title': 'Fast',
            'via': 'uvx',
            'found': null,
            'offered': true,
            'startable': true,
          },
          {
            'name': 'goose',
            'title': 'goose',
            'via': 'cli',
            'found': true,
            'offered': true,
            'startable': true,
          },
          {
            'name': 'codex',
            'title': 'Codex',
            'via': 'settings',
            'found': null,
            'offered': true,
            'startable': true,
          },
          {
            'name': 'mine',
            'title': null,
            'via': 'settings',
            'found': null,
            'offered': true,
            'startable': true,
          },
          {
            'name': 'cursor',
            'title': 'Cursor',
            'via': 'cli',
            'found': false,
            'offered': false,
            'startable': true,
          },
        ],
        'problems': <Object?>[],
      });
    },
  );

  test('its keys come in the original\'s order', () {
    final json = _json();

    expect(json.keys, ['version', 'preferred', 'agents', 'problems']);
    expect(_agents(json).first.keys, [
      'name',
      'title',
      'via',
      'found',
      'offered',
      'startable',
    ]);
  });

  test('found is a boolean for an own CLI only', () {
    expect(_named('goose')['found'], isTrue);
    expect(_named('cursor')['found'], isFalse);
    for (final name in ['claude', 'fast', 'codex', 'mine']) {
      expect(_named(name)['found'], isNull);
    }
  });

  test('with the setting, its names come first in its order, the rest in the '
      'catalog\'s', () {
    final agents = _agents(_json(offered: ['mine', 'cursor', 'claude']));

    expect(
      [for (final agent in agents) (agent['name'], agent['offered'])],
      [
        ('mine', true),
        ('cursor', true),
        ('claude', true),
        ('fast', false),
        ('goose', false),
        ('codex', false),
      ],
    );
  });

  test(
    'a name the setting gives that chord lacks is a problem without a file',
    () {
      const problem = SettingsProblem(
        '/config/chord/settings.json',
        'unknown key "x", ignored',
        kind: SettingsProblemKind.validation,
      );

      expect(
        _json(offered: ['zed', 'claude'], problems: [problem])['problems'],
        [
          {'file': problem.file, 'message': problem.message},
          {'message': '"offeredAgents": no agent named zed, left out'},
        ],
      );
    },
  );

  test(
    'a refused command leaves its agent unstartable and not offered, with or '
    'without the setting',
    () {
      for (final offered in [
        null,
        ['codex', 'claude'],
      ]) {
        final agents = _agents(_json(offered: offered, refused: {'codex'}));

        expect(agents.firstWhere((agent) => agent['name'] == 'codex'), {
          'name': 'codex',
          'title': 'Codex',
          'via': 'settings',
          'found': null,
          'offered': false,
          'startable': false,
        });
        expect(
          [
            for (final agent in agents)
              if (agent['startable'] == false) agent['name'],
          ],
          ['codex'],
        );
      }
    },
  );

  group('JSON catalog boundaries', () {
    test(
      'repeated offered and unknown names keep first order without duplicate '
      'rows or problems',
      () async {
        final listed = await _catalog();
        final result = _json(
          listed: listed,
          offered: ['goose', 'missing', 'claude', 'goose', 'missing'],
          preferred: 'missing-preference',
          refused: {'claude', 'refused-only'},
        );

        expect(result['preferred'], 'missing-preference');
        expect(
          [for (final agent in _agents(result)) agent['name']],
          [
            'goose',
            for (final agent in listed)
              if (agent.name != 'goose') agent.name,
          ],
        );
        expect(
          [
            for (final agent in _agents(result))
              if (agent['offered'] == true) agent,
          ],
          [
            {
              'name': 'goose',
              'title': 'goose',
              'via': 'cli',
              'found': false,
              'offered': true,
              'startable': true,
            },
          ],
        );
        expect(result['problems'], [
          {'message': '"offeredAgents": no agent named missing, left out'},
        ]);
      },
    );

    test(
      'an empty offered list leaves every catalog row present and unoffered',
      () async {
        final listed = await _catalog();
        final result = _json(listed: listed, offered: []);

        expect(
          [for (final agent in _agents(result)) agent['name']],
          [for (final agent in listed) agent.name],
        );
        expect(
          _agents(result).every((agent) => agent['offered'] == false),
          isTrue,
        );
        expect(result['problems'], isEmpty);
      },
    );
  });
}
