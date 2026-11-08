import { expect, test } from 'bun:test';
import { OUTPUT, socialPage } from '../../../scripts/dev/social.ts';
import { TAGLINE } from '../../../src/ui/app/start_layout.ts';

test('the card carries the tagline, the logo and the team window it is given', () => {
  const page = socialPage('data:logo', 'data:team');

  expect(page).toContain(`<h1>${TAGLINE}</h1>`);
  expect(page).toContain('<img src="data:logo">');
  expect(page).toContain('url(data:team)');
  expect(page).toContain('npm i -g @chorded/chord');
  // The window cut out of the 2348×1778 pane, at half size.
  expect(page).toContain('width:1031px;height:738.5px;border-radius:42px');
  expect(page).toContain('-71.5px -63.5px/1174px 889px');
});

test('the card is written to dist/, which git ignores', () => {
  expect(OUTPUT.endsWith('/dist/social-preview.png')).toBe(true);
});
