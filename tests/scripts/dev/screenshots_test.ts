import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseTeam } from '../../../src/teams.ts';

describe('CHD-407 R1 tester: screenshot team', () => {
  test('the dedicated team parses with the selected runtime and model pairs', async () => {
    const text = await readFile(
      new URL('../../../scripts/dev/screenshots_team.md', import.meta.url),
      'utf8',
    );
    const parsed = parseTeam('bugfix', text, ['claude', 'codex']);

    assert('team' in parsed);
    expect(parsed.team.lead.agent).toBe('claude');
    expect(parsed.team.lead.model).toBe('claude-opus-5-5');
    expect(
      parsed.team.members.map(({ name, agent, model }) => ({
        name,
        agent,
        model,
      })),
    ).toEqual([
      { name: 'tester', agent: 'claude', model: 'claude-opus-5-5' },
      { name: 'coder', agent: 'codex', model: 'gpt-6.1-sol' },
      { name: 'reviewer', agent: 'claude', model: 'claude-opus-5-5' },
    ]);
  });
});

describe('CHD-560 U2 tester: screenshot team modes', () => {
  for (const file of ['screenshots_team.md', 'screenshots_proposal.md']) {
    test(`${file} gives the coder auto while retaining the other roles' modes`, async () => {
      const text = await readFile(
        new URL(`../../../scripts/dev/${file}`, import.meta.url),
        'utf8',
      );
      const parsed = parseTeam('bugfix', text, ['claude', 'codex']);

      assert('team' in parsed);
      expect(parsed.team.lead.mode).toBe('default');
      expect(
        parsed.team.members.map(({ name, mode }) => ({ name, mode })),
      ).toStrictEqual([
        { name: 'tester', mode: 'acceptEdits' },
        { name: 'coder', mode: 'auto' },
        { name: 'reviewer', mode: 'plan' },
      ]);
    });
  }
});
