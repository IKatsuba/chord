import { expect, test } from 'bun:test';
import { agentNameProblem } from '../src/agent_name.ts';

test('agent names reject only the quote used to delimit @@ names', () => {
  for (const name of ['parser', 'bugfix 2', 'a\\b', "a'b"]) {
    expect(agentNameProblem(name)).toBeUndefined();
  }

  expect(agentNameProblem('a"b')).toBe('must not contain the character "');
});
