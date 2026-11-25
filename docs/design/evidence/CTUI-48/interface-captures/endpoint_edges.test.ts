import { test } from 'bun:test';

const original = process.env.CHORD_SOURCE;
if (!original) throw new Error('CHORD_SOURCE must name the read-only original');
const { withWindow, send, left } = await import(`${original}/tests/ui/app/render.tsx`);
const { cellsOf, REPLY } = await import(`${original}/tests/ui/app/selecting.ts`);

test('records motion/release and blank-code endpoint edges with clipboard disabled', async () => {
  for (const [columns, rows] of [[120, 40], [80, 24]]) {
    await withWindow(async (window: any) => {
      await send(window, 'text');
      await window.shows(REPLY);
      const at = cellsOf(window, REPLY);
      for (const name of ['no-motion', 'same-cell-motion', 'return-anchor', 'release-elsewhere-no-motion', 'motion-then-release-elsewhere']) {
        await window.press('\x1b');
        await window.press(left(at.x, at.y, 'down'));
        if (name === 'same-cell-motion') await window.press(left(at.x, at.y, 'drag'));
        if (name === 'return-anchor') {
          await window.press(left(at.x + 3, at.y, 'drag'));
          await window.press(left(at.x, at.y, 'drag'));
        }
        if (name === 'motion-then-release-elsewhere') await window.press(left(at.x + 1, at.y, 'drag'));
        const before = window.selected();
        const end = name.includes('elsewhere') ? at.x + 3 : at.x;
        await window.press(left(end, at.y, 'up'));
        console.log(JSON.stringify({columns,rows,name,beforeRelease:before,selected:window.selected()}));
      }
      await window.press('\x1b');
      await send(window, 'markdowncode');
      await window.shows('echo done');
      const echo = cellsOf(window, 'echo done');
      const blankY = echo.y - 1;
      for (const [name, ax, ay, bx, by, motion] of [
        ['blank-click', echo.x, blankY, echo.x, blankY, false],
        ['blank-same-cell-motion', echo.x, blankY, echo.x, blankY, true],
        ['blank-row-across', echo.x, blankY, echo.x+3, blankY, true],
        ['blank-to-code', echo.x, blankY, echo.end, echo.y, true],
        ['code-to-blank', echo.end, echo.y, echo.x, blankY, true],
        ['first-code-glyph-to-blank', echo.x, echo.y, echo.x, blankY, true],
      ]) {
        await window.press('\x1b');
        await window.press(left(ax, ay, 'down'));
        if (motion) await window.press(left(bx, by, 'drag'));
        const before = window.selected();
        await window.press(left(bx, by, 'up'));
        console.log(JSON.stringify({columns,rows,name,beforeRelease:before,selected:window.selected()}));
      }
    }, {columns,rows,copyOnSelect:false,copy:async()=>{throw new Error('copy must not be called');}});
  }
}, 30000);
