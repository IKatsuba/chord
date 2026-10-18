import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { askerParts } from '../../../src/ui/dialogs/asker.ts';
import { QuestionBox } from '../../../src/ui/dialogs/Questions.tsx';
import { ElicitationForm } from '../../../src/ui/dialogs/Form.tsx';
import { LinkPrompt } from '../../../src/ui/dialogs/Link.tsx';
import { enricherRelay } from '../../../src/session/enrich.ts';
import { ENRICHERS } from '../../../src/session/enrichers.ts';
import { questionsOf } from '../../../src/session/questions.ts';
import { CODEX_QUESTIONS } from '../../fixtures/questions.ts';
import { draw } from '../harness.tsx';
import { ESC, leader, promptRow, withWindow } from '../app/render.tsx';

const NAME =
  'Review every tokenizer boundary and preserve the original source locations through nested imports';
const TEAM = 'release validation across supported terminal sizes';
const member = askerParts({
  entries: [],
  picked: { name: NAME, team: TEAM, colour: '#c49cff' },
});
const task = askerParts({
  entries: [
    {
      kind: 'subagent',
      turnId: 't',
      subagent: {
        id: 'task',
        title: NAME,
        state: 'running',
        entries: [],
        plan: [],
        task: { name: NAME, runtime: 'fake', model: 'fake-small' },
      },
    },
  ],
  subagentId: 'task',
});

/** Borders split wrapped words onto different rows; compare the whole heading. */
function words(frame: string): string {
  return frame
    .replace(/[│╭╮╰╯─]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

describe('CHD-389 tester: headings wrap without losing the countdown or keys', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const [kind, asker, heading] of [
      ['task', task, `Agent(${NAME}) · fake`],
      ['member', member, `${NAME} · ${TEAM}`],
    ] as const) {
      test(`a long ${kind} and its countdown both remain readable at ${columns} columns`, async () => {
        const [message] = enricherRelay(ENRICHERS).fromAgent({
          jsonrpc: '2.0',
          id: 1,
          method: 'elicitation/create',
          params: { ...CODEX_QUESTIONS, sessionId: 's' },
        });

        assert(message && 'params' in message);

        const questions = questionsOf(message.params as typeof CODEX_QUESTIONS);

        assert(questions);

        const box = await draw(
          <QuestionBox
            wait={{
              id: 'questions',
              mode: 'form',
              message: CODEX_QUESTIONS.message,
              schema: { type: 'object', properties: {} },
              questions,
              at: 1_000,
            }}
            questions={questions}
            agent='fake'
            asker={asker}
            windowRows={rows}
            width={columns}
            active={false}
            now={() => 61_000}
            onAnswer={() => {}}
          />,
          { columns, rows },
        );

        try {
          const frame = box.frame();
          const countdown = 'answers itself in 4:00';
          // The countdown occupies the first row beside the heading, not its words.
          const headingOnly = words(frame.replace(countdown, ''));

          expect(headingOnly).toContain(`${heading} asks you 2 questions`);
          expect(frame).toContain(countdown);
          expect(frame).toContain('Esc to cancel');
          expect(
            frame.split('\n').every((row) => row.length <= columns),
          ).toBeTrue();
          expect(
            frame.split('\n').findIndex((row) => row.includes('asks you')),
          ).toBeGreaterThan(1);
        } finally {
          await box.unmount();
        }
      });
    }

    for (const kind of ['form', 'link'] as const) {
      test(`a long member's between-turn ${kind} keeps its full name, team and attendance hint at ${columns} columns`, async () => {
        const box = await draw(
          kind === 'form' ? (
            <ElicitationForm
              wait={{
                id: kind,
                mode: 'form',
                message: 'Release approval',
                schema: {
                  type: 'object',
                  properties: { name: { type: 'string' } },
                },
              }}
              agent='fake'
              asker={member}
              between
              held
              active={false}
              windowRows={rows}
              width={columns}
              onAnswer={() => {}}
            />
          ) : (
            <LinkPrompt
              wait={{
                id: kind,
                mode: 'url',
                message: 'Release approval',
                url: 'https://example.com/approve',
              }}
              agent='fake'
              asker={member}
              between
              held
              active={false}
              onAnswer={() => {}}
            />
          ),
          { columns, rows },
        );

        try {
          const frame = box.frame();
          const says =
            kind === 'form' ? 'asks for input' : 'asks you to open a link';

          expect(words(frame)).toContain(
            `${NAME} · ${TEAM} ${says} · between turns`,
          );
          expect(frame).toContain('ctrl+x a to answer');
          expect(frame).not.toContain('❯');
          expect(
            frame.split('\n').every((row) => row.length <= columns),
          ).toBeTrue();
        } finally {
          await box.unmount();
        }
      });

      test(`main's between-turn ${kind} keeps the heading while attention and Esc route correctly at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            const session = window.session();

            assert(session);

            const answer = session.elicitations.handler(
              kind === 'form'
                ? {
                    sessionId: session.id,
                    mode: 'form',
                    message: 'Release approval',
                    requestedSchema: {
                      type: 'object',
                      properties: { name: { type: 'string' } },
                    },
                  }
                : {
                    sessionId: session.id,
                    mode: 'url',
                    message: 'Release approval',
                    url: 'https://example.com/approve',
                    elicitationId: 'release-link',
                  },
              new AbortController().signal,
            );
            const says =
              kind === 'form' ? 'asks for input' : 'asks you to open a link';
            const heading = `main ${says} · between turns`;

            await window.shows(heading);
            await window.type('draft kept');
            expect(promptRow(window)).toContain('draft kept');
            expect(window.frame()).not.toContain('❯');
            await leader(window, 'a');
            await window.shows('❯');
            expect(window.frame()).toContain(heading);
            await window.press(ESC);
            expect(await answer).toStrictEqual({ action: 'cancel' });
            await window.shows('› draft kept');
            expect(promptRow(window)).toContain('draft kept');
          },
          { columns, rows },
        ));
    }
  }
});
