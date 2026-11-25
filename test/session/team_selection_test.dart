// A run's selection checked and frozen, and its receipt: the original's
// tests/session/team_selection_test.ts.
import 'dart:convert';

import 'package:chord/session/team_selection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:test/test.dart';

const _saved = Team(
  description: 'Selection fixture.',
  lead: TeamLead(
    agent: 'codex',
    model: 'old-model',
    mode: 'old-mode',
    effort: 'high',
    instructions: 'Lead exactly as written.\nKeep permissions.',
  ),
  members: [
    TeamMember(
      name: 'reviewer',
      role: 'Review byte for byte',
      instructions: 'Read-only review.\nDo not edit.',
      agent: 'codex',
      model: 'old-model',
      mode: 'old-mode',
    ),
  ],
  body: '# Handoffs\n\nPreserve QA and permission requirements.\n',
);
const _runtimes = ['codex', 'claude'];
const _reason = 'Preserve every role and permission; capacity is unknown.';

Team _withLead(Team team, TeamLead lead) => Team(
  description: team.description,
  lead: lead,
  members: team.members,
  body: team.body,
);

TeamLead _lead({String? agent, String? model, String? mode, String? effort}) =>
    TeamLead(
      agent: agent ?? _saved.lead.agent,
      model: model ?? _saved.lead.model,
      mode: mode ?? _saved.lead.mode,
      effort: effort ?? _saved.lead.effort,
      instructions: _saved.lead.instructions,
    );

TeamMember _reviewer({
  String? agent,
  String? model,
  String? mode,
  String? effort,
}) {
  final member = _saved.members.single;
  return TeamMember(
    name: member.name,
    role: member.role,
    agent: agent ?? member.agent,
    model: model ?? member.model,
    mode: mode ?? member.mode,
    effort: effort ?? member.effort,
    instructions: member.instructions,
  );
}

Team _withMember(TeamMember member) => Team(
  description: _saved.description,
  lead: _saved.lead,
  members: [member],
  body: _saved.body,
);

Team _with(Map<String, String> lead) => _withLead(
  _saved,
  _lead(
    agent: lead['agent'],
    model: lead['model'],
    mode: lead['mode'],
    effort: lead['effort'],
  ),
);

RoleConfig _role(String agent, {String? model, String? mode, String? effort}) =>
    (agent: agent, model: model, mode: mode, effort: effort);

String _noRun(String text) =>
    '$text. No run started. Choose a supported configuration.';

FrozenSelection _frozen(Object selection, {Map<String, Object?>? policy}) {
  final result = freezeSelection(
    _saved,
    selection,
    policy ?? const {},
    _runtimes,
  );
  expect(result.error, isNull);
  return result.frozen!;
}

void main() {
  group('CTUI-37 tester: selection snapshot boundaries', () {
    test('selection limits count UTF-16 and retain exact Unicode text', () {
      final id = '👩' * 64;
      expect(runChoiceOf({'model': id})!['model'], id);
      expect(runChoiceOf({'model': '$id👩'}), isNull);
      final reason = '界👩e\u0301' * 100;
      expect(reason.length, 500);
      expect(runSelectionOf({'reason': reason})!.reason, reason);
      expect(runSelectionOf({'reason': '${reason}x'}), isNull);
      expect(runSelectionOf({'reason': '\ufeff\u00a0\u2029'}), isNull);
    });

    test(
      'mutating submitted choices cannot revise a frozen run or receipt',
      () {
        final lead = {'model': 'new-model'};
        final member = {'mode': 'review-mode'};
        final submitted = <String, Object?>{
          'reason': _reason,
          'lead': lead,
          'members': {'reviewer': member},
        };
        final frozen = _frozen(submitted);
        final before = jsonEncode(
          selectionReceipt('immutable-run', (
            name: 'fixture',
            place: 'project',
          ), frozen),
        );
        lead['model'] = 'later-model';
        member['mode'] = 'later-mode';
        submitted['reason'] = 'later reason';
        expect(frozen.team.lead.model, 'new-model');
        expect(frozen.team.members.single.mode, 'review-mode');
        expect(frozen.saved, _saved);
        expect(
          jsonEncode(
            selectionReceipt('immutable-run', (
              name: 'fixture',
              place: 'project',
            ), frozen),
          ),
          before,
        );
      },
    );
  });

  group('strict per-run selection', () {
    test('unrepresentable inherited and overridden saved IDs fail before '
        'freezing', () {
      final long = 'x' * 129;
      for (final field in const ['agent', 'model', 'mode', 'effort']) {
        final source = _with({field: long});
        for (final override in [
          null,
          {
            'agent': 'claude',
            'model': 'sonnet',
            'mode': 'plan',
            'effort': 'medium',
          },
        ]) {
          expect(
            freezeSelection(
              source,
              {'reason': _reason, 'lead': ?override},
              const {},
              _runtimes,
            ).error,
            _noRun(
              'lead.$field: the saved value cannot fit a bounded run receipt',
            ),
          );
        }
        final member = _withMember(
          _reviewer(
            agent: field == 'agent' ? long : null,
            model: field == 'model' ? long : null,
            mode: field == 'mode' ? long : null,
            effort: field == 'effort' ? long : null,
          ),
        );
        expect(
          freezeSelection(
            member,
            {'reason': _reason},
            const {},
            _runtimes,
          ).error,
          _noRun(
            'reviewer.$field: the saved value cannot fit a bounded run receipt',
          ),
        );
      }
    });

    test('boundary-length saved IDs remain unchanged and produce a valid '
        'receipt', () {
      final source = _with({
        'model': 'm' * 128,
        'effort': 'e' * 128,
        'mode': 'p' * 128,
      });
      final result = freezeSelection(
        source,
        {'reason': _reason},
        const {},
        _runtimes,
      );
      final receipt = selectionReceipt('run', (
        name: 'fixture',
        place: 'project',
      ), result.frozen!);
      expect(((receipt['roles'] as List).first as Map)['saved'], {
        'agent': 'codex',
        'model': 'm' * 128,
        'effort': 'e' * 128,
        'mode': 'p' * 128,
      });
      expect(isSelectionReceipt(receipt), isTrue);
    });

    test('rejects unknown keys, null shorthand, blank reasons and oversized '
        'input', () {
      for (final value in [
        {'agent': null},
        {'model': null},
        {'mode': null},
        {'effort': null},
        {'command': 'other'},
        {'agent': ''},
        {'model': 'm' * 129},
      ]) {
        expect(runChoiceOf(value), isNull, reason: '$value');
      }
      for (final value in [
        <String, Object?>{},
        {'reason': ''},
        {'reason': ' \n '},
        {'reason': 'r' * 501},
        {'reason': _reason, 'extra': true},
        {
          'reason': _reason,
          'members': {
            for (var i = 0; i < 9; i++) 'member$i': <String, Object?>{},
          },
        },
      ]) {
        expect(runSelectionOf(value), isNull, reason: '$value');
      }
      expect(
        runSelectionOf({
          'reason': 'r' * 500,
          'lead': <String, Object?>{},
        })!.reason,
        hasLength(500),
      );
    });

    test('same-runtime omission inherits saved values and freezes an '
        'independent copy', () {
      final agents = ['codex'];
      final policy = <String, Object?>{
        'constraints': {'agents': agents},
      };
      final frozen = _frozen({
        'reason': _reason,
        'lead': {'model': 'new-model'},
      }, policy: policy);
      expect(frozen.team.lead, _lead(model: 'new-model'));
      expect(frozen.team.members, _saved.members);
      expect(frozen.team.body, _saved.body);
      agents.add('claude');
      expect(((frozen.policy['constraints'] as Map)['agents'] as List), [
        'codex',
      ]);
      expect(
        () => frozen.team.members.add(_reviewer()),
        throwsUnsupportedError,
      );
      expect(
        () => (frozen.policy['constraints'] as Map)['agents'] = <String>[],
        throwsUnsupportedError,
      );
    });

    test('runtime change requires destination model/mode and requested '
        'effort', () {
      for (final field in const ['model', 'mode', 'effort']) {
        final choice = {
          'agent': 'claude',
          'model': 'sonnet',
          'mode': 'plan',
          'effort': 'medium',
        }..remove(field);
        expect(
          freezeSelection(
            _saved,
            {'reason': _reason, 'lead': choice},
            const {},
            _runtimes,
          ).error,
          _noRun(
            'lead.$field: a runtime change requires an explicit destination '
            'value',
          ),
        );
      }
    });

    test('runtime change drops incompatible fields and never changes role '
        'prose', () {
      final frozen = _frozen({
        'reason': _reason,
        'lead': {
          'agent': 'claude',
          'model': 'sonnet',
          'mode': 'plan',
          'effort': 'medium',
        },
        'members': {
          'reviewer': {'agent': 'claude', 'model': 'sonnet', 'mode': 'plan'},
        },
      });
      expect(
        frozen.team.lead,
        _lead(agent: 'claude', model: 'sonnet', mode: 'plan', effort: 'medium'),
      );
      final member = frozen.team.members.single;
      expect(
        member,
        TeamMember(
          name: 'reviewer',
          role: 'Review byte for byte',
          agent: 'claude',
          model: 'sonnet',
          mode: 'plan',
          instructions: _saved.members.single.instructions,
        ),
      );
      expect(member.effort, isNull);
      expect(frozen.team.body, _saved.body);
    });

    test('unknown member names and unconfigured runtimes fail before any '
        'run', () {
      expect(
        freezeSelection(
          _saved,
          {
            'reason': _reason,
            'members': {'ghost': <String, Object?>{}},
          },
          const {},
          _runtimes,
        ).error,
        'Unknown selected member ghost. No run started.',
      );
      expect(
        freezeSelection(
          _saved,
          {
            'reason': _reason,
            'lead': {
              'agent': 'missing',
              'model': 'model',
              'mode': 'mode',
              'effort': 'high',
            },
          },
          const {},
          _runtimes,
        ).error,
        contains('lead.agent: the selected runtime is not configured'),
      );
    });

    test('hard allowlists cover unchanged members as well as explicitly '
        'overridden roles', () {
      expect(
        freezeSelection(
          _saved,
          {
            'reason': _reason,
            'lead': {'model': 'new-model'},
          },
          {
            'constraints': {
              'models': {
                'codex': ['new-model'],
              },
            },
          },
          _runtimes,
        ).error,
        contains(
          'reviewer.model: the choice is outside the configured allowlist',
        ),
      );
    });

    test('empty lists deny and omission adds no constraint or cross-runtime '
        'mode mapping', () {
      for (final constraints in [
        {'agents': <String>[]},
        {
          'models': {'codex': <String>[]},
        },
        {
          'modes': {'codex': <String>[]},
        },
      ]) {
        expect(
          freezeSelection(
            _saved,
            {'reason': _reason},
            {'constraints': constraints},
            _runtimes,
          ).error,
          isNotNull,
        );
      }
      expect(
        freezeSelection(
          _saved,
          {'reason': _reason},
          {
            'constraints': {
              'modes': {'claude': <String>[]},
            },
          },
          _runtimes,
        ).frozen,
        isNotNull,
      );
      expect(
        freezeSelection(
          _saved,
          {'reason': _reason},
          const {},
          _runtimes,
        ).frozen,
        isNotNull,
      );
      expect(
        freezeSelection(
          _saved,
          {'reason': _reason},
          {
            'constraints': {
              'modes': {
                'codex': ['plan'],
              },
            },
          },
          _runtimes,
        ).error,
        isNotNull,
      );
    });

    test('configured model/mode restrictions require explicit or inherited '
        'values', () {
      expect(
        validateSelectedRole('lead', _role('codex'), {
          'constraints': {
            'models': {
              'codex': ['old-model'],
            },
          },
        }, _runtimes),
        contains('lead.model'),
      );
      expect(
        validateSelectedRole('lead', _role('codex'), {
          'constraints': {
            'modes': {
              'codex': ['old-mode'],
            },
          },
        }, _runtimes),
        contains('lead.mode'),
      );
    });

    test('known unsupported mode has the design refusal; unknown capability '
        'remains unconfirmed', () {
      expect(
        validateSelectedRole(
          'reviewer',
          _role('claude', mode: 'plan'),
          const {},
          _runtimes,
          capabilities: (models: null, modes: ['auto'], efforts: null),
        ),
        _noRun('reviewer.mode: plan is not supported by the selected runtime'),
      );
      expect(
        validateSelectedRole(
          'reviewer',
          _role('claude', mode: 'plan'),
          const {},
          _runtimes,
        ),
        isNull,
      );
      expect(
        validateSelectedRole(
          'reviewer',
          _role('claude', model: 'sonnet'),
          const {},
          _runtimes,
          capabilities: (models: const [], modes: null, efforts: null),
        ),
        contains('reviewer.model'),
      );
    });

    test('only known support for the selected model can reject a new soft '
        'effort', () {
      final choice = _role('codex', model: 'new-model', effort: 'high');
      expect(
        validateSelectedRole(
          'lead',
          choice,
          const {},
          _runtimes,
          capabilities: (
            models: const [
              (id: 'old-model', efforts: ['low']),
              (id: 'new-model', efforts: null),
            ],
            modes: null,
            efforts: const ['low'],
          ),
          explicit: const {'effort': 'high'},
        ),
        isNull,
      );
      const none = (
        models: [(id: 'new-model', efforts: <String>[])],
        modes: null,
        efforts: null,
      );
      expect(
        validateSelectedRole(
          'lead',
          choice,
          const {},
          _runtimes,
          capabilities: none,
          explicit: const {'effort': 'high'},
        ),
        contains('lead.effort'),
      );
      expect(
        validateSelectedRole(
          'lead',
          choice,
          const {},
          _runtimes,
          capabilities: none,
        ),
        isNull,
      );
    });
  });

  group('selection decision receipts', () {
    SelectionReceipt receipt([String place = 'project']) => selectionReceipt(
      'run-1',
      (name: 'fixture', place: place),
      _frozen({'reason': _reason}),
    );

    test('unopened roles are planned, with no actual/default claims, '
        'decision read or resource warnings', () {
      final made = receipt();
      expect(
        [
          for (final role in (made['roles'] as List).cast<Map>())
            [role['name'], role['state'], role['actual']],
        ],
        [
          ['lead', 'planned', null],
          ['reviewer', 'planned', null],
        ],
      );
      expect(made['decisionRead'], isNull);
      expect(made['warnings'], isEmpty);
      expect(made['reason'], _reason);
      expect(
        ((made['roles'] as List).first as Map)['planned'],
        isNot(contains('instructions')),
      );
      final again = jsonDecode(jsonEncode(made));
      expect(isSelectionReceipt(again), isTrue);
      expect(again, made);
      expect(
        jsonEncode(((made['roles'] as List).first as Map)['planned']),
        '{"agent":"codex","model":"old-model","effort":"high","mode":"old-mode"}',
      );
    });

    test('unknown or mismatched exact model/mode refuses; actual effort may '
        'differ', () {
      final role = ((receipt()['roles'] as List).first as Map)
          .cast<String, Object?>();
      for (final actual in [
        {'model': null, 'mode': 'old-mode', 'effort': null},
        {'model': 'other', 'mode': 'old-mode', 'effort': 'high'},
        {'model': 'old-model', 'mode': null, 'effort': 'high'},
        {'model': 'old-model', 'mode': 'other', 'effort': 'high'},
      ]) {
        expect(confirmSelectionRole(role, actual)['state'], 'refused');
      }
      expect(
        confirmSelectionRole(role, {
          'model': 'other',
          'mode': 'old-mode',
          'effort': 'high',
        })['note'],
        'lead.model: the runtime did not confirm the requested model '
        'old-model.',
      );
      final confirmed = confirmSelectionRole(role, {
        'model': 'old-model',
        'mode': 'old-mode',
        'effort': 'low',
      }, 'Requested effort was refused.');
      expect(confirmed['state'], 'confirmed');
      expect((confirmed['actual'] as Map)['effort'], 'low');
      expect(confirmed['note'], 'Requested effort was refused.');
      expect(role['state'], 'planned');
      expect(role['actual'], isNull);
    });

    test('omitted model/mode can confirm startup while retaining unknown '
        'actual defaults', () {
      final role = <String, Object?>{
        'role': 'lead',
        'name': 'lead',
        'saved': {'agent': 'codex'},
        'planned': {'agent': 'codex'},
        'state': 'planned',
        'actual': null,
        'note': null,
      };
      expect(
        confirmSelectionRole(role, {
          'model': null,
          'mode': null,
          'effort': null,
        }),
        {
          ...role,
          'state': 'confirmed',
          'actual': {'model': null, 'mode': null, 'effort': null},
        },
      );
    });
  });

  test('cleanup warning is added once without mutating the plan', () {
    final receipt = selectionReceipt('actual-run', (
      name: 'fixture',
      place: 'project',
    ), _frozen({'reason': 'Preserve all instructions.'}));
    final changed = withSelectionCleanupWarning(receipt);
    expect(changed['warnings'], [agentCleanupUnverified]);
    expect(
      agentCleanupUnverified,
      'An attempted agent cleanup could not be verified; process exit is '
      'uncertain.',
    );
    expect(identical(withSelectionCleanupWarning(changed), changed), isTrue);
    expect(receipt['warnings'], isEmpty);
    expect(identical(changed['roles'], receipt['roles']), isTrue);
    expect(isSelectionReceipt(changed), isTrue);
  });

  test('a receipt is a run_team call\'s only when the call is the admitted '
      'one', () {
    final receipt = selectionReceipt('a1b2c3d4', (
      name: 'fixture',
      place: 'project',
    ), _frozen({'reason': _reason}));
    ChordCall call({String? asked, String id = 'a1b2c3d4'}) => ChordCall(
      tool: ChordTool.runTeam,
      input: const {'team': 'fixture', 'job': 'x'},
      asked: asked,
      answer: {'id': id, 'name': 'fixture', 'receipt': receipt},
    );
    expect(recordedSelection(call(asked: 'a1b2c3d4')), receipt);
    expect(recordedSelection(call()), isNull);
    expect(recordedSelection(call(asked: 'other')), isNull);
    expect(recordedSelection(call(asked: 'a1b2c3d4', id: 'other')), isNull);
    expect(
      recordedSelection(
        ChordCall(
          tool: ChordTool.runTeam,
          input: const {},
          asked: 'a1b2c3d4',
          answer: {
            'id': 'a1b2c3d4',
            'receipt': {...receipt, 'extra': 1},
          },
        ),
      ),
      isNull,
    );
  });
}
