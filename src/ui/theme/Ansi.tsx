import { runs } from './text.ts';

/**
 * A string with SGR of its own (markdansi's, emphasize's) as `<span>`s, for
 * inside a `<text>`: each run's style on top of the text's.
 */
export function Ansi({ text }: { text: string }) {
  return runs(text).map((run, index) => (
    <span
      key={index}
      {...(run.fg === undefined ? {} : { fg: run.fg })}
      {...(run.bg === undefined ? {} : { bg: run.bg })}
      attributes={run.attributes}
    >
      {run.text}
    </span>
  ));
}
