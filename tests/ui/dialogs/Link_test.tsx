import { expect, test } from 'bun:test';
import { ESC, inputAsked, send, withWindow } from '../app/render.tsx';

test('a link opens only on its key, and its record keeps it whole', async () => {
  const opened: string[] = [];

  await withWindow(
    async (window) => {
      await send(window, 'link');
      await inputAsked(window, 'fake asks you to open a link');
      expect(window.frame()).toContain('Opens example.com');
      expect(window.frame()).toContain('❯ 1. Open in the browser');
      expect(opened).toStrictEqual([]);
      await window.press('1');
      await window.shows(
        'Opened https://example.com/oauth/authorize?client=abc&state=9f2c',
      );
      await window.shows('Elicitation answer: accept');
      expect(opened).toStrictEqual([
        'https://example.com/oauth/authorize?client=abc&state=9f2c',
      ]);
    },
    {
      openUrl: (url) => {
        opened.push(url);

        return Promise.resolve(undefined);
      },
    },
  );
});

test('Esc on a link answers cancel and opens nothing', async () => {
  const opened: string[] = [];

  await withWindow(
    async (window) => {
      await send(window, 'link');
      await inputAsked(window, 'fake asks you to open a link');
      await window.press(ESC);
      await window.shows('Elicitation answer: cancel');
      expect(opened).toStrictEqual([]);
    },
    {
      openUrl: (url) => {
        opened.push(url);

        return Promise.resolve(undefined);
      },
    },
  );
});
