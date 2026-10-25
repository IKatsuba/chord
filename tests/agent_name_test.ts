import { expect, test } from 'bun:test';
import { agentNameProblem } from '../src/agent_name.ts';

test('agent names reject the delimiter and C0/DEL, keeping other characters', () => {
  for (const name of ['parser', 'bugfix 2', 'a\\b', "a'b"]) {
    expect(agentNameProblem(name)).toBeUndefined();
  }

  expect(agentNameProblem('a"b')).toBe('must not contain the character "');
});

test('each C0 and DEL control is named in the refusal', () => {
  for (const code of [...Array.from({ length: 32 }, (_, at) => at), 127]) {
    expect(agentNameProblem(`a${String.fromCharCode(code)}b`)).toBe(
      `must not contain the control character U+${code.toString(16).toUpperCase().padStart(4, '0')}`,
    );
  }

  expect(agentNameProblem('a\u0085b')).toBeUndefined();
});
