import { serveChord } from '../../../src/server/server.ts';
import { openSession } from '../../../src/session/session.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readPast, recordActions } from '../../../src/session/record.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Entry,
  type TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import type { ConversationEvent } from '../../../src/session/conversation.ts';
import { ElicitationRecord } from '../../../src/ui/dialogs/Form.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { recordSession } from '../../fixtures/records.ts';
import { FORM_SCHEMA } from '../../fixtures/forms.ts';
import type { PendingElicitation } from '../../../src/session/elicitations.ts';
import { enricherRelay } from '../../../src/session/enrich.ts';
import { ENRICHERS } from '../../../src/session/enrichers.ts';
import { type Questions, questionsOf } from '../../../src/session/questions.ts';
import { QuestionBox } from '../../../src/ui/dialogs/Questions.tsx';
import { CODEX_QUESTIONS, DROID_QUESTIONS } from '../../fixtures/questions.ts';
import { draw } from '../harness.tsx';
import {
  CTRL_O,
  DOWN,
  ESC,
  inputAsked,
  leader,
  until,
  send,
  TAB,
  withWindow,
} from '../app/render.tsx';

test("an agent's questions are asked one at a time, with their text and options, and the answers go back under its fields", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');

      const first = window.frame();

      expect(first).toContain('← ◉ Language   ○ Checks   ○ Submit →');
      expect(first).toContain('Which language should helper scripts use?');
      expect(first).toContain('❯ 1. Deno (TypeScript) (Recommended)');
      expect(first).toContain(
        'Runs from source with inline npm: and jsr: imports, no package manager',
      );
      expect(first).toContain('  2. Python');
      expect(first).toContain(
        'Note  Type your own answer, or add a note to the option you chose above (optional).',
      );
      expect(first).toContain(
        'Enter to pick · 1–2 · ↑↓ to move · ←→ or Tab for the questions · Esc to cancel',
      );

      // The first option, then Types and Tests on the second question.
      await window.press('\r');
      await window.shows('Which checks should run before a commit? (pick any)');
      await window.press(' ');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(' ');
      await window.shows('❯ [✔] 3. Tests');
      await window.press('\r');
      await window.shows('Checks    Types, Tests');
      expect(window.frame()).toContain(
        'Language  Deno (TypeScript) (Recommended)',
      );
      await window.press('\r');
      await window.shows(
        '{"question_0":"Deno (TypeScript) (Recommended)","question_1":["Types","Tests"]}',
      );
    },
    { rows: 40, columns: 120 },
  ));

test("a multi-select's rows stay in line as its ticks change", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press(TAB);
      await window.press(' ');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press(' ');
      await window.shows('❯ [✔] 3. Tests');

      const lines = window.frame().split('\n');
      const column = (text: string) =>
        lines.find((line) => line.includes(text))?.indexOf(text);

      expect(column('[ ] 2. Lint')).toBe(column('[✔] 1. Types'));
      expect(column('[✔] 3. Tests')).toBe(column('[✔] 1. Types'));
    },
    { rows: 40, columns: 120 },
  ));

test("codex's questions at 80 columns: its wait, a secret typed as dots, and Send out of reach until it has its answers", () =>
  withWindow(async (window) => {
    await send(window, 'askcodex');
    await inputAsked(window, 'fake asks you 2 questions');
    expect(window.frame()).toMatch(/answers itself in [45]:\d\d/);
    expect(window.frame()).toContain(
      '← * ◉ Next step   * ○ Token   ○ Submit →',
    );
    expect(window.frame()).toContain('Note  Additional answer or note');
    await window.press(TAB);
    await window.shows('Paste the API token for the staging deploy.');
    await window.type('sk-1');
    await window.shows('❯ ••••');
    await window.press(TAB);
    await window.shows('Next step  no answer yet, and fake needs one');
    expect(window.frame()).toContain('Token      ••••');
    expect(window.frame()).toContain('❯ 2. Skip these questions');
    expect(window.frame()).not.toContain('sk-1');
    await window.press(ESC);
    await window.shows('Elicitation answer: cancel');
  }));

test('a form with no questions read in it keeps the field table', () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);
    expect(window.frame()).toContain('❯ * Project name');
    expect(window.frame()).not.toContain('Submit →');
  }));

test('a Note placeholder too long for 80 columns is cut at its end', () =>
  withWindow(
    async (window) => {
      // Typed rather than sent: at 80x24 the call and the box push the
      // prompt's row off screen before it could be waited for.
      await window.type('askclaude');
      await window.press('\r');
      await inputAsked(window, 'fake asks you 2 questions');

      const note = window
        .frame()
        .split('\n')
        .find((line) => line.includes('Note  '));

      expect(note).toContain('Note  Type your own answer, or add a note to');
      expect(note).toMatch(/…\s*│$/);
    },
    { rows: 24, columns: 80 },
  ));

test('an answered box leaves a row per question under the turn, saying who asked', () =>
  withWindow(
    async (window) => {
      await send(window, 'askcodex');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press('2');
      await window.type('sk-1');
      await window.press('\r');
      await window.press('\r');
      await window.shows('⎿  fake asked · Next step  Review existing work');

      // Right under the prompt it answers, as a command's outcome is.
      const lines = window.frame().split('\n');
      const prompt = lines.findIndex((line) => line.includes('› askcodex'));

      expect(lines[prompt + 1]).toContain('⎿  fake asked · Next step');
      expect(window.frame()).toMatch(/^ +Token {6}\(hidden\)/m);

      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press(TAB);
      await window.press(TAB);
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('⎿  Language, Checks · Skipped');

      await send(window, 'askdroid');
      await inputAsked(window, 'fake asks you 3 questions');
      await window.press(ESC);
      await window.shows(
        '⎿  fake asked · Storage, Formats, Bucket · Cancelled',
      );
    },
    { rows: 40, columns: 120 },
  ));

test("a box withdrawn as the agent's wait runs out reads Timed out", () =>
  withWindow(async (window) => {
    await send(window, 'askcodexwait');
    await window.shows('⎿  fake asked · Next step, Token · Timed out');
    await window.shows('Elicitation answer: timed out');
  }));

test('a bracketed paste goes into the text row, a secret as dots', () =>
  withWindow(async (window) => {
    await send(window, 'askcodex');
    await inputAsked(window, 'fake asks you 2 questions');
    // On an option row it picks nothing.
    await window.paste('2');
    await window.press(TAB);
    await window.paste('sk-1');
    await window.shows('❯ ••••');
    await window.press(TAB);
    await window.shows('Token      ••••');
    expect(window.frame()).toContain('Next step  no answer yet');
  }));

test('the countdown runs from when the request came, not from when the box is drawn, and goes on as it is drawn again', async () => {
  const { questions } = askedCodex();
  const box = (now: number) => (
    <QuestionBox
      wait={{
        id: 'e1',
        mode: 'form',
        message: 'Codex needs your input to continue.',
        schema: { type: 'object', properties: {} },
        questions,
        at: 1_000,
      }}
      questions={questions}
      agent='codex'
      windowRows={24}
      width={80}
      active={false}
      now={() => now}
      onAnswer={() => {}}
    />
  );

  for (const [now, left] of [
    [1_000 + 60_000, 'answers itself in 4:00'],
    // Switched away and back two minutes later: drawn afresh.
    [1_000 + 180_000, 'answers itself in 2:00'],
  ] as const) {
    const drawn = await draw(box(now), { columns: 80, rows: 24 });

    expect(drawn.frame()).toContain(left);
    await drawn.unmount();
  }
});

/** codex's questions as the enrichers read them. */
function askedCodex(): { questions: Questions } {
  const [message] = enricherRelay(ENRICHERS).fromAgent({
    jsonrpc: '2.0',
    id: 1,
    method: 'elicitation/create',
    params: { ...CODEX_QUESTIONS, sessionId: 's' },
  });

  assert(message !== undefined && 'params' in message);

  const questions = questionsOf(message.params as typeof CODEX_QUESTIONS);

  assert(questions !== undefined);

  return { questions };
}

test("an option's description longer than an 80x24 box is cut, and the hint stays on screen", async () => {
  const long = Array.from({ length: 60 }, (_, index) => `word${index}`).join(
    ' ',
  );
  const questions: Questions = {
    agent: 'claude',
    questions: [
      {
        id: 'q',
        text: 'Which one?',
        options: [
          { value: 'a', title: 'First', description: long.repeat(4) },
          { value: 'b', title: 'Second' },
        ],
        multiSelect: false,
        required: false,
      },
    ],
  };
  const drawn = await draw(
    <QuestionBox
      wait={{
        id: 'e1',
        mode: 'form',
        message: 'Which one?',
        schema: { type: 'object', properties: {} },
      }}
      questions={questions}
      agent='claude'
      windowRows={24}
      width={80}
      active={false}
      onAnswer={() => {}}
    />,
    { columns: 80, rows: 24 },
  );
  const frame = drawn.frame();

  await drawn.unmount();
  expect(frame).toContain('❯ 1. First');
  expect(frame).toContain('…');
  expect(frame).toContain('↓ 1 more');
  expect(frame).toContain('Esc to cancel');
  expect(frame).toContain('╰');
});

test("claude's AskUserQuestion call draws the box's record in place of its own lines", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaude');
      await inputAsked(window, 'fake asks you 2 questions');
      await window.press('1');
      await window.press('\r');
      await window.press('\r');
      await window.shows('Elicitation answer: accept');

      const lines = window.frame().split('\n');
      const call = lines.findIndex((line) =>
        line.includes('Asking(for your input)'),
      );

      expect(lines[call + 1]).toContain(
        '⎿  Language  Deno (TypeScript) (Recommended)',
      );
      expect(lines[call + 2]).toContain('Checks    skipped');
      expect(window.frame()).not.toContain('User has answered your questions');
      expect(window.frame()).not.toContain('fake asked ·');
    },
    { rows: 40, columns: 120 },
  ));

describe('CHD-1 tester: question box lifecycle', () => {
  test('pasted digits do not pick, while notes and secret text reach the agent through their own fields', () =>
    withWindow(
      async (window) => {
        await send(window, 'askcodex');
        await inputAsked(window, 'fake asks you 2 questions');
        await window.paste('2\n3');
        expect(window.frame()).toContain('◉ Next step');
        await window.press('2');
        await window.press('\x1b[Z');
        await window.press(DOWN);
        await window.press(DOWN);
        await window.paste('tests\r\nfirst 2');
        await window.shows('Note  tests first 2');
        await window.press(TAB);
        await window.paste('2\nprivate');
        await window.shows('❯ •••••••••');
        expect(window.frame()).not.toContain('2 private');
        await window.press('\r');
        expect(window.frame()).toContain(
          'Review existing work · tests first 2',
        );
        await window.press('\r');
        await window.shows('Elicitation answer: accept');
        await window.shows('"next_note":"tests first 2"');
        await window.shows('"token":"2 private"');
      },
      { columns: 120, rows: 40 },
    ));

  test('switching sessions restores the question, secret draft and countdown without restarting it', () =>
    withWindow(
      async (window) => {
        await send(window, 'askcodex');
        await inputAsked(window, 'fake asks you 2 questions');
        await window.press('2');
        await window.type('first-token');
        await window.shows('❯ •••••••••••');

        const clockSeconds = () => {
          const match = window.frame().match(/answers itself in (\d+):(\d+)/);

          assert(match !== null);

          return Number(match[1]) * 60 + Number(match[2]);
        };

        const before = clockSeconds();

        await leader(window, 'c');
        await until('the second fake agent', () => window.pids.length === 2);
        await send(window, 'askdroid');
        await inputAsked(window, 'fake asks you 3 questions');
        await window.press('1');
        await window.press('1');
        await window.press('\r');
        await window.type('uploads');
        await window.press('\r');
        await window.press('\r');
        await window.shows('Elicitation answer: accept');
        // Each following prompt waits out the preceding turn's trailing updates.
        await send(window, 'late');
        await window.shows('Late, after the answer.');
        await send(window, 'text');
        await window.shows('Hello, world.');
        await leader(window, '1');
        await inputAsked(window, 'fake asks you 2 questions');
        expect(window.frame()).toContain('* ◉ Token');
        expect(window.frame()).toContain('❯ •••••••••••');
        expect(window.frame()).not.toContain('first-token');
        expect(clockSeconds()).toBeLessThan(before);
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
      },
      { columns: 80, rows: 24 },
    ));

  test('a short request withdrawn behind another session never reopens its box on return', () =>
    withWindow(
      async (window) => {
        await window.shows('? for shortcuts');
        await leader(window, 'c');
        await until('the second fake agent', () => window.pids.length === 2);

        const session = window.session();
        let request: PendingElicitation | undefined;

        assert(session !== undefined);

        const unsubscribe = session.elicitations.subscribe((pending) => {
          request = pending;
        });

        try {
          await send(window, 'askcodexwait');
          await leader(window, '1');
          await until(
            'the background request to withdraw',
            () => request?.signal.aborted === true,
          );
          await leader(window, '2');
          await window.shows('Elicitation answer: timed out');
          expect(window.frame()).not.toContain('fake asks you 2 questions');
          expect(window.frame()).not.toContain('answers itself in');
        } finally {
          unsubscribe();
        }
      },
      { columns: 80, rows: 24 },
    ));

  test('every tall option stays reachable with its title, clipped end and cancel hint at 80x24', async () => {
    const questions: Questions = {
      agent: 'claude',
      questions: [
        {
          id: 'q',
          text: 'Pick a destination.',
          required: false,
          multiSelect: false,
          options: Array.from({ length: 8 }, (_, index) => ({
            value: String(index),
            title: `Destination ${index + 1}`,
            description: `Description ${index + 1} `.repeat(100),
          })),
        },
      ],
    };
    const drawn = await draw(
      <QuestionBox
        wait={{
          id: 'tall',
          mode: 'form',
          message: 'Pick',
          schema: { type: 'object', properties: {} },
        }}
        questions={questions}
        agent='fake'
        windowRows={24}
        width={80}
        active
        onAnswer={() => {}}
      />,
      { columns: 80, rows: 24 },
    );

    try {
      for (let index = 0; index < 8; index++) {
        const frame = drawn.frame();

        expect(frame).toContain(`❯ ${index + 1}. Destination ${index + 1}`);
        expect(frame).toContain('…');
        expect(frame).toContain('Esc to cancel');
        expect(frame).toContain('╰');
        expect(frame.split('\n').length).toBeLessThanOrEqual(24);
        await drawn.write(DOWN);
      }
    } finally {
      await drawn.unmount();
    }
  });
});

describe('CHD-1 tester: question record rendering', () => {
  test('a secret renders hidden live and from the saved record that omits its value, at both widths', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-question-record-'));
    const stateDir = join(dir, 'state');
    const events: ConversationEvent[] = [];

    try {
      await recordSession({
        stateDir,
        cwd: dir,
        command: fakeAgentCommand(),
        prompts: ['askcodex'],
        answer: {
          action: 'accept',
          content: {
            next: 'Review existing work',
            next_note: 'tests first',
            token: 'record-secret-for-tests',
          },
        },
        heard: (event) => events.push(event),
      });

      const [file] = await readRecords(stateDir);

      assert(file !== undefined);

      const lines = await readPast(file.path);
      const answer = lines.find((entry) => entry.type === 'answered');
      const replay = recordActions(lines)
        .filter((action): action is TranscriptAction => action.type !== 'usage')
        .reduce(reduceTranscript, emptyTranscript);
      const types = new Set([
        'prompt',
        'update',
        'elicitation_requested',
        'elicitation_settled',
        'cancel',
        'result',
      ]);
      const live = events
        .filter((event): event is TranscriptAction => types.has(event.type))
        .reduce(reduceTranscript, emptyTranscript);
      const recorded = replay.entries.find(
        (entry) => entry.kind === 'elicitation',
      );
      const current = live.entries.find(
        (entry) => entry.kind === 'elicitation',
      );

      assert(answer?.type === 'answered' && answer.answer.type === 'accepted');
      expect(answer.answer.content).toStrictEqual({
        next: 'Review existing work',
        next_note: 'tests first',
      });
      assert(
        recorded?.kind === 'elicitation' && current?.kind === 'elicitation',
      );
      expect(current.content?.token).toBe('record-secret-for-tests');
      expect(recorded.content?.token).toBeUndefined();

      for (const entry of [current, recorded]) {
        for (const columns of [80, 120]) {
          for (const expanded of [false, true]) {
            const rendered = await draw(
              <ElicitationRecord
                entry={entry}
                agent='codex'
                expanded={expanded}
              />,
              { columns, rows: 24 },
            );

            try {
              const frame = rendered.frame();

              expect(frame).toContain('codex asked · Next step');
              expect(frame).toContain('Review existing work · tests first');
              expect(frame).toMatch(/Token +\(hidden\)/);
              expect(frame).not.toContain('record-secret-for-tests');
            } finally {
              await rendered.unmount();
            }
          }
        }
      }
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  test('droid records show option titles, combine its own answer and label an unanswered question skipped', async () => {
    const [message] = enricherRelay(ENRICHERS).fromAgent({
      jsonrpc: '2.0',
      id: 1,
      method: 'elicitation/create',
      params: { ...DROID_QUESTIONS, sessionId: 's' },
    });

    assert(message !== undefined && 'params' in message);

    const questions = questionsOf(message.params as typeof DROID_QUESTIONS);

    assert(questions !== undefined);

    const entry: Extract<Entry, { kind: 'elicitation' }> = {
      kind: 'elicitation',
      turnId: 't',
      outcome: 'accepted',
      wait: {
        id: 'droid',
        mode: 'form',
        message: DROID_QUESTIONS.message,
        schema: DROID_QUESTIONS.requestedSchema,
        questions,
      },
      content: {
        question_0: 'option_1',
        question_1: ['option_0', 'other'],
        question_1_other: 'HEIC',
      },
    };
    const rendered = await draw(
      <ElicitationRecord entry={entry} agent='droid' expanded={false} />,
      { columns: 80, rows: 24 },
    );

    try {
      const frame = rendered.frame();

      expect(frame).toMatch(/Storage +S3 bucket/);
      expect(frame).toMatch(/Formats +PNG, HEIC/);
      expect(frame).toMatch(/Bucket +skipped/);
      expect(frame).not.toContain('option_');
      expect(frame).not.toContain('Answered ·');
    } finally {
      await rendered.unmount();
    }
  });

  test('unanswered outcomes name all questions, while a record without questions keeps its old form summary', async () => {
    const { questions } = askedCodex();

    for (const [outcome, text] of [
      ['declined', 'Skipped'],
      ['cancelled', 'Cancelled'],
      ['timed_out', 'Timed out'],
    ] as const) {
      const rendered = await draw(
        <ElicitationRecord
          entry={{
            kind: 'elicitation',
            turnId: 't',
            outcome,
            wait: {
              id: 'e',
              mode: 'form',
              message: CODEX_QUESTIONS.message,
              schema: CODEX_QUESTIONS.requestedSchema,
              questions,
            },
          }}
          agent='codex'
          expanded={false}
        />,
        { columns: 80, rows: 24 },
      );

      try {
        expect(rendered.frame()).toContain(
          `codex asked · Next step, Token · ${text}`,
        );
      } finally {
        await rendered.unmount();
      }
    }

    const entry: Extract<Entry, { kind: 'elicitation' }> = {
      kind: 'elicitation',
      turnId: 't',
      outcome: 'accepted',
      wait: {
        id: 'generic',
        mode: 'form',
        message: 'Set up the deploy target',
        schema: FORM_SCHEMA,
      },
      content: { name: 'old-form', replicas: 2 },
    };

    for (const expanded of [false, true]) {
      const rendered = await draw(
        <ElicitationRecord entry={entry} agent='fake' expanded={expanded} />,
        { columns: 80, rows: 24 },
      );

      try {
        expect(rendered.frame()).toContain(
          'fake asked: Set up the deploy target',
        );
        expect(rendered.frame()).toContain('Answered · 2 fields');
        expect(rendered.frame()).not.toContain('fake asked ·');

        if (expanded) {
          expect(rendered.frame()).toMatch(/Project name +old-form/);
        }
      } finally {
        await rendered.unmount();
      }
    }
  });
});

test("claude's lone question reads Asking(<the question>) while its box is open and once answered", () =>
  withWindow(
    async (window) => {
      await send(window, 'askclaudeone');
      await inputAsked(window, 'fake asks you a question');
      // Above the open box too, as the person reads it while answering.
      expect(window.frame()).toContain(
        '⏺ Asking(Which language should helper scripts use?)',
      );
      await window.press('1');
      await window.press('\r');
      await window.shows('⏺ Asking(Which language should helper scripts use?)');
      expect(window.frame()).not.toContain('Which(language');
    },
    { rows: 40, columns: 120 },
  ));

describe('CHD-1 tester: task question collision in the window', () => {
  for (const action of ['accept', 'cancel'] as const) {
    test(`${action}: taskask keeps the parent call and nests one question record live and reopened`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'taskask');
            await inputAsked(window, 'fake asks you 2 questions');
            expect(window.frame()).toContain("The parent's own call.");

            if (action === 'accept') {
              await window.press('2');
              await window.press(' ');
              await window.press('\r');
              await window.press('\r');
            } else {
              await window.press(ESC);
            }

            await window.shows(
              'It is asking; I will read its report when it lands.',
            );
            await window.shows('Done');
            expect(window.frame()).not.toContain(
              'User has answered your questions',
            );
            expect(window.frame()).toContain("The parent's own call.");
            await window.press(CTRL_O);
            await window.shows(
              action === 'accept'
                ? 'Language  Python'
                : 'Language, Checks · Cancelled',
            );

            const live = window.frame();

            expect(
              live.split(
                action === 'accept'
                  ? 'Language  Python'
                  : 'Language, Checks · Cancelled',
              ),
            ).toHaveLength(2);
            expect(live).toContain(
              action === 'accept'
                ? 'User has answered your questions'
                : 'Tool use aborted',
            );
            expect(live).toContain("The parent's own call.");

            const records = await readRecords(join(window.dir, 'state'));
            const parent = records.find(
              (record) => record.parent === undefined,
            );

            assert(parent !== undefined);

            const resumed = await openSession({
              agent: 'fake',
              cwd: window.dir,
              agentCommand: fakeAgentCommand(undefined, '--resume-only'),
              resume: {
                sessionId: parent.sessionId,
                cwd: window.dir,
                record: parent.path,
              },
            });

            try {
              const transcript = resumed
                .history()
                .filter(
                  (event): event is TranscriptAction => event.type !== 'usage',
                )
                .reduce(reduceTranscript, emptyTranscript);
              const rootCall = transcript.entries.find(
                (entry) => entry.kind === 'tool' && entry.call.id === 'ask-1',
              );
              const task = transcript.entries.find(
                (entry) => entry.kind === 'subagent',
              );

              assert(rootCall?.kind === 'tool' && task?.kind === 'subagent');
              expect(rootCall.call.asked).toBeUndefined();
              expect(
                task.subagent.entries.filter(
                  (entry) => entry.kind === 'elicitation',
                ),
              ).toHaveLength(1);
              expect(
                transcript.entries.filter(
                  (entry) => entry.kind === 'elicitation',
                ),
              ).toHaveLength(0);

              for (const expanded of [false, true]) {
                const rendered = await draw(
                  <box>
                    {transcript.entries.map((entry, index) => (
                      <TranscriptEntry
                        key={index}
                        entry={entry}
                        turn={transcript.turn}
                        agent='fake'
                        expanded={expanded}
                        width={118}
                      />
                    ))}
                  </box>,
                  { columns: 120, rows: 80 },
                );

                try {
                  const frame = rendered.frame();

                  expect(frame).toContain("The parent's own call.");

                  if (expanded) {
                    expect(
                      frame.split(
                        action === 'accept'
                          ? 'Language  Python'
                          : 'Language, Checks · Cancelled',
                      ),
                    ).toHaveLength(2);
                    expect(frame).toContain(
                      action === 'accept'
                        ? 'User has answered your questions'
                        : 'Tool use aborted',
                    );
                  } else {
                    expect(frame).not.toContain(
                      'User has answered your questions',
                    );
                  }
                } finally {
                  await rendered.unmount();
                }
              }
            } finally {
              await resumed.close();
            }
          },
          { server, runtimes: ['fake'], rows: 80, columns: 120 },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('who a question box names (CHD-389)', () => {
  test("main's names its runtime; a task's names it as its call is headed", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await send(window, 'askclaude');
          await inputAsked(window, 'fake asks you 2 questions');
          expect(window.frame()).toMatch(/│ fake asks you 2 questions/);
          await window.press(ESC);
          await window.shows('Elicitation answer: cancel');
          await send(window, 'taskask');
          await window.shows(
            'Agent(Ask the person) · fake asks you 2 questions',
          );
        },
        { server, runtimes: ['fake'], rows: 40, columns: 120 },
      );
    } finally {
      await server.close();
    }
  });
});
