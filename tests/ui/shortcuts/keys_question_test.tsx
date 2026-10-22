/**
 * Every key the question box and the model picker answer is in the
 * shortcuts panel.
 */
import { expect, test } from 'bun:test';
import * as harness from '../harness.tsx';
import { QuestionBox } from '../../../src/ui/dialogs/Questions.tsx';
import { ModelPicker } from '../../../src/ui/pickers/Pickers.tsx';
import { SHORTCUTS } from '../../../src/ui/shortcuts/keys.ts';
import {
  NINE,
  listKeys,
  FORM_PRESSES,
  ASKED,
  QUESTION_STATES,
} from './keys_presses.tsx';

/**
 * Presses every key on the question box, on each kind of row afresh, and
 * checks that each one it answers is in the panel, and that each the panel
 * promises for it does something. Typing and editing a text row are not
 * listed.
 */
test('every key the question box answers is in the panel', async () => {
  // A lone ESC waits 20 ms for the rest of a sequence that never comes; the
  // harness's own wait is for what a key draws, so this one is the ESC's.
  const escaped = () => new Promise((resolve) => setTimeout(resolve, 40));
  const answered = new Set<string>();

  for (const [state, prelude, typing] of QUESTION_STATES) {
    const answers: unknown[] = [];
    const draw = async () => {
      const app = await harness.draw(
        <QuestionBox
          wait={{
            id: 'e1',
            mode: 'form',
            message: 'Go?',
            schema: { type: 'object', properties: {} },
          }}
          questions={ASKED}
          agent='fake'
          windowRows={40}
          width={120}
          active
          onAnswer={(response) => answers.push(response)}
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

        answered.add(name);
        expect(
          SHORTCUTS.some(
            (shortcut) =>
              shortcut.questions?.includes(name) ||
              shortcut.choices?.includes(name),
          ),
          `${name} on the question box's ${state} is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.questions ?? []) {
      expect(
        answered.has(name),
        `${name} does nothing on the question box`,
      ).toBeTruthy();
    }
  }
});

// The session picker's list is the model picker's, so this covers both.
test('every key the model picker answers is in the panel', () =>
  listKeys('model picker', (onPick) => (
    <ModelPicker
      models={{
        available: NINE.map((digit) => ({
          id: digit,
          name: `Model ${digit}`,
        })),
        // In the middle, so that its highlight can move either way: it stops
        // at the ends.
        current: '5',
      }}
      rows={9}
      agent='fake'
      active
      onPick={onPick}
    />
  )));
