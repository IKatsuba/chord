/**
 * Every key the plan box, dimcode's notice and the prompt answer is in the
 * shortcuts panel.
 */
import { expect, test } from 'bun:test';
import * as harness from '../harness.tsx';
import { PlanBox } from '../../../src/ui/dialogs/PlanBox.tsx';
import { NoticeBox } from '../../../src/ui/pickers/Pickers.tsx';
import { PromptInput } from '../../../src/ui/prompt/Prompt.tsx';
import { SHORTCUTS } from '../../../src/ui/shortcuts/keys.ts';
import { type Cursor } from '../../../src/ui/prompt/prompt.ts';
import {
  RAW_PRESSES,
  listKeys,
  FORM_PRESSES,
  PLAN_STATES,
} from './keys_presses.tsx';

/**
 * Presses every key on the plan box, on each kind of row afresh, and checks
 * that each one it answers is in the panel: its keys are the permission
 * prompt's and the question box's, nothing new. Typing on the Note row is
 * not listed.
 */
test('every key the plan box answers is in the panel', async () => {
  const escaped = () => new Promise((resolve) => setTimeout(resolve, 40));

  for (const [agent, state, prelude, typing] of PLAN_STATES) {
    const answers: unknown[] = [];
    const draw = async () => {
      const app = await harness.draw(
        <PlanBox
          wait={{ id: 'p1', agent, toolCallId: 'c1', plan: '# Plan' }}
          agent={agent}
          width={120}
          active
          onAnswer={(answer) => answers.push(answer)}
        />,
      );

      for (const press of prelude) {
        await app.write(press);
      }

      answers.length = 0;

      return app;
    };

    let app = await draw();

    try {
      for (const { name, sequence } of FORM_PRESSES) {
        const before = app.frame();

        await app.write(sequence);

        if (sequence === '\x1b') {
          await escaped();
        }

        if (app.frame() === before && answers.length === 0) {
          continue;
        }

        await app.unmount();

        app = await draw();

        if (
          typing &&
          (name.length === 1 ||
            name.startsWith('ctrl + ') ||
            name === 'backspace')
        ) {
          continue;
        }

        expect(
          SHORTCUTS.some(
            (shortcut) =>
              shortcut.questions?.includes(name) ||
              shortcut.choices?.includes(name),
          ),
          `${name} on ${agent}'s plan box's ${state} is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }
});

test("every key dimcode's notice answers is in the panel (CHD-434)", () =>
  listKeys(
    'notice',
    (onPick) => (
      <NoticeBox
        columns={80}
        active
        onAnswer={(dismissed) => onPick(dismissed ? 'dismiss' : 'later')}
      />
    ),
    2,
    // Opened on 1, and on 2.
    ['', '\x1b[B'],
  ));

/** The prompt box with a draft, counting what each press did to it. */
async function promptBox(walking: boolean) {
  const did = { sends: 0, newlines: 0, walks: 0 };
  const app = await harness.draw(
    <PromptInput
      // A draft, so that a send has something to send.
      value='draft'
      cursor={[0, 5]}
      rows={5}
      walking={walking}
      focus
      onChange={(value) => value.includes('\n') && did.newlines++}
      onCursorChange={() => {}}
      onSubmit={() => did.sends++}
      onOlder={() => did.walks++}
      onNewer={() => did.walks++}
    />,
  );

  return { app, did };
}

/**
 * option and cmd with ← and →, in the forms terminals send them, which the
 * prompt's textarea moves its cursor on (CHD-386). ← and → alone, ctrl+a and
 * ctrl+e move it too, and the panel leaves them out, as Claude Code does.
 */
const MOVES: { name: string; sequence: string }[] = [
  { name: 'alt + ←', sequence: '\x1b[1;3D' },
  { name: 'alt + →', sequence: '\x1b[1;3C' },
  { name: 'alt + b', sequence: '\x1bb' },
  { name: 'alt + f', sequence: '\x1bf' },
  { name: 'cmd + ←', sequence: '\x1b[1;9D' },
  { name: 'cmd + →', sequence: '\x1b[1;9C' },
];

test('every key the prompt sends, breaks, walks or moves by word or line on is in the panel', async () => {
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));
  const answered = new Set<string>();

  for (const walking of [false, true]) {
    // The box's value and cursor are held, so no press changes what the next
    // one does.
    const { app, did } = await promptBox(walking);

    try {
      await settle();

      for (const { name, sequence } of RAW_PRESSES) {
        const before = JSON.stringify(did);

        await app.write(sequence);
        await settle();

        if (JSON.stringify(did) === before) {
          continue;
        }

        answered.add(name);
        expect(
          SHORTCUTS.some((shortcut) => shortcut.prompt?.includes(name)),
          `${name} in the prompt is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }

  // Each from the middle of a draft of words, in a box of its own, so that
  // every move has somewhere to go.
  for (const { name, sequence } of MOVES) {
    const moves: Cursor[] = [];
    const app = await harness.draw(
      <PromptInput
        value='one two three'
        cursor={[0, 5]}
        rows={5}
        walking={false}
        focus
        onChange={() => {}}
        onCursorChange={(cursor) => moves.push(cursor)}
        onSubmit={() => {}}
        onOlder={() => {}}
        onNewer={() => {}}
      />,
    );

    try {
      await settle();

      moves.length = 0;

      await app.write(sequence);
      await settle();

      if (moves.every(([, column]) => column === 5)) {
        continue;
      }

      answered.add(name);
      expect(
        SHORTCUTS.some((shortcut) => shortcut.prompt?.includes(name)),
        `${name} in the prompt is not listed`,
      ).toBeTruthy();
    } finally {
      await app.unmount();
    }
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.prompt ?? []) {
      expect(
        answered.has(name),
        `${name} does nothing in the prompt`,
      ).toBeTruthy();
    }
  }
});
