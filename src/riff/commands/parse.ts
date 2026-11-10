/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/shell_command/command_effect.zig, Apache-2.0.
 * chord uses unbash's typed AST instead of fx's lexer; unsupported nodes review.
 */
import { parse } from 'unbash';
import type {
  Command,
  PipelineNode,
  Redirection,
  Word as ShellWord,
} from 'unbash';

/** One shell word. `raw` is its source text; `unquoted` the source text of its
 * unquoted parts only; `dquoted` that of its double-quoted parts; `value` the word after quote removal. `literal` is
 * false when any part is an expansion, glob, brace or other non-literal. */
export type Word = {
  raw: string;
  unquoted: string;
  dquoted: string;
  value: string;
  literal: boolean;
};
export type Redirect = {
  raw: string;
  fd: number | null;
  op: string;
  target: Word | null;
};
export type Stage = {
  assigns: number;
  words: Word[];
  redirects: Redirect[];
  redirectLast: boolean;
};
export type Line = { join: '&&' | '|' | null; stages: Stage[] };

const nonLiteral = (raw: string): Word => ({
  raw,
  unquoted: raw,
  dquoted: '',
  value: raw,
  literal: false,
});

// ---------- unbash ----------
export function parseLine(src: string): Line | null {
  const ast = parse(src);

  if (ast.errors?.length) {
    return null;
  }

  if (ast.commands.length !== 1) {
    return null;
  }

  const st = ast.commands[0]!;

  if (st.background) {
    return null;
  }

  // unbash drops comments; text outside the statement is one.
  if (src.slice(0, st.pos).trim() !== '' || src.slice(st.end).trim() !== '') {
    return null;
  }

  const c = st.command;
  let join: Line['join'] = null;
  let nodes: readonly PipelineNode[];

  if (c.type === 'AndOr') {
    if (!c.operators.every((o) => o === '&&')) {
      return null;
    }

    join = '&&';
    nodes = c.commands;
  } else if (c.type === 'Pipeline') {
    if (c.prefixes.length || !c.operators.every((o) => o === '|')) {
      return null;
    }

    join = '|';
    nodes = c.commands;
  } else {
    nodes = [c];
  }

  const stages: Stage[] = [];

  for (const n of nodes) {
    if (n.type !== 'Command') {
      return null;
    }

    stages.push(unbashStage(n, src));
  }

  return { join, stages };
}

function unbashStage(cmd: Command, src: string): Stage {
  const words: Word[] = [];
  const redirects: Redirect[] = [];
  let assigns = 0;
  let prefixRedirect = false;

  for (const p of cmd.prefix) {
    if (p.type === 'Assignment') {
      assigns++;
    } else {
      prefixRedirect = true;

      redirects.push(unbashRedirect(p, src));
    }
  }

  if (cmd.name) {
    words.push(unbashWord(cmd.name));
  }

  for (const s of cmd.suffix) {
    if (s.type === 'Word') {
      words.push(unbashWord(s));
    } else if (s.type === 'Assignment') {
      words.push(nonLiteral(s.text));
    } else {
      redirects.push(unbashRedirect(s, src));
    }
  }

  const last = cmd.suffix.at(-1);
  const redirectLast =
    !prefixRedirect &&
    last !== undefined &&
    last.type !== 'Word' &&
    last.type !== 'Assignment';

  return { assigns, words, redirects, redirectLast };
}

function unbashRedirect(r: Redirection, src: string): Redirect {
  return {
    raw: src.slice(r.pos, r.end),
    fd: r.descriptor?.type === 'FileDescriptor' ? r.descriptor.value : null,
    op: r.operator,
    target: 'target' in r && r.target ? unbashWord(r.target) : null,
  };
}

function unbashWord(w: ShellWord): Word {
  const parts = w.parts ?? [{ type: 'Literal', text: w.text, value: w.value }];
  const out: Word = {
    raw: w.text,
    unquoted: '',
    dquoted: '',
    value: '',
    literal: true,
  };

  for (const p of parts) {
    if (p.type === 'Literal') {
      out.unquoted += p.text;
      out.value += p.value;
    } else if (p.type === 'SingleQuoted') {
      out.value += p.value;
    } else if (
      p.type === 'DoubleQuoted' &&
      p.parts.every((q) => q.type === 'Literal')
    ) {
      for (const q of p.parts) {
        out.dquoted += q.text;
        out.value += q.value;
      }
    } else {
      out.literal = false;
    }
  }

  return out;
}
