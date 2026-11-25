import { test } from 'bun:test';

const original = process.env.CHORD_SOURCE;
if (!original) throw new Error('CHORD_SOURCE must name the read-only original');
const { withWindow, send, left } = await import(`${original}/tests/ui/app/render.tsx`);
const { cellsOf, REPLY } = await import(`${original}/tests/ui/app/selecting.ts`);
const { default: stripAnsi } = await import(`${original}/node_modules/strip-ansi/index.js`);

test('records original selection endpoints with auto-copy off and copy stub', async () => {
  for (const [columns, rows] of [[120, 40], [80, 24]]) {
    await withWindow(async (window: any) => {
      await send(window, 'text');
      await window.shows(REPLY);
      const at = cellsOf(window, REPLY);
      const screen = stripAnsi(window.frame()).split('\n');
      const py = screen.findIndex((row: string) => /(?:^|\s)text\s*$/.test(row));
      if (py < 0) throw new Error('transcript prompt not found');
      const prompt = { x: screen[py].lastIndexOf('text'), y: py };
      const cases = [
        ['click', at.x, at.y, at.x, at.y],
        ['forward', at.x, at.y, at.x + 3, at.y],
        ['reverse', at.x + 3, at.y, at.x, at.y],
        ['past-right', at.x, at.y, columns - 1, at.y],
        ['past-left', at.x + 3, at.y, 0, at.y],
        ['past-below', at.x + 3, at.y, columns - 1, at.y + 2],
        ['past-above', at.x + 3, at.y, 0, at.y - 1],
        ['cross-entry-direct', prompt.x, prompt.y, at.end, at.y],
        ['cross-entry-stepped', prompt.x, prompt.y, at.end, at.y],
        ['cross-entry-reverse-stepped', at.end, at.y, prompt.x, prompt.y],
      ];
      for (const [name, ax, ay, bx, by] of cases) {
        await window.press('\x1b');
        await window.press(left(ax, ay, 'down'));
        if (String(name).includes('stepped')) {
          const step = by >= ay ? 1 : -1;
          for (let y = ay; y !== by; y += step) await window.press(left(bx, y, 'drag'));
          for (let repeat = 0; repeat < 5; repeat++) await window.press(left(bx, by, 'drag'));
        } else if (name !== 'click') await window.press(left(bx, by, 'drag'));
        await window.press(left(bx, by, 'up'));
        console.log(JSON.stringify({columns,rows,name,selected:window.selected()}));
      }
    }, { columns, rows, copyOnSelect: false, copy: async () => { throw new Error('copy must not be called'); } });
  }
}, 30000);
