import { expect, test } from 'bun:test';
import { emptyWatch } from '../../../src/notify.ts';
import { idle } from '../../../src/session/tabs.ts';
import { GLYPHS, glyphsOf, waitGlyphs } from '../../../src/ui/agents/glyphs.ts';

test('an agent shows its state, none while idle, then what of it is not yet seen (CHD-471)', () => {
  const asking = {
    on: { kind: 'permission', title: 'Write notes.txt' },
    since: 1,
  } as const;

  expect(waitGlyphs(idle)).toStrictEqual({});
  expect(waitGlyphs({ watch: emptyWatch, working: 1 })).toStrictEqual({
    state: 'working',
  });
  // Working with a reply not yet seen: both.
  expect(
    waitGlyphs({
      watch: emptyWatch,
      working: 1,
      unseen: { kind: 'replied', since: 2 },
    }),
  ).toStrictEqual({ state: 'working', mark: 'replied' });
  // A failed turn is a mark, the agent idle; an exit is its state.
  expect(
    waitGlyphs({ watch: emptyWatch, unseen: { kind: 'failed', since: 2 } }),
  ).toStrictEqual({ mark: 'failed' });
  expect(
    waitGlyphs({
      watch: emptyWatch,
      exited: true,
      unseen: { kind: 'failed', since: 2, failure: 'exited' },
    }),
  ).toStrictEqual({ state: 'failed' });
  expect(
    waitGlyphs({
      watch: emptyWatch,
      unseen: { kind: 'message', from: '@main', since: 2 },
    }),
  ).toStrictEqual({ mark: 'message' });
  expect(
    waitGlyphs({
      watch: emptyWatch,
      asking,
      unseen: { kind: 'failed', since: 2 },
    }),
  ).toStrictEqual({ state: 'asking', mark: 'failed' });

  // Drawn state first: `✻✓`.
  expect(
    glyphsOf({ state: 'working', mark: 'replied' })
      .map((glyph) => GLYPHS[glyph])
      .join(''),
  ).toStrictEqual('✻✓');
  expect(glyphsOf(undefined)).toStrictEqual([]);
});
