import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import { ElicitationForm } from '../../../src/ui/dialogs/Form.tsx';
import {
  CTRL_C,
  CTRL_O,
  DOWN,
  END,
  ESC,
  inputAsked,
  send,
  TAB,
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
