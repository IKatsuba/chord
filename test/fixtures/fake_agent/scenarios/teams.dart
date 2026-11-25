// Teams, as the original's scenarios/teams.ts: a session that hands the
// fake team `bugfix` a job through chord's `run_team`, twice for a second
// run; the lead's first turn, which opens `tester` and `coder`, reports to
// main and, in a second run, asks the first run's lead which files it
// holds; `tester`'s, which reports to its lead, messages `coder` directly
// and asks the person to run the tests; and `coder`'s, which messages
// `tester`. A team agent's first prompt is played by its part's role, as
// main.dart reads it, so the job reads as a real one.
import 'dart:convert';
import 'dart:io';

// The one import of the app's: the original's teams.ts reads a
// `--propose-team` file with the app's own parseTeam
// (`import { parseTeam } from '../../../../src/teams.ts'`), so this reads
// it with the port's.
import 'package:chord/teams.dart' as chord;

import '../options.dart';
import '../turn.dart';
import 'chord_tools.dart';
import 'tasks.dart';

/// A team agent's pace: 20 steps, a tenth of a second by default.
num get _teamStepMs => stepMs * 20;

/// The first run's job, as main writes it from the conversation.
const teamJob =
    'Issue 214: a string at the end of a line loses its closing quote. '
    'readString in src/parse/tokenize.ts stops at the newline before it '
    'consumes the quote. Add a test that fails for that reason, fix it, and '
    'have the diff reviewed. Report to me when it is done.';

/// The second run's job.
const secondJob =
    'Issue 219: parseDate in src/parse/date.ts reads "2026-02-30" as March 2. '
    'Add a test that fails for that reason, fix it, and have the diff '
    'reviewed. Report to me when it is done.';

/// What the lead opens `tester` with.
const testerPrompt =
    'Write a test in tests/parse/tokenize_test.ts that fails because a '
    'string at the end of a line loses its closing quote. Edit tests/ only. '
    'Tell me when it fails for that reason.';

/// What the lead opens `coder` with.
const coderPrompt =
    "You will edit src/parse/tokenize.ts, and only it, once tester's test "
    'fails. Read it now; change nothing yet.';

/// The lead's first report to main.
const leadReport =
    'On it. tester is writing a failing test in tests/parse/tokenize_test.ts; '
    'coder waits for it and will edit src/parse/tokenize.ts only. I will '
    "report when the test fails for the bug's own reason.";

/// What the lead opens `reviewer` with.
const reviewerPrompt =
    'Read the diff once coder has one, and the test with it. Edit nothing.';

/// What the lead opens each member with, by its name.
const _memberPrompts = {
  'tester': testerPrompt,
  'coder': coderPrompt,
  'reviewer': reviewerPrompt,
};

/// `tester`'s report to its lead.
const testerReport =
    'It fails for that reason: "a" at the end of a line comes back as "a, '
    'with no closing quote. Only tests/parse/tokenize_test.ts changed.';

/// `tester`'s message to `coder`, not through the lead.
const testerToCoder =
    'The failing test is in tests/parse/tokenize_test.ts and stays mine. '
    'Fix readString so it passes; I will run the suite after.';

/// `coder`'s message to `tester`.
const coderToTester =
    'Reading src/parse/tokenize.ts now. Tell me when your test fails.';

/// Names as a sentence says them: `tester and coder`, `a, b and c`.
String _spoken(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// The team `propose` proposes: the one `--propose-team` names, read as
/// chord reads a team file, else the fake's own.
Map<String, Object?> _proposedTeam() {
  final file = proposeTeam;
  if (file == null) return proposedTeam;
  final read = chord.parseTeam(
    proposedTeam['name']! as String,
    File(file).readAsStringSync(),
    const ['claude', 'codex'],
  );
  final team = read.team;
  if (team == null) throw StateError('--propose-team: ${read.problem}');
  return {
    'name': proposedTeam['name'],
    'description': team.description,
    'lead': team.lead.toMap(),
    'members': [for (final member in team.members) member.toMap()],
    'body': team.body,
  };
}

/// A team agent's part, by its session, as main read it off the prompt.
final teamParts = <String, ({String from, String text})>{};

/// The runs a lead's part names as open beside it, by their leads' names.
List<String> _otherRuns(String text) {
  final named = RegExp(
    r'by these names: ([^\n]*)\.$',
    multiLine: true,
  ).firstMatch(text)?.group(1);
  return named == null ? [] : named.split(RegExp(r', (?:and )?| and '));
}

/// A call of the agent's own, done after a step.
Future<void> _work(Turn turn, String title, String output) async {
  final toolCallId = turn.callId('execute');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': title,
    'kind': 'edit',
    'status': 'in_progress',
  });
  await pause(turn.signal, _teamStepMs * 5);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': output},
      },
    ],
  });
}

/// Asks the person to run [command], and says how they answered.
Future<String> _askToRun(Turn turn, String command) async {
  final toolCallId = turn.callId('execute');
  final toolCall = {
    'toolCallId': toolCallId,
    'title': '`$command`',
    'kind': 'execute',
    'status': 'pending',
  };
  await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

  final answer = await turn.client.request('session/request_permission', {
    'sessionId': turn.sessionId,
    'toolCall': toolCall,
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
      {'optionId': 'always', 'name': 'Always allow', 'kind': 'allow_always'},
      {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
    ],
  });
  final outcome = (answer['outcome'] as Map?) ?? const {};
  if (outcome['outcome'] == 'cancelled') return 'cancelled';

  final allowed = outcome['optionId'] != 'deny';
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': allowed ? 'completed' : 'failed',
    if (allowed)
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': '1 failed, 213 passed'},
        },
      ],
  });
  await turn.say([
    allowed
        ? 'The suite fails only where the new test does.'
        : 'Not run; I will ask bugfix how to go on.',
  ]);
  return 'end_turn';
}

/// Says the session has no chord server and ends the turn.
Future<String> _noServer(Turn turn) async {
  await turn.say(['No chord server in this session.']);
  return 'end_turn';
}

/// Hands team `bugfix` [job], then says where its reports will come.
Future<String> handOver(Turn turn, String job) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'list_teams', {});
    final answer = await callChord(turn, client, 'run_team', {
      'team': 'bugfix',
      'job': job,
    });
    final name = answer == null ? null : (jsonDecode(answer) as Map)['name'];
    await turn.say([
      name == null
          ? 'chord did not start the team.'
          : '$name has the job. Its lead will report here; you can look in '
                'with ↓.',
    ]);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// How bugfix works, as the proposal's body has it.
const _proposedBody = '''# How bugfix works

1. The lead reads the job, finds the files involved, and names who may edit which before anyone starts.
2. tester writes a test that fails for the bug's own reason. It edits `tests/` only, and reports the failure.
3. coder fixes the code so that test passes. It edits only the files the lead named for it, and never `tests/`.
4. reviewer reads the diff and edits nothing. If it finds a problem, the lead hands it back to coder.
5. tester runs the whole suite once more, and the lead reports to main.

## Who edits what

- One writer per file at a time. Before a member starts, the lead tells it which files are its own.
- A member that needs a file it does not own asks its owner directly, and tells the lead what they agreed.
- Another run of a team may be working in this directory: the leads agree on files among themselves.
- Nobody commits. The person commits.

## Reporting

The lead writes to main when it needs a decision only the person can make, when the job is done, and when it cannot be done.''';

/// The team the fake proposes first, as `propose_team` takes it.
const proposedTeam = <String, Object?>{
  'name': 'bugfix',
  'description':
      'Fixes a bug end to end: a failing test first, then the fix, then a '
      'review of the diff.',
  'lead': {
    'agent': 'claude',
    'model': 'opus',
    'mode': 'default',
    'instructions':
        'Read the job and the code it points at until you can '
        'name the cause and the files involved. Open tester first, coder '
        "once tester's test fails, and reviewer last, on the diff.",
  },
  'members': [
    {
      'name': 'tester',
      'role': 'Writes the failing test, then proves the fix',
      'agent': 'claude',
      'model': 'sonnet',
      'mode': 'acceptEdits',
      'instructions':
          'Write the smallest test that fails because of the '
          'bug, and run it to show that.',
    },
    {
      'name': 'coder',
      'role': 'Writes the fix, in the files the lead names',
      'agent': 'codex',
      'model': 'gpt-5.3-codex',
      'mode': 'auto',
      'instructions':
          'Make the failing test pass with the smallest change. '
          'Do not touch tests.',
    },
    {
      'name': 'reviewer',
      'role': 'Reads the diff and edits nothing',
      'agent': 'claude',
      'model': 'opus',
      'mode': 'plan',
      'instructions': 'Read `git diff` and the test. Never edit a file.',
    },
  ],
  'body': _proposedBody,
};

List<Map<String, Object?>> get _proposedMembers => [
  for (final member in proposedTeam['members']! as List)
    (member as Map).cast<String, Object?>(),
];

/// The team changed as the person asked: reviewer on codex, and tester
/// running the suite without asking.
final Map<String, Object?> changedTeam = {
  ...proposedTeam,
  'members': [
    for (final member in _proposedMembers)
      member['name'] == 'tester'
          ? {...member, 'mode': 'bypassPermissions'}
          : member['name'] == 'reviewer'
          ? {
              ...member,
              'agent': 'codex',
              'model': 'gpt-5.3-codex',
              'mode': 'read-only',
            }
          : member,
  ],
  'body': _proposedBody.replaceFirst(
    '5. tester runs the whole suite once more,',
    '5. tester runs the whole suite once more, without asking,',
  ),
};

/// `bugfix` with efforts, as CHD-356 drew it: the lead on high, tester on
/// medium, coder and reviewer on their runtime's own.
final Map<String, Object?> effortsTeam = {
  ...proposedTeam,
  'lead': {...(proposedTeam['lead']! as Map), 'effort': 'high'},
  'members': [
    for (final member in _proposedMembers)
      member['name'] == 'tester' ? {...member, 'effort': 'medium'} : member,
  ],
};

/// [effortsTeam] changed: tester on high and bypassPermissions, coder on
/// xhigh, reviewer read-only, so the table has each kind of `was`.
final Map<String, Object?> changedEffortsTeam = {
  ...effortsTeam,
  'members': [
    for (final member in (effortsTeam['members']! as List).cast<Map>())
      member['name'] == 'tester'
          ? {...member, 'effort': 'high', 'mode': 'bypassPermissions'}
          : member['name'] == 'coder'
          ? {...member, 'effort': 'xhigh'}
          : member['name'] == 'reviewer'
          ? {...member, 'mode': 'read-only'}
          : member,
  ],
};

/// The sessions whose last turn proposed a team, with what to propose
/// after: `proposeagain` or `proposeeffortsagain`. Their next words,
/// whatever they say, are what to change.
final proposing = <String, String>{};

/// As long as the fake waits for the person to answer the save box.
const _saveBoxMs = 3600000;

/// Proposes [team] through chord's `propose_team`, after [intro], and says
/// what came of it: where it was saved, or nothing, as the person will say
/// what to change.
Future<String> _propose(
  Turn turn,
  Map<String, Object?> team,
  String intro, [
  String again = 'proposeagain',
]) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await turn.say([intro]);
    final answer = await callChord(
      turn,
      client,
      'propose_team',
      team,
      timeout: _saveBoxMs,
    );
    proposing[turn.sessionId] = again;
    if (answer != null && answer.startsWith('Saved to ')) {
      final name = team['name'];
      await turn.say([
        '$name is saved for '
            '${answer.contains('.config') ? 'every project' : 'this project'}. '
            'Hand it a bug with /team run $name and the bug, or just '
            'tell me to hand one to $name.',
      ]);
    }
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// A lead's turn that opens `tester` on `text`, plays [after] with a way
/// to call chord, then says [said].
Future<String> _clearing(
  Turn turn,
  Future<void> Function(
    Future<String?> Function(String name, Map<String, Object?> arguments) call,
  )
  after,
  String said,
) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    Future<String?> call(String name, Map<String, Object?> arguments) =>
        callChord(turn, client, name, arguments);
    await call('open_agent', {'member': 'tester', 'prompt': 'text'});
    await after(call);
    await turn.say([said]);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> teamPlays = {
  // Proposes `bugfix` for the person to save.
  'propose': (turn) => _propose(
    turn,
    _proposedTeam(),
    'A lead on Opus to split the work, and three members, one for each '
    'step. Only one of them edits a file at a time.',
  ),

  // Proposes `bugfix` again, as the person's words after a proposal change
  // it: the reviewer on codex, the tester running the suite unasked.
  'proposeagain': (turn) => _propose(
    turn,
    changedTeam,
    'The reviewer on codex too, read-only, and tester in '
    'bypassPermissions, so it runs the suite without asking.',
  ),

  // Proposes `bugfix` with efforts, and on the person's words, a change to
  // them.
  'proposeefforts': (turn) => _propose(
    turn,
    effortsTeam,
    'The lead thinks hard, tester a little; the rest on their own.',
    'proposeeffortsagain',
  ),

  'proposeeffortsagain': (turn) => _propose(
    turn,
    changedEffortsTeam,
    'tester on high and bypassPermissions, coder on xhigh, and the '
        'reviewer read-only.',
    'proposeeffortsagain',
  ),

  // Hands the first job to `bugfix`.
  'team': (turn) => handOver(turn, teamJob),

  // A member and a task of main's asking the person at once (CHD-431).
  'teamtask': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'run_team', {
        'team': 'bugfix',
        'job': teamJob,
      });
      await callChord(turn, client, 'spawn_task', taskArgs);
      await turn.say(['The team and the task are both at work.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Hands the second job to `bugfix`, a second run while the first is open.
  'team2': (turn) => handOver(turn, secondJob),

  // The lead's first turn: opens `tester`, then `coder`, reports to main,
  // and asks each other run's lead which files it holds.
  'teamlead': (turn) async {
    final client = await chordClient(turn);
    final others = _otherRuns(teamParts[turn.sessionId]?.text ?? '');
    if (client == null) return _noServer(turn);
    try {
      for (final member in leadOpens) {
        await callChord(turn, client, 'open_agent', {
          'member': member,
          // A scenario's name for tester's prompt is played in place of
          // its role.
          'prompt':
              (member == 'tester' ? testerPlays : null) ??
              _memberPrompts[member] ??
              'Wait for my word.',
        });
      }
      for (final other in others) {
        await callChord(turn, client, 'send_message', {
          'to': other,
          'text':
              'This run keeps to src/parse/date.ts and '
              'tests/parse/date_test.ts. Which files do you hold?',
        });
      }
      await callChord(turn, client, 'send_message', {
        'to': 'main',
        'text': leadReport,
      });
      await turn.say([
        "${_spoken(leadOpens)} are open; I wait for tester's test.",
      ]);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A lead's job: open `tester`, clear it, then message it `teampartof`,
  // its first message in the fresh session (CHD-476).
  'leadclear': (turn) => _clearing(turn, (call) async {
    await call('clear_agent', {'to': 'tester'});
    await call('send_message', {'to': 'tester', 'text': 'teampartof'});
  }, 'tester was cleared.'),

  // A lead's job: open `tester`, then clear it twice at once while
  // messaging it `teampartof`: one clear is refused, the message waits for
  // the fresh session and goes there once (CHD-476).
  'leadclearrace': (turn) => _clearing(turn, (call) async {
    await Future.wait([
      call('clear_agent', {'to': 'tester'}),
      call('clear_agent', {'to': 'tester'}),
      call('send_message', {'to': 'tester', 'text': 'teampartof'}),
    ], eagerError: true);
  }, 'tester was cleared once.'),

  // A lead's job: open `tester`, then clear it, and say nothing to it.
  'leadclearonly': (turn) => _clearing(turn, (call) async {
    await call('clear_agent', {'to': 'tester'});
  }, 'tester was cleared.'),

  // Says whose team part the session's messages have carried, if any.
  'teampartof': (turn) async {
    final part = teamParts[turn.sessionId];
    await turn.say([
      part == null
          ? 'No team part reached this session.'
          : 'The team part from ${part.from} reached this session.',
    ]);
    return 'end_turn';
  },

  // `tester`'s first turn: the test written, a report to its lead, a word
  // to `coder` directly, then the suite, which asks the person.
  'teamtester': (turn) async {
    final client = await chordClient(turn);
    final lead = teamParts[turn.sessionId]?.from ?? 'bugfix';
    try {
      await _work(
        turn,
        'Write tests/parse/tokenize_test.ts',
        'Wrote 12 lines to tests/parse/tokenize_test.ts',
      );
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'to': lead,
          'text': testerReport,
        });
        await callChord(turn, client, 'send_message', {
          'to': 'coder',
          'text': testerToCoder,
        });
      }
    } finally {
      await client?.close();
    }
    await pause(turn.signal, _teamStepMs * 5);
    return _askToRun(turn, 'bun dev test tests/parse');
  },

  // `coder`'s first turn: a word to `tester`, then it waits.
  'teamcoder': (turn) async {
    final client = await chordClient(turn);
    try {
      await pause(turn.signal, _teamStepMs * 5);
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'to': 'tester',
          'text': coderToTester,
        });
      }
      await turn.say(["Waiting for tester's test."]);
    } finally {
      await client?.close();
    }
    return 'end_turn';
  },

  // `reviewer`'s first turn, for a lead that opens one: it waits for the
  // diff.
  'teamreviewer': (turn) async {
    await pause(turn.signal, _teamStepMs * 5);
    await turn.say(["Waiting for coder's diff."]);
    return 'end_turn';
  },
};
