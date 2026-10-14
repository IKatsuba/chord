import { TextAttributes } from '@opentui/core';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { useColours } from './context.ts';
import { GLYPHS, type StripView } from './strip.ts';

/**
 * The header with two or more sessions open: ` chord`, a tab for each, the
 * one in front inverse and bold, which reads in a dark theme, a light one
 * and with no colour alike, and the directory once on the right.
 */
export function Strip({ view }: { view: StripView }) {
  const colours = useColours();
  const glyphColour = {
    asking: colours.warning,
    failed: colours.error,
    replied: colours.success,
    working: undefined,
  };

  return (
    <box
      flexDirection='row'
      paddingX={1}
      justifyContent='space-between'
      flexShrink={0}
    >
      <text {...CUT}>
        <span attributes={BOLD}>chord</span>
        {view.pieces.map((piece, index) =>
          piece.kind === 'gap' ? (
            <span key={index}>{piece.text}</span>
          ) : piece.kind === 'front' ? (
            <span key={index} attributes={TextAttributes.INVERSE | BOLD}>
              {piece.text}
            </span>
          ) : (
            <span key={index}>
              <span attributes={DIM}>{piece.text}</span>
              {piece.glyph && (
                <span
                  {...(glyphColour[piece.glyph] === undefined
                    ? { attributes: DIM }
                    : fg(glyphColour[piece.glyph]))}
                >
                  {` ${GLYPHS[piece.glyph]}`}
                </span>
              )}
            </span>
          ),
        )}
      </text>
      <box flexShrink={0} marginLeft={2}>
        <text {...TEXT} attributes={DIM}>
          {view.directory}
        </text>
      </box>
    </box>
  );
}
