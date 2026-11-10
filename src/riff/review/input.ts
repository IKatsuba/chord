/** Bounded evidence for one safety review; assistant prose has no input here. */
import escapeHtml from 'escape-html';
import { Buffer } from 'node:buffer';
import stripAnsi from 'strip-ansi';

export type ReviewAction =
  | { readonly tool: 'shell'; readonly command: string; readonly cwd: string }
  | { readonly tool: 'read'; readonly real: string }
  | {
      readonly tool: 'edit' | 'write';
      readonly real: string;
      readonly existed: boolean;
      readonly additions: number;
      readonly deletions: number;
      readonly diff: string;
    };

/** Only results from tools run in the current turn belong in this evidence. */
export interface ReviewResult {
  readonly id: string;
  readonly tool: string;
  readonly text: string;
}

export interface ReviewRequests {
  readonly current: string;
  readonly first: string;
  /** Most recent first, excluding current and first. */
  readonly recent: readonly string[];
}

export interface ReviewEvidence {
  readonly action: ReviewAction;
  readonly requests: ReviewRequests;
  /** Newest first, never from an earlier turn. */
  readonly results: readonly ReviewResult[];
  readonly omittedResults?: number;
  readonly branch?: string;
}

export type ReviewInput =
  | { readonly outcome: 'incomplete'; readonly reason: string }
  | { readonly outcome: 'ready'; readonly text: string };

const ACTION_BYTES = 64 * 1024;
const OMITTED = '...[evidence omitted]...';

/** Cuts only between Unicode code points, including when keeping a tail. */
function prefix(text: string, limit: number): string {
  let size = 0;
  let end = 0;

  for (const char of text) {
    size += Buffer.byteLength(char);

    if (size > limit) {
      break;
    }

    end += char.length;
  }

  return text.slice(0, end);
}

/** Context may be abbreviated; action fields may never be abbreviated. */
export function excerpt(text: string, limit: number): string {
  if (Buffer.byteLength(text) <= limit) {
    return text;
  }

  if (limit < Buffer.byteLength(OMITTED)) {
    return prefix(OMITTED, limit);
  }

  const remaining = limit - Buffer.byteLength(OMITTED);
  const head = prefix(text, Math.ceil(remaining / 2));
  const tail = [
    ...prefix([...text].reverse().join(''), Math.floor(remaining / 2)),
  ]
    .reverse()
    .join('');

  return head + OMITTED + tail;
}

/** Keep control bytes out of the terminal and XML text out of its structure. */
function encoded(text: string): string {
  const safe = stripAnsi(text).replace(/[\p{Cc}\p{Cf}]/gu, (char) =>
    char === '\n' || char === '\t'
      ? char
      : `\\u${char.codePointAt(0)?.toString(16).padStart(4, '0')}`,
  );

  return escapeHtml(safe);
}

const field = (name: string, value: string) =>
  `<${name}>${encoded(value)}</${name}>`;

/** Builds the inspectable pending action and bounded, explicitly labelled context. */
export function reviewInput(evidence: ReviewEvidence): ReviewInput {
  const entries = Object.entries(evidence.action);

  for (const [name, value] of entries) {
    if (Buffer.byteLength(String(value)) > ACTION_BYTES) {
      return {
        outcome: 'incomplete',
        reason: `The pending action's ${name} exceeds the 64 KiB review limit.`,
      };
    }
  }

  const rows = [
    '<review_data>',
    '<normalized_action>',
    ...entries.map(([name, value]) => field(name, String(value))),
    '</normalized_action>',
  ];

  if (evidence.branch !== undefined) {
    rows.push(field('current_branch', excerpt(evidence.branch, 255)));
  }

  if (evidence.action.tool === 'shell' || evidence.action.tool === 'read') {
    let remaining = 1024;
    const requests = [
      ['current_request', evidence.requests.current],
      ['first_root_user_request', evidence.requests.first],
      ...evidence.requests.recent.map((text) => ['recent_request', text]),
    ] as const;

    rows.push('<trusted_root_context>');

    for (const [name, text] of requests) {
      const kept = excerpt(text ?? '', remaining);

      rows.push(field(name ?? 'recent_request', kept));

      remaining -= Buffer.byteLength(kept);
    }

    rows.push('</trusted_root_context>');
  }

  rows.push('<prior_tool_results trust="untrusted">');

  let remaining = 8192;
  let count = 0;

  for (const result of evidence.results.slice(0, 16)) {
    if (remaining === 0) {
      break;
    }

    const text = excerpt(result.text, Math.min(1024, remaining));

    remaining -= Buffer.byteLength(text);

    count++;

    rows.push(
      '<result>',
      field('id', excerpt(result.id, 512)),
      field('tool', excerpt(result.tool, 512)),
      field('text', text),
      '</result>',
    );
  }

  rows.push(
    field(
      'omitted_results',
      String(evidence.results.length - count + (evidence.omittedResults ?? 0)),
    ),
    '</prior_tool_results>',
    '</review_data>',
  );

  return { outcome: 'ready', text: rows.join('\n') };
}
