import { expect, test } from 'bun:test';
import { chooseAgentAtStart } from '../../../src/ui/app/startup_choice.ts';

const plain = { named: undefined, stdinTTY: true, stdoutTTY: true };

test('every unnamed new interactive invocation asks even when it has a configured default', () => {
  expect(chooseAgentAtStart(plain)).toBe(true);
});

test.each([
  { named: 'fake' },
  { agentCommand: 'fixture' },
  { print: '' },
  { continue: true },
  { resume: true as const },
  { resume: 'recorded' },
  { stdinTTY: false },
  { stdoutTTY: false },
])('the existing route is retained for %j', (route) => {
  expect(chooseAgentAtStart({ ...plain, ...route })).toBe(false);
});
