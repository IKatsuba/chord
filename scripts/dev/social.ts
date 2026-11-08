/**
 * Lay out the repository's social preview, the card GitHub shows for a link
 * to it.
 *
 *   bun dev social   write dist/social-preview.png
 *
 * The card is built from what `bun dev screenshots` leaves in docs/images:
 * the dark logo, and the window of the `team` shot, cut out of its pane and
 * set on the right, half off the edge. So it follows the logo's colours and
 * chord's screen without a picture of its own; retake the shots first for a
 * new version. GitHub takes the card only through the repository's settings
 * page, so it is written to dist/ for the owner to upload.
 */
import { mkdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import puppeteer from 'puppeteer-core';
import { TAGLINE } from '../../src/ui/app/start_layout.ts';
import { CHROME, IMAGES, ROOT } from './screenshots.ts';

/** The card's size in CSS pixels; GitHub's recommended 1280×640, taken at 2x. */
const WIDTH = 1280;
const HEIGHT = 640;

/** The pane's size around each screenshot in docs/images, in pixels. */
const SHOT = { width: 2348, height: 1778 };

/** The window inside a shot's pane: its left, top, width, height and corner. */
const WINDOW = { x: 143, y: 127, width: 2062, height: 1477, radius: 84 };

/** The scale the window is drawn at on the card. */
const SCALE = 0.5;

/** Where the card is written. */
export const OUTPUT = join(ROOT, 'dist', 'social-preview.png');

/** A PNG as a data URL, so the page needs no files of its own. */
function dataUrl(png: Uint8Array): string {
  return `data:image/png;base64,${Buffer.from(png).toString('base64')}`;
}

/** The card's page, with the logo and the team shot as data URLs. */
export function socialPage(logo: string, team: string): string {
  const s = SCALE;

  return `<!doctype html><style>
html,body{margin:0}
.page{position:relative;width:${String(WIDTH)}px;height:${String(HEIGHT)}px;overflow:hidden;
  background:linear-gradient(135deg,#2b3a8c 0%,#6a4bc4 38%,#c46aa8 70%,#f2a17a 100%);
  font-family:-apple-system,'SF Pro Display','Helvetica Neue',sans-serif;color:#fff}
.left{position:absolute;left:72px;top:0;bottom:0;width:470px;display:flex;flex-direction:column;justify-content:center;gap:28px}
.left img{width:420px}
h1{margin:0;font-size:40px;line-height:1.15;font-weight:700;letter-spacing:-0.5px}
p{margin:0;font-size:21px;line-height:1.4;color:rgba(255,255,255,.85)}
code{font:18px 'JetBrains Mono',Menlo,monospace;background:rgba(14,15,18,.55);padding:10px 16px;border-radius:10px;align-self:flex-start;color:#47e7a5}
.win{position:absolute;left:590px;top:110px;width:${String(WINDOW.width * s)}px;height:${String(WINDOW.height * s)}px;border-radius:${String(WINDOW.radius * s)}px;
  background:url(${team}) ${String(-WINDOW.x * s)}px ${String(-WINDOW.y * s)}px/${String(SHOT.width * s)}px ${String(SHOT.height * s)}px no-repeat;
  box-shadow:0 30px 80px rgba(20,10,60,.55)}
</style><div class="page">
<div class="left"><img src="${logo}">
<h1>${TAGLINE}</h1>
<p>Claude Code, Codex, Gemini CLI and 33 more, side by side, working as a team.</p>
<code>npm i -g @chorded/chord</code></div>
<div class="win"></div></div>`;
}

/** Writes the card to `OUTPUT` from docs/images. */
export async function social(): Promise<void> {
  const [logo, team] = await Promise.all(
    ['logo-dark.png', 'team.png'].map(async (name) =>
      dataUrl(await readFile(join(IMAGES, name))),
    ),
  );
  const browser = await puppeteer.launch({ executablePath: CHROME });

  try {
    const tab = await browser.newPage();

    await tab.setViewport({
      width: WIDTH,
      height: HEIGHT,
      deviceScaleFactor: 2,
    });
    await tab.setContent(socialPage(logo ?? '', team ?? ''), {
      waitUntil: 'load',
    });
    await tab.evaluate(() => document.fonts.ready);

    const element = await tab.$('.page');

    if (element === null) {
      throw new Error('The social preview drew no card.');
    }

    await mkdir(join(ROOT, 'dist'), { recursive: true });
    await element.screenshot({ path: OUTPUT });
    console.log(OUTPUT);
  } finally {
    await browser.close();
  }
}
