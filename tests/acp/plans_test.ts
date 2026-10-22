import { expect, test } from 'bun:test';
import { cursorPlan, grokPlan } from '../../src/acp/plans.ts';

const TODO = { id: 'read', content: 'Read it', status: 'pending' } as const;

test("cursor's create_plan reads its plan, name, overview, todos and phases; anything else stays out (CHD-437)", () => {
  expect(
    cursorPlan({
      toolCallId: 'call-1',
      name: 'Route',
      overview: 'Split it.',
      plan: '# Route',
      todos: [TODO],
      phases: [{ name: 'Read', todos: [TODO] }],
      isProject: true,
    }),
  ).toStrictEqual({
    agent: 'cursor',
    toolCallId: 'call-1',
    plan: '# Route',
    name: 'Route',
    overview: 'Split it.',
    todos: [TODO],
    phases: [{ name: 'Read', todos: [TODO] }],
  });
  expect(
    cursorPlan({ toolCallId: 'call-1', plan: '', todos: [] }),
  ).toStrictEqual({
    agent: 'cursor',
    toolCallId: 'call-1',
    plan: '',
    todos: [],
  });
});

test('a create_plan that does not read as cursor documents it reads as none, so it is answered cancelled', () => {
  for (const params of [
    undefined,
    'plan',
    { plan: '# Route', todos: [] },
    { toolCallId: 'call-1', todos: [] },
    { toolCallId: 'call-1', plan: '# Route' },
    { toolCallId: 'call-1', plan: '# Route', todos: 'three' },
    {
      toolCallId: 'call-1',
      plan: '# Route',
      todos: [{ ...TODO, status: 'done' }],
    },
    {
      toolCallId: 'call-1',
      plan: '# Route',
      todos: [],
      phases: [{ name: 'Read', todoIds: ['read'] }],
    },
  ]) {
    expect(cursorPlan(params)).toBe(undefined);
  }
});

test("grok's exit_plan_mode reads its session, call and plan, with or without a plan (CHD-457)", () => {
  expect(
    grokPlan({ sessionId: 's', toolCallId: 'c', planContent: '# Route' }),
  ).toStrictEqual({
    agent: 'grok',
    sessionId: 's',
    toolCallId: 'c',
    plan: '# Route',
  });
  expect(grokPlan({ sessionId: 's', toolCallId: 'c' })).toStrictEqual({
    agent: 'grok',
    sessionId: 's',
    toolCallId: 'c',
  });

  for (const params of [
    { toolCallId: 'c' },
    { sessionId: 's' },
    { sessionId: 's', toolCallId: 'c', planContent: 3 },
  ]) {
    expect(grokPlan(params)).toBe(undefined);
  }
});
