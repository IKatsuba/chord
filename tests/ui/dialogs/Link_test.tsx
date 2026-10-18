import { describe, expect, test } from 'bun:test';
import {
  ESC,
  inputAsked,
  promptRow,
  send,
  withWindow,
} from '../app/render.tsx';

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

describe('CHD-158 tester: a held link', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`the rebound attention key activates a link and keeps typed digits at ${columns} columns`, async () => {
      const opened: string[] = [];

      await withWindow(
        async (window) => {
          const session = window.session()!;
          const answer = session.elicitations.handler(
            {
              sessionId: session.id,
              mode: 'url',
              message: 'Approve this deployment',
              url: 'https://example.com/approve',
              elicitationId: 'held-link',
            },
            new AbortController().signal,
          );

          await window.shows('main asks you to open a link · between turns');
          await window.shows('ctrl+y to answer');
          expect(window.frame()).not.toContain('❯ 1. Open in the browser');
          await window.type('1');
          expect(promptRow(window)).toContain('› 1');
          expect(opened).toStrictEqual([]);
          await window.press('\x19');
          await window.shows('❯ 1. Open in the browser');
          await window.press('1');
          expect(await answer).toStrictEqual({ action: 'accept' });
          await window.shows('Opened https://example.com/approve');
          expect(opened).toStrictEqual(['https://example.com/approve']);
          expect(promptRow(window)).toContain('› 1');
        },
        {
          columns,
          rows,
          openUrl: (url) => {
            opened.push(url);

            return Promise.resolve(undefined);
          },
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'Global',
                bindings: {
                  'ctrl+x a': null,
                  'ctrl+y': 'session:attention',
                },
              },
            ],
          }),
        },
      );
    });
  }
});
