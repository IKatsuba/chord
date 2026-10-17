/**
 * Vim mode for the prompt box: insert is the textarea as it always is, and
 * normal mode's keys go to the vim engine of @replit/codemirror-vim, which is
 * written against a CodeMirror 5 editor and is given here a string with a
 * cursor that does what it asks. Each key is played on a fresh one from the
 * draft, the keys of a command still being typed played again first, so what
 * a key does is a function of the draft, the cursor and this module's state.
 * `u` is chord's: the engine leaves undo to its editor.
 */
import {
  type CM5EditorInterface,
  type CodeMirrorConstructor,
  initVim,
  type MotionFn,
  type OperatorFn,
  type Pos,
} from '@replit/codemirror-vim-core';
import type { Cursor } from './prompt.ts';

export type VimMode = 'insert' | 'normal';

/** The draft as it stood, for `u` to go back to. */
export interface Snapshot {
  readonly text: string;
  readonly cursor: Cursor;
}

/** What `p` puts back: the last text deleted or yanked, and whether whole lines. */
export interface Register {
  readonly text: string;
  readonly linewise: boolean;
}

/** Vim mode's state while it is on. */
export interface Vim {
  readonly mode: VimMode;
  /** The keys of a command still being typed, such as `2` and `d`. */
  readonly pending: readonly string[];
  readonly register?: Register | undefined;
  /** What `u` goes back to, the latest last. */
  readonly undo: readonly Snapshot[];
  /** The draft as insert mode found it; leaving changed, it is one undo. */
  readonly entered?: Snapshot | undefined;
  /**
   * Where `j` and `k` aim, which the engine keeps between keys: the column
   * a line too short for it does not take away, and the last motion, which
   * says whether to aim for it. The engine's own, never read here.
   */
  readonly goal?: Goal | undefined;
}

/** The engine's record of the column `j` and `k` aim for. */
export interface Goal {
  readonly motion: unknown;
  readonly column: number;
  readonly left: number;
}

/** Vim mode as `/vim` turns it on, and as each sent prompt leaves it. */
export const startingVim: Vim = {
  mode: 'insert',
  pending: [],
  undo: [],
  entered: { text: '', cursor: [0, 0] },
};

/** How far back `u` goes. */
const UNDO_LIMIT = 100;

/**
 * Widens a deletion that cut into a placeholder to take the whole of it, as
 * `cutPlaceholder` does; undefined when nothing needs widening.
 */
export type Atoms = (
  before: string,
  after: string,
) => { readonly text: string; readonly cursor: Cursor } | undefined;

/** What a key in normal mode did. */
export type VimStep =
  | { readonly vim: Vim; readonly text: string; readonly cursor: Cursor }
  /** `k` on the first line and `j` on the last walk history, as ↑ and ↓ do. */
  | { readonly vim: Vim; readonly history: 'older' | 'newer' };

/**
 * The characters normal mode takes. Others are dropped rather than given to
 * the engine, which would open a visual selection, a search or an ex line
 * that the box does not draw.
 */
export const NORMAL_KEYS = 'hjklwbeWBE0123456789$^xXdcyDCYsSiaIAoOupP~;,fFtTrJ';

/** The keys normal mode takes, by the engine's names. */
const TAKEN = new Set([
  ...NORMAL_KEYS,
  '<Left>',
  '<Right>',
  '<Up>',
  '<Down>',
  '<BS>',
]);

/** Keys that take the next one as a character, whatever it is. */
const TAKES_CHARACTER = /[fFtTr]$/;

/** After an operator, `i` and `a` begin a text object such as `iw`. */
const TEXT_OBJECT = /^\d*[dcy]\d*[ia]$/;

/**
 * The keys a press is in normal mode, as the engine names them, from chord's:
 * one, or each character of several that came in one read, as a quick
 * `dw` can. None for a press normal mode has no name for.
 */
export function vimKeyNames(
  input: string,
  key: {
    readonly leftArrow?: boolean;
    readonly rightArrow?: boolean;
    readonly upArrow?: boolean;
    readonly downArrow?: boolean;
    readonly backspace?: boolean;
    readonly delete?: boolean;
    readonly ctrl?: boolean;
    readonly meta?: boolean;
    readonly tab?: boolean;
  },
): string[] {
  const named = key.leftArrow
    ? '<Left>'
    : key.rightArrow
      ? '<Right>'
      : key.upArrow
        ? '<Up>'
        : key.downArrow
          ? '<Down>'
          : // Most terminals send the backspace key as DEL, which may read as delete.
            key.backspace || key.delete
            ? '<BS>'
            : undefined;

  if (named !== undefined) {
    return [named];
  }

  if (key.ctrl || key.meta || key.tab) {
    return [];
  }

  return [...input].filter((character) => character >= ' ');
}

/**
 * Whether normal mode takes the next key as the character it is, as after
 * `f` or `r`, rather than as a key with a meaning of its own.
 */
export function vimTakesCharacter(vim: Vim): boolean {
  return TAKES_CHARACTER.test(vim.pending.join(''));
}

/** Whether normal mode takes `name` next, with what is pending before it. */
export function vimTakes(vim: Vim, name: string): boolean {
  const typed = vim.pending.join('');

  return (
    TAKEN.has(name) || TAKES_CHARACTER.test(typed) || TEXT_OBJECT.test(typed)
  );
}

/**
 * Esc in insert mode: normal mode, the cursor one back onto the character it
 * was after, as vim leaves it. What insert mode changed is one step for `u`.
 */
export function vimEscape(
  vim: Vim,
  text: string,
  cursor: Cursor,
): {
  readonly vim: Vim;
  readonly cursor: Cursor;
} {
  const [line, column] = cursor;
  const changed = vim.entered !== undefined && vim.entered.text !== text;

  return {
    vim: {
      ...vim,
      mode: 'normal',
      pending: [],
      undo: changed ? pushed(vim.undo, vim.entered!) : vim.undo,
      entered: undefined,
      // Insert mode moved the cursor; `j` and `k` aim from where it is.
      goal: undefined,
    },
    cursor: [line, Math.max(0, column - 1)],
  };
}

/**
 * Characters typed at the cursor, as insert mode takes the rest of a read
 * whose first keys left normal mode, such as `ihi` typed quickly.
 */
export function typedAt(
  text: string,
  [line, column]: Cursor,
  typed: string,
): { readonly text: string; readonly cursor: Cursor } {
  const lines = text.split('\n');
  const current = lines[line] ?? '';
  const inserted = (current.slice(0, column) + typed).split('\n');
  const end = inserted.at(-1)!.length;

  inserted[inserted.length - 1] += current.slice(column);

  lines.splice(line, 1, ...inserted);

  return { text: lines.join('\n'), cursor: [line + inserted.length - 1, end] };
}

/** A pending command dropped, as Esc in normal mode does to one. */
export function vimCleared(vim: Vim): Vim {
  return { ...vim, pending: [] };
}

/** Insert mode again, as a sent prompt leaves the box: empty, nothing to undo. */
export function vimReset(vim: Vim): Vim {
  return { ...startingVim, register: vim.register };
}

/** Where the normal-mode cursor sits, as an offset into `text`; none on an empty line. */
export function cursorOffset(
  text: string,
  [line, column]: Cursor,
): number | undefined {
  const lines = text.split('\n');
  const current = lines[line];

  if (current === undefined || current.length === 0) {
    return undefined;
  }

  let offset = 0;

  for (let index = 0; index < line; index++) {
    offset += lines[index]!.length + 1;
  }

  return offset + Math.min(column, current.length - 1);
}

/**
 * One key in normal mode. `atoms` keeps a placeholder whole when a
 * deletion cuts into it.
 */
export function vimKey(
  vim: Vim,
  text: string,
  cursor: Cursor,
  key: string,
  atoms?: Atoms,
): VimStep {
  const same = { vim, text, cursor };
  const { pending } = vim;
  const idle = pending.length === 0;

  if (!vimTakes(vim, key)) {
    return same;
  }

  if (idle && key === 'u') {
    const last = vim.undo.at(-1);

    return last === undefined
      ? same
      : {
          vim: { ...vim, undo: vim.undo.slice(0, -1) },
          text: last.text,
          cursor: clipped(last.text, last.cursor),
        };
  }

  const lines = text.split('\n');

  if (idle && (key === 'k' || key === '<Up>') && cursor[0] === 0) {
    return { vim, history: 'older' };
  }

  if (
    idle &&
    (key === 'j' || key === '<Down>') &&
    cursor[0] === lines.length - 1
  ) {
    return { vim, history: 'newer' };
  }

  const editor = new Editor(text, cursor);
  const engine = engineOf();

  engine.enterVimMode(editor.cm);

  const kept = editor.cm.state.vim!;

  if (vim.goal !== undefined) {
    kept.lastMotion = vim.goal.motion as MotionFn | null;
    kept.lastHPos = vim.goal.column;
    kept.lastHSPos = vim.goal.left;
  }

  engine
    .getRegisterController()
    .unnamedRegister.setText(
      vim.register?.text ?? '',
      vim.register?.linewise ?? false,
    );

  try {
    for (const each of [...pending, key]) {
      editor.cm.operation(() => engine.handleKey(editor.cm, each, 'user'));
    }
  } catch {
    // A command the editor here cannot carry out is dropped, not chord.
    return { ...same, vim: vimCleared(vim) };
  }

  const state = editor.cm.state.vim!;
  const input = state.inputState;
  const unnamed = engine.getRegisterController().unnamedRegister;
  const still =
    input.keyBuffer.length > 0 ||
    input.operator !== null ||
    input.prefixRepeat.length > 0 ||
    input.motionRepeat.length > 0;
  let after = editor.text();
  const last = lines.length - 1;
  // `dd` on the last line takes the line break before it, as the engine
  // does on CodeMirror too; vim's register has the line alone. Only that
  // delete is undone here: a leading break anywhere else is a blank line.
  const lastLineCut =
    unnamed.linewise &&
    last > 0 &&
    cursor[0] === last &&
    after === lines.slice(0, last).join('\n') &&
    unnamed.toString() === `\n${lines[last]}\n`;
  const register: Register = {
    text: lastLineCut ? `${lines[last]}\n` : unnamed.toString(),
    linewise: unnamed.linewise,
  };
  let at = editor.cursor();
  const row = cursor[0];
  const above = lines.slice(0, row).join('\n');

  // A counted `dd` (or `dj`, `dG`) that reaches the last line leaves the
  // break before the first deleted line behind, a blank last line vim has
  // not; the register already holds the lines as vim does. A change (`2cc`,
  // `cj`) ends in insert mode on that blank line, which is its replacement.
  if (
    !state.insertMode &&
    unnamed.linewise &&
    row > 0 &&
    row < last &&
    after === `${above}\n` &&
    unnamed.toString() === `${lines.slice(row).join('\n')}\n`
  ) {
    after = above;
    at = [row - 1, lines[row - 1]!.search(/\S|$/)];
  }

  const widened = atoms?.(text, after);

  if (widened !== undefined) {
    after = widened.text;
    at = widened.cursor;
  }

  const cut = widened === undefined ? undefined : removed(text, after);
  const before: Snapshot = { text, cursor };
  const insert = state.insertMode;

  return {
    vim: {
      ...vim,
      mode: insert ? 'insert' : 'normal',
      pending: still ? [...pending, key] : [],
      register:
        cut === undefined
          ? register.text === '' && vim.register === undefined
            ? undefined
            : register
          : { text: cut, linewise: false },
      undo: !insert && after !== text ? pushed(vim.undo, before) : vim.undo,
      entered: insert ? before : undefined,
      goal: {
        motion: state.lastMotion,
        column: state.lastHPos,
        left: state.lastHSPos,
      },
    },
    text: after,
    cursor: at,
  };
}

function pushed(undo: readonly Snapshot[], snapshot: Snapshot): Snapshot[] {
  return [...undo, snapshot].slice(-UNDO_LIMIT);
}

/** A cursor kept on a character of its line, as normal mode keeps it. */
function clipped(text: string, [line, column]: Cursor): Cursor {
  const lines = text.split('\n');
  const row = Math.min(line, lines.length - 1);
  const length = lines[row]?.length ?? 0;

  return [row, Math.max(0, Math.min(column, length - 1))];
}

/** The stretch `after` lacks of `before`, one deletion apart. */
function removed(before: string, after: string): string {
  let start = 0;

  while (start < after.length && before[start] === after[start]) {
    start++;
  }

  return before.slice(start, start + before.length - after.length);
}

type Engine = ReturnType<typeof initVim>;

let engine: Engine | undefined;

/** The engine, made once: its registers and last `f` search are its own. */
function engineOf(): Engine {
  if (engine === undefined) {
    engine = initVim(Editor as unknown as CodeMirrorConstructor);

    engine.defineOperator('yank', yank(engine));
  }

  return engine;
}

/**
 * The library's yank, through its public `defineOperator`, less the
 * "lines yanked" message: that builds a DOM node before it asks the editor
 * to show it, which a terminal has none of, and the error it throws inside
 * `handleKey` lost the yank with it (owner, 2026-10-17, CHD-215 Q1). What it
 * yanked goes to the register, and the cursor stays where the yank began,
 * as the library leaves it outside visual mode, which chord never opens.
 */
function yank(vim: Engine): OperatorFn {
  return (cm, args, _ranges, oldAnchor) => {
    vim
      .getRegisterController()
      .pushText(
        args.registerName ?? undefined,
        'yank',
        cm.getSelection(),
        args.linewise,
        false,
      );

    return oldAnchor;
  };
}

type Handler = (...args: unknown[]) => void;

const handlers = new WeakMap<object, Map<string, Handler[]>>();

function on(target: object, type: string, handler: Handler) {
  const all = handlers.get(target) ?? new Map<string, Handler[]>();

  handlers.set(target, all);
  all.set(type, [...(all.get(type) ?? []), handler]);
}

function off(target: object, type: string, handler: Handler) {
  const all = handlers.get(target);

  all?.set(
    type,
    (all.get(type) ?? []).filter((each) => each !== handler),
  );
}

function signal(target: object, type: string, ...args: unknown[]) {
  for (const handler of handlers.get(target)?.get(type) ?? []) {
    handler(...args);
  }
}

function before(a: Pos, b: Pos): boolean {
  return a.line < b.line || (a.line === b.line && a.ch < b.ch);
}

/**
 * The editor the engine edits: the draft's lines and one cursor, with the
 * part of CodeMirror 5's interface that normal mode's motions and operators
 * reach. Scrolling, searching, dialogs and marks answer as an editor with
 * none of them would.
 */
class Editor {
  // What the engine reads and writes on its editor.
  state: CM5EditorInterface['state'] = {};
  marks = {};
  $mid = 0;
  curOp: CM5EditorInterface['curOp'] = null;
  options: Record<string, unknown> = {};
  #lines: string[];
  #anchor: Pos;
  #head: Pos;
  #input = {};

  constructor(text: string, [line, ch]: Cursor) {
    this.#lines = text.split('\n');
    this.#anchor = this.#head = this.clipPos({ line, ch });
  }

  get cm(): CM5EditorInterface {
    return this as unknown as CM5EditorInterface;
  }

  text(): string {
    return this.#lines.join('\n');
  }

  cursor(): Cursor {
    return [this.#head.line, this.#head.ch];
  }

  on(type: string, handler: Handler) {
    on(this, type, handler);
  }

  off(type: string, handler: Handler) {
    off(this, type, handler);
  }

  signal(type: string, ...args: unknown[]) {
    signal(this, type, ...args);
  }

  getValue(): string {
    return this.text();
  }

  setValue(text: string) {
    this.#lines = text.split('\n');
  }

  indexFromPos(pos: Pos): number {
    const { line, ch } = this.clipPos(pos);
    let index = ch;

    for (let row = 0; row < line; row++) {
      index += this.#lines[row]!.length + 1;
    }

    return index;
  }

  posFromIndex(index: number): Pos {
    let line = 0;
    let left = Math.max(0, index);

    while (line < this.#lines.length - 1 && left > this.#lines[line]!.length) {
      left -= this.#lines[line]!.length + 1;

      line++;
    }

    return { line, ch: Math.min(left, this.#lines[line]!.length) };
  }

  firstLine(): number {
    return 0;
  }

  lastLine(): number {
    return this.#lines.length - 1;
  }

  lineCount(): number {
    return this.#lines.length;
  }

  /** As CodeMirror clips: past either end is that end of the text. */
  clipPos(pos: Pos): Pos {
    const last = this.lastLine();

    if (pos.line < 0) {
      return { line: 0, ch: 0 };
    }

    if (pos.line > last) {
      return { line: last, ch: this.#lines[last]!.length };
    }

    const length = this.#lines[pos.line]!.length;

    return { line: pos.line, ch: Math.max(0, Math.min(pos.ch, length)) };
  }

  setCursor(line: number | Pos, ch?: number) {
    const pos = this.clipPos(
      typeof line === 'number' ? { line, ch: ch ?? 0 } : line,
    );

    this.#anchor = this.#head = pos;

    this.signal('cursorActivity', this);
  }

  getCursor(which = 'head'): Pos {
    const first = before(this.#head, this.#anchor) ? this.#head : this.#anchor;
    const last = first === this.#head ? this.#anchor : this.#head;

    return which === 'anchor'
      ? this.#anchor
      : which === 'start'
        ? first
        : which === 'end'
          ? last
          : this.#head;
  }

  listSelections() {
    return [{ anchor: this.#anchor, head: this.#head }];
  }

  setSelections(ranges: { anchor: Pos; head: Pos }[]) {
    const [range] = ranges;

    if (range !== undefined) {
      this.#anchor = this.clipPos(range.anchor);
      this.#head = this.clipPos(range.head);

      this.signal('cursorActivity', this);
    }
  }

  setSelection(anchor: Pos, head: Pos) {
    this.setSelections([{ anchor, head }]);
  }

  getLine(line: number): string {
    return this.#lines[line] ?? '';
  }

  getLineHandle(line: number) {
    return { row: line, index: line };
  }

  getLineNumber(handle: { row: number }): number {
    return handle.row;
  }

  releaseLineHandles() {}

  getRange(from: Pos, to: Pos): string {
    const [a, b] = [this.indexFromPos(from), this.indexFromPos(to)];

    return this.text().slice(Math.min(a, b), Math.max(a, b));
  }

  replaceRange(text: string, from: Pos, to = from) {
    const whole = this.text();
    const [a, b] = [this.indexFromPos(from), this.indexFromPos(to)];
    const start = Math.min(a, b);

    this.setValue(whole.slice(0, start) + text + whole.slice(Math.max(a, b)));
    this.setCursor(this.posFromIndex(start + text.length));
    this.signal('change', this, { text: text.split('\n'), origin: '+input' });
  }

  replaceSelection(text: string) {
    this.replaceRange(text, this.getCursor('start'), this.getCursor('end'));
  }

  replaceSelections(texts: string[]) {
    this.replaceSelection(texts[0] ?? '');
  }

  getSelection(): string {
    return this.getRange(this.#anchor, this.#head);
  }

  getSelections(): string[] {
    return [this.getSelection()];
  }

  somethingSelected(): boolean {
    return before(this.#anchor, this.#head) || before(this.#head, this.#anchor);
  }

  getInputField() {
    return this.#input;
  }

  focus() {}

  blur() {}

  defaultTextHeight(): number {
    return 1;
  }

  findMatchingBracket() {
    return { to: undefined };
  }

  scanForBracket() {
    return null;
  }

  indentLine() {}

  indentMore() {}

  indentLess() {}

  execCommand() {}

  setBookmark(pos: Pos) {
    const offset = this.indexFromPos(pos);

    return {
      cm: this,
      id: 0,
      offset,
      assoc: 0,
      clear() {},
      find: () => this.posFromIndex(offset),
      update() {},
    };
  }

  addOverlay() {}

  removeOverlay() {}

  getSearchCursor() {
    return {
      findNext: () => null,
      findPrevious: () => null,
      find: () => null,
      from: () => undefined,
      to: () => undefined,
      replace() {},
      match: null,
    };
  }

  findPosV(start: Pos, amount: number) {
    const line = start.line + amount;

    return {
      ...this.clipPos({ line, ch: start.ch }),
      hitSide: line < 0 || line > this.lastLine(),
    };
  }

  charCoords(pos: Pos) {
    return { left: pos.ch, top: pos.line, bottom: pos.line + 1 };
  }

  coordsChar(coords: { left: number; top: number }): Pos {
    return this.clipPos({ line: coords.top, ch: coords.left });
  }

  getScrollInfo() {
    const height = this.#lines.length;

    return {
      left: 0,
      top: 0,
      height,
      width: 0,
      clientHeight: height,
      clientWidth: 0,
    };
  }

  scrollTo() {}

  scrollIntoView() {}

  getWrapperElement() {
    return {};
  }

  getMode() {
    return { name: 'text' };
  }

  operation<T>(run: () => T): T {
    if (this.curOp) {
      return run();
    }

    this.curOp = { $d: 0 };

    try {
      return run();
    } finally {
      this.curOp = null;
    }
  }

  setOption(name: string, value: unknown) {
    this.options[name] = value;
  }

  getOption(name: string): unknown {
    return name === 'tabSize' ? 2 : this.options[name];
  }

  toggleOverwrite() {}

  getTokenTypeAt() {
    return '';
  }

  isInMultiSelectMode(): boolean {
    return false;
  }

  virtualSelectionMode(): boolean {
    return false;
  }

  getLastEditEnd(): Pos {
    return this.#head;
  }

  openNotification() {
    return () => {};
  }

  openDialog() {
    return () => {};
  }

  // What the engine reads off the constructor it is given.
  static isMac = false;
  static Pos = function (line: number, ch: number): Pos {
    return { line, ch };
  };
  static commands = {
    // `o` and `O` open their line through these; the box does not indent.
    newlineAndIndent(cm: Editor) {
      cm.replaceSelection('\n');
    },
    newlineAndIndentContinueComment(cm: Editor) {
      cm.replaceSelection('\n');
    },
  };
  static keys = {};
  static isWordChar = (character: string) => /\w/.test(character);
  static on = on;
  static off = off;
  static signal = signal;
  static addClass() {}
  static rmClass() {}
  static e_preventDefault() {}
  static e_stop() {}
  static lookupKey() {}
  static findMatchingTag() {}
  static findEnclosingTag() {}
}
