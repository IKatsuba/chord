import { describe, expect, test } from 'bun:test';
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

describe('CHD-437 U1 tester: protocol data stays lossless and malformed asks stay out', () => {
  test('cursor keeps all four todo states and independent phase data, including Unicode and empty text', () => {
    const todos = (
      ['pending', 'in_progress', 'completed', 'cancelled'] as const
    ).map((status, index) => ({
      id: String(index),
      content: index === 0 ? '' : 'Read 日本語 👩🏽‍💻',
      status,
    }));
    const params = {
      toolCallId: 'plan',
      sessionId: 'session',
      name: '',
      overview: '',
      plan: '',
      todos,
      phases: [
        {
          name: '',
          todos: [
            {
              id: '0',
              content: 'Different phase copy',
              status: 'pending' as const,
            },
          ],
        },
      ],
    };

    expect(cursorPlan(params)).toEqual({ agent: 'cursor', ...params });
    expect(params.todos[0]?.content).toBe('');
  });

  test('null and nested malformed known fields never become an approvable request', () => {
    for (const extra of [
      { sessionId: null },
      { name: 3 },
      { overview: [] },
      { phases: [{ name: 'Read', todos: [null] }] },
      { todos: [{ id: 'a', content: 'Read', status: null }] },
    ]) {
      expect(
        cursorPlan({ toolCallId: 'c', plan: '# Route', todos: [], ...extra }),
      ).toBeUndefined();
    }

    for (const extra of [
      { sessionId: null },
      { toolCallId: [] },
      { planContent: null },
    ]) {
      expect(
        grokPlan({ sessionId: 's', toolCallId: 'c', ...extra }),
      ).toBeUndefined();
    }
  });
});
