import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from '../app/child_window.tsx';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { useState } from 'react';
import { FORM_SCHEMA } from '../../fixtures/forms.ts';
import { draw } from '../harness.tsx';
import type { ElicitationReply } from '../../../src/session/elicitations.ts';
import { DROID_QUESTIONS } from '../../fixtures/questions.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  GATE,
  GATE_RELEASE,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { ElicitationForm } from '../../../src/ui/dialogs/Form.tsx';
import {
  CTRL_C,
  CTRL_O,
  DOWN,
  END,
  ESC,
  inputAsked,
  leader,
  quitAll,
  send,
  TAB,
  until,
  UP,
  withWindow,
} from '../app/render.tsx';

test("a form takes the prompt box's place, and typing goes to its field", () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);

    const frame = window.frame();

    expect(frame).toContain('Waiting for your input…');
    expect(frame).toContain('Set up the deploy target');
    expect(frame).toContain('❯ * Project name');
    expect(frame).toContain('✔ Replicas       2');
    expect(frame).toContain('☐ No');
    expect(frame).toContain('Accept   Decline');
    expect(!frame.includes('│ ›'), 'the prompt box stayed').toBeTruthy();
    await window.type('web');
    await window.shows('Project name   web');
    await window.press(ESC);
    await window.shows('⎿  Cancelled');
    await window.shows('Elicitation answer: cancel');
    // The keys were the form's: the prompt box comes back empty.
    await window.shows('│ ›');
    expect(
      !window.frame().includes('› web'),
      'the draft took the keys',
    ).toBeTruthy();
  }));

test("a field that moves up into a note's row lines up with the rest", () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);
    // Leaving Project name takes its note away, and Contact email moves up
    // into the row the note had.
    await window.press(DOWN);
    await window.shows('❯   Contact email');

    const lines = window.frame().split('\n');
    const column = (label: string) =>
      lines.find((line) => line.includes(label))?.indexOf(label);

    expect(column('Contact email')).toBe(column('Project name'));
    expect(column('Replicas')).toBe(column('Project name'));
  }));

test('an invalid entry is refused in place, and Accept sends nothing', () =>
  withWindow(
    async (window) => {
      await send(window, 'form');
      await inputAsked(window);
      await window.type('ab');
      await window.press(TAB);
      await window.shows('At least 3 characters');
      await window.type('x1');
      await window.shows('Contact email  x1');
      // Letters never go into a number field.
      await window.press(TAB);
      await window.type('z');
      await window.shows('Replicas       2');
      await window.press(END);

      // On through the rest to Accept.
      for (let step = 0; step < 5; step++) {
        await window.press(TAB);
      }

      await window.press('\r');
      await window.shows('3 fields to fix');
      expect(window.frame()).toContain('Not an email address');
      expect(window.frame()).toContain('Required');
      expect(
        !window.frame().includes('Elicitation answer'),
        'a refused form was sent',
      ).toBeTruthy();
      await window.press(ESC);
      await window.shows('Elicitation answer: cancel');
    },
    { rows: 40, columns: 120 },
  ));

test('an accepted form reaches the agent, which echoes it', () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);
    await window.type('web-app');

    // To Region, its list open, Europe picked, then to Accept.
    for (let step = 0; step < 5; step++) {
      await window.press(DOWN);
    }

    await window.press(' ');
    await window.shows('1. Europe');
    await window.press('1');
    await window.shows('Region         Europe');
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('⎿  Answered · 4 fields');
    await window.shows('Elicitation answer: accept');
    await window.shows(
      '{"name":"web-app","replicas":2,"public":false,"region":"eu"}',
    );
    await window.press(CTRL_O);
    await window.shows('Region        Europe');
  }));

test('a declined form reaches the agent as declined', () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);

    for (let step = 0; step < 7; step++) {
      await window.press(TAB);
    }

    await window.press('\x1b[C');
    await window.shows('Enter to decline');
    await window.press('\r');
    await window.shows('⎿  Declined');
    await window.shows('Elicitation answer: decline');
  }));

test('ctrl+c stops the turn, and the form goes with it', () =>
  withWindow(async (window) => {
    await send(window, 'form');
    await inputAsked(window);
    await window.press(CTRL_C);
    await window.shows('⎿  Cancelled');
    await window.shows('Interrupted by user');
    expect(
      !window.frame().includes('asks for input'),
      'the form stayed',
    ).toBeTruthy();
  }));

test("a field's value keeps the agent's colours while the cursor is in it", async () => {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <ElicitationForm
        wait={{
          id: 'e',
          mode: 'form',
          message: 'Question',
          schema: {
            type: 'object',
            properties: {
              name: {
                type: 'string',
                title: 'Name',
                default: '\x1b[31mRED\x1b[0m',
              },
            },
          },
        }}
        agent='fake'
        windowRows={24}
        width={80}
        active={false}
        onAnswer={() => {}}
      />,
      { columns: 80, rows: 24 },
    );
    const shown = drawn.frame();

    await drawn.unmount();
    expect(shown).toContain('\x1b[31m');
    expect(stripAnsi(shown)).toContain('RED');
    expect(stripAnsi(shown)).not.toMatch(/\[\d*m/);
  } finally {
    chalk.level = level;
  }
});

describe('CHD-1 tester: generic form row lifecycle', () => {
  const labels = [
    'Project name',
    'Contact email',
    'Replicas',
    'Traffic share',
    'Public',
    'Region',
    'Tags',
  ];
  const aligned = (frame: string) => {
    const lines = frame.split('\n');
    const columns = labels.flatMap((label) => {
      const line = lines.find((line) => line.includes(label));

      return line === undefined ? [] : [line.indexOf(label)];
    });

    expect(columns.length).toBeGreaterThan(1);

    for (const column of columns) {
      expect(column).toBe(columns[0] ?? -1);
    }
  };

  for (const size of [
    { columns: 120, rows: 40 },
    { columns: 80, rows: 24 },
  ]) {
    test(`dropdowns, validation notes and overflow keep their columns at ${size.columns}x${size.rows}`, () =>
      withWindow(async (window) => {
        await send(window, 'form');
        await inputAsked(window);
        await window.type('ab');
        await window.press(DOWN);
        await window.shows('At least 3 characters');
        aligned(window.frame());

        for (let step = 0; step < 4; step++) {
          await window.press(DOWN);
        }

        for (let cycle = 0; cycle < 2; cycle++) {
          await window.press(' ');
          await window.shows('1. Europe');
          aligned(window.frame());
          await window.press('2');
          await window.shows('Region         United States');
          await window.press(DOWN);
          await window.press(' ');
          await window.shows('☐ worker');
          aligned(window.frame());
          await window.press(' ');
          await window.press(DOWN);
          await window.press(' ');
          await window.press('\r');
          await window.shows(
            cycle === 0 ? 'Tags           web, api' : 'Tags           ',
          );
          aligned(window.frame());
          await window.press(UP);
        }

        for (let step = 0; step < 5; step++) {
          await window.press(UP);
        }

        await window.shows('Project name   ab');
        await window.press('\x15');
        await window.type('web-app');
        await window.press(DOWN);
        await window.shows('Contact email');
        expect(window.frame()).not.toContain('At least 3 characters');
        aligned(window.frame());
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
      }, size));
  }

  test('two sessions keep separate form values and open lists when switched', () =>
    withChild(
      async (window) => {
        await openOther(window);
        await send(window, 'form');
        await inputAsked(window);
        await window.type('alpha');

        for (let step = 0; step < 5; step++) {
          await window.press(DOWN);
        }

        await window.press(' ');
        await window.shows('1. Europe');
        await pickAgent(window, 'other');
        await until('the second agent', () => window.pids.length === 2);
        await window.shows('asks for input · ctrl+x a');
        await send(window, 'form');
        await inputAsked(window, '│ other asks for input');
        await window.type('beta');
        await window.press(DOWN);
        await window.type('beta@example.com');
        await pickAgent(window, 'main');
        await inputAsked(window, '│ fake asks for input');
        await window.shows('1. Europe');
        aligned(window.frame());
        await window.press('2');
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
        await pickAgent(window, 'other');
        await inputAsked(window, '│ other asks for input');
        await window.shows('Project name   beta');
        await window.shows('Contact email  beta@example.com');
        aligned(window.frame());
        expect(window.frame()).not.toContain('alpha');
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
        await quitAll(window);
      },
      { columns: 80, rows: 24 },
    ));

  test('a child form cancels independently of a hung main turn', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withChild(
        async (window) => {
          await readyAgent(window);

          if (main === undefined) {
            throw new Error('main was not admitted');
          }

          await main.window.open(main.key, {
            agent: 'codex',
            name: 'other',
            prompt: 'form',
          });
          await until('the child is started', () => window.pids.length === 2);
          await send(window, 'never');
          await window.shows('Working…');
          await pickAgent(window, 'other');
          await inputAsked(window, 'other asks for input');
          await window.press(DOWN);
          aligned(window.frame());
          await window.press(CTRL_C);
          await window.shows('⎿  Cancelled');
          expect(window.frame()).not.toContain('fake asks for input');
          await pickAgent(window, 'main');
          await window.shows('Working…');
          await quitAll(window);
        },
        {
          server,
          columns: 80,
          rows: 24,
          agentCommand: fakeAgentCommand(undefined, '--hang', 'turn'),
          startupOf: (agent) => ({
            agentCommand:
              agent === 'fake'
                ? fakeAgentCommand(undefined, '--hang', 'turn')
                : fakeAgentCommand(),
          }),
        },
      );
    } finally {
      await server.close();
    }
  });

  test('an agent exiting with a dropdown open withdraws the form', () =>
    withWindow(
      async (window) => {
        await send(window, 'form');
        await inputAsked(window);

        for (let step = 0; step < 5; step++) {
          await window.press(DOWN);
        }

        await window.press(' ');
        await window.shows('1. Europe');

        const pid = window.pids[0];

        expect(pid).toBeDefined();
        process.kill(pid!, 'SIGKILL');
        await until(
          'the exited agent to withdraw its form',
          () => !window.frame().includes('fake asks for input'),
        );
        await window.shows('⎿  Cancelled');
      },
      { columns: 80, rows: 24 },
    ));

  test('a late reply before a new form leaves its rows and cancel key intact', () =>
    withWindow(
      async (window) => {
        await send(window, 'late');
        await window.shows('Late, after the answer.');
        await send(window, 'form');
        await inputAsked(window);
        await window.press(DOWN);
        aligned(window.frame());
        await window.press(ESC);
        await window.shows('Elicitation answer: cancel');
      },
      { columns: 80, rows: 24 },
    ));
});

describe('CHD-1 tester: Droid multi-select schema', () => {
  test('repeated checkbox toggles send each selected option only once', async () => {
    let answer: ElicitationReply | undefined;
    const form = await draw(
      <ElicitationForm
        wait={{
          id: 'droid',
          mode: 'form',
          message: DROID_QUESTIONS.message,
          schema: DROID_QUESTIONS.requestedSchema,
        }}
        agent='fake'
        windowRows={40}
        width={120}
        active
        onAnswer={(response) => {
          answer = response;
        }}
      />,
      { columns: 120, rows: 40 },
    );

    try {
      await form.write(' ');
      await form.write('1');
      await form.write(DOWN);
      await form.write(DOWN);
      await form.write(' ');

      // Pick, unpick and pick PNG again, then add JPEG.
      for (let toggle = 0; toggle < 3; toggle++) {
        await form.write(' ');
      }

      await form.write(DOWN);
      await form.write(' ');
      await form.write('\r');
      await form.write(DOWN);
      await form.write(DOWN);
      await form.write('uploads');
      await form.write(DOWN);
      await form.write('\r');
      expect(answer?.action).toBe('accept');

      const values =
        answer?.action === 'accept' ? answer.content?.question_1 : undefined;

      expect(values).toStrictEqual(['option_0', 'option_1']);

      if (!Array.isArray(values)) {
        throw new Error('Droid multi-select did not send an array');
      }

      // SDK parsing strips droid's uniqueItems; checkbox toggles keep its picks unique.
      expect(new Set(values).size).toBe(values.length);
    } finally {
      await form.unmount();
    }
  });
});

describe("a form left open at its turn's end (CHD-158 C5, the owner's Q53)", () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`stays answerable between turns, the queue behind it, at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          // Its turn ends once the test says so, so the form is seen in it
          // however slow the test is (CHD-399).
          await send(window, 'leftformgated');
          // In its turn it has the keys.
          await inputAsked(window);
          await window.shows('❯ * Project name');
          await mkdir(join(window.dir, GATE), { recursive: true });
          await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
          // Its turn over, it waits between turns, without the keys; at 80
          // by 24 the form hides the turn's last words.
          await window.shows('main asks for input · between turns');
          await window.shows('ctrl+x a to answer');
          // It still waits on the person, and the line says so.
          await window.shows('Waiting for your input…');
          expect(window.frame()).not.toContain('❯ * Project name');
          expect(window.frame()).toContain('Set up the deploy target');
          expect(window.frame()).not.toContain('Elicitation answer');

          await window.type('text');
          await window.press('\r');
          await window.shows('› after your answer: text');

          const lines = window.frame().split('\n');

          // Everything below the box is whole, the box folding to make room
          // at 80 by 24 and drawn whole at 120 by 40 (CHD-158 §8).
          expect(lines).toHaveLength(rows);
          expect(lines.at(-1)).toContain('ctrl+x a to answer');
          expect(window.frame()).toContain('Waiting for your input…');

          if (columns === 80) {
            expect(window.frame()).toMatch(/… \d+ more lines/);
            expect(window.frame()).not.toContain('Accept   Decline');
          } else {
            expect(window.frame()).not.toContain('more lines');
          }

          expect(window.frame()).toContain('between turns');

          await leader(window, 'a');
          await window.shows('❯ * Project name');
          await window.shows('› after your answer: text');
          await window.press(ESC);
          await window.shows('Elicitation answer: cancel');
          await window.shows('Hello, world.');
          expect(window.frame()).not.toContain('between turns');
        },
        { columns, rows },
      ));
  }
});

describe('CHD-462 B1 tester: hidden form contents', () => {
  for (const columns of [80, 120]) {
    test(`typed contents survive the frame at ${columns} columns`, async () => {
      const control: { set?: (hidden: boolean) => void } = {};

      function Hidden() {
        const [hidden, setHidden] = useState(false);

        control.set = setHidden;

        return (
          <ElicitationForm
            wait={{
              id: 'kept-form',
              mode: 'form',
              message: 'Kept deploy values',
              schema: FORM_SCHEMA,
            }}
            agent='fake'
            width={columns}
            windowRows={24}
            active={!hidden}
            hidden={hidden}
            onAnswer={() => {}}
          />
        );
      }

      const drawn = await draw(<Hidden />, { columns, rows: 24 });

      try {
        await drawn.write('web-app');
        await until('typed value', () => drawn.frame().includes('web-app'));
        control.set?.(true);
        await until(
          'form hidden',
          () => !drawn.frame().includes('Kept deploy values'),
        );
        control.set?.(false);
        await until('typed value restored', () =>
          drawn.frame().includes('web-app'),
        );
        await drawn.write('-v2');
        await until('field continues editing', () =>
          drawn.frame().includes('web-app-v2'),
        );
      } finally {
        await drawn.unmount();
      }
    });
  }
});
