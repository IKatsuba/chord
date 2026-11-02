import { expect, test } from 'bun:test';
import {
  type ListedTeam,
  ranNote,
  stoppedLine,
  teamCommand,
  teamRefusal,
  type TeamWords,
} from '../../src/session/team_command.ts';

const WORDS: TeamWords = {
  whichRun: 'which run, host?',
  closedLead: 'the host has it',
  closedRun: 'the host has them',
};

test('/team reads its form, then a name, then the rest', () => {
  expect(teamCommand('', WORDS)).toStrictEqual({ form: 'list' });
  expect(teamCommand('new fixes bugs', WORDS)).toStrictEqual({
    form: 'new',
    words: 'fixes bugs',
  });
  expect(teamCommand('show bugfix', WORDS)).toStrictEqual({
    form: 'show',
    name: 'bugfix',
  });
  expect(teamCommand('run bugfix issue 214', WORDS)).toStrictEqual({
    form: 'run',
    name: 'bugfix',
    job: 'issue 214',
  });
  expect(teamCommand('stop bugfix  2', WORDS)).toStrictEqual({
    form: 'stop',
    name: 'bugfix 2',
  });
});

test("/team stop with no run answers in the host's words, the rest in /team's", () => {
  expect(teamCommand('stop', WORDS)).toStrictEqual({
    form: 'refused',
    problem: 'which run, host?',
  });
  expect(teamCommand('show', WORDS)).toStrictEqual({
    form: 'refused',
    problem: 'Which team? /team lists them',
  });
  expect(teamCommand('run bugfix', WORDS)).toStrictEqual({
    form: 'refused',
    problem: '/team run bugfix takes the job after the name',
  });
  expect(teamCommand('nope', WORDS)).toStrictEqual({
    form: 'refused',
    problem: '/team has no nope; it takes list, new, show, run or stop',
  });
});

test("what /team stop says ends in the host's words", () => {
  expect(stoppedLine('bugfix', [], WORDS)).toStrictEqual(
    'Stopped bugfix: its lead is closed · the host has it',
  );
  expect(stoppedLine('bugfix', ['tester', 'coder'], WORDS)).toStrictEqual(
    'Stopped bugfix: its lead, tester, and coder are closed · the host has them',
  );
});

test('a team not found, or broken, is refused; a good one is not', () => {
  const found = (extra: object) =>
    ({ name: 'triage', shown: 'triage.md', ...extra }) as ListedTeam;

  expect(teamRefusal('nope', undefined)).toStrictEqual(
    'No team named nope · /team lists them',
  );
  expect(teamRefusal('triage', found({ problem: 'no lead' }))).toStrictEqual(
    'triage.md is not a team chord can run:\nno lead',
  );
  expect(teamRefusal('triage', found({ team: {} }))).toBe(undefined);
});

test('the note to main names the job, the lead and how to reach it', () => {
  expect(ranNote('bugfix', 'bugfix 2', 'issue 214')).toStrictEqual(
    'The person handed team bugfix this job: "issue 214". Its lead is ' +
      '@bugfix 2 and reports to you; send_message reaches it.',
  );
});
