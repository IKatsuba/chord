/**
 * Code coloured by its language: emphasize's highlight.js grammars, in
 * sheets made from a theme's tokens: one set for the terminal's own
 * background, one for a diff's tinted rows (theme.ts).
 */
import { extname } from 'node:path';
import process from 'node:process';
import chalk, { Chalk, type ChalkInstance } from 'chalk';
import { common, createEmphasize, type Sheet } from 'emphasize';
import type { Tones } from '../theme/theme.ts';

const emphasize = createEmphasize(common);

/**
 * A hex through chalk, at whatever level the terminal takes, or one of the
 * terminal's 16 by name; a class with no colour stays as it is.
 */
export function brush(
  paint: ChalkInstance,
  colour: string | undefined,
): (text: string) => string {
  if (colour === undefined) {
    return (text) => text;
  }

  return colour.startsWith('#')
    ? paint.hex(colour)
    : (paint[colour as 'red'] ?? ((text) => text));
}

function sheet(paint: ChalkInstance, tones: Tones): Sheet {
  const keyword = brush(paint, tones.keyword);
  const string = brush(paint, tones.string);
  const number = brush(paint, tones.number);
  const comment = brush(paint, tones.comment);
  const title = brush(paint, tones.title);
  const type = brush(paint, tones.type);
  const name = brush(paint, tones.name);
  const meta = brush(paint, tones.meta);

  return {
    keyword,
    'selector-tag': keyword,
    'meta keyword': keyword,
    string,
    regexp: string,
    'meta meta-string': string,
    char: string,
    number,
    literal: number,
    comment,
    quote: comment,
    doctag: comment,
    title,
    section: title,
    'selector-id': title,
    'selector-class': title,
    type,
    built_in: type,
    'class title': type,
    name,
    attr: name,
    attribute: name,
    variable: name,
    'template-variable': name,
    property: name,
    meta,
    symbol: meta,
    bullet: meta,
    link: meta,
    'selector-attr': meta,
    'selector-pseudo': meta,
    emphasis: paint.italic,
    strong: paint.bold,
  };
}

/**
 * The colour level the terminal takes, as chalk detects it; at
 * least 16 colours when the caller has decided on colour.
 */
const PAINT = new Chalk({ level: Math.max(chalk.level, 1) as 1 });

/** Each set of tones' sheet, made the first time it is asked for. */
const sheets = new WeakMap<Tones, { sheet: Sheet; id: number }>();
let made = 0;

function sheetOf(tones: Tones): { sheet: Sheet; id: number } {
  const known = sheets.get(tones);

  if (known !== undefined) {
    return known;
  }

  const fresh = { sheet: sheet(PAINT, tones), id: made++ };

  sheets.set(tones, fresh);

  return fresh;
}

/**
 * Whether code is coloured on this terminal: chalk takes no notice of
 * NO_COLOR, so it is read here, and nothing is added under it.
 */
export function highlighting(): boolean {
  return process.stdout.isTTY === true && !process.env['NO_COLOR'];
}

/**
 * The grammar a fence's label names, by its first word; none when the label
 * is missing or names no language highlight.js knows.
 */
export function fenceLanguage(label: string | undefined): string | undefined {
  const name = label?.trim().split(/\s+/)[0]?.toLowerCase() ?? '';

  return name !== '' && emphasize.registered(name) ? name : undefined;
}

/**
 * The grammar a file's extension names, or its whole name for one like
 * `Makefile`; none when highlight.js knows neither.
 */
export function pathLanguage(path: string): string | undefined {
  const extension = extname(path).slice(1).toLowerCase();
  const base = path.split(/[\\/]/).at(-1)?.toLowerCase() ?? '';

  return [extension, base].find(
    (name) => name !== '' && emphasize.registered(name),
  );
}

/**
 * The texts highlighted last. A transcript draws again on every tick of the
 * working line, and an edit's diff colours both whole files each time, so
 * the same file is not highlighted twice while it stays in view.
 */
const highlighted = new Map<string, readonly string[]>();

/** Enough for every edit on a screen, few enough that memory stays small. */
const REMEMBERED = 64;

/**
 * `code`'s lines coloured as `language` in `tones`, or as they are without a
 * language or tones. The
 * whole text is highlighted at once, so a comment or a string that runs over
 * several lines is coloured on each; chalk closes and opens its styles again
 * at every line break, so each line stands alone.
 */
export function highlightLines(
  code: string,
  language: string | undefined,
  tones: Tones | undefined,
): readonly string[] {
  if (language === undefined || tones === undefined) {
    return code.split('\n');
  }

  const { sheet, id } = sheetOf(tones);
  const key = `${id}\0${language}\0${code}`;
  const known = highlighted.get(key);

  if (known !== undefined) {
    return known;
  }

  const lines = emphasize.highlight(language, code, sheet).value.split('\n');

  if (highlighted.size >= REMEMBERED) {
    highlighted.delete(highlighted.keys().next().value!);
  }

  highlighted.set(key, lines);

  return lines;
}
