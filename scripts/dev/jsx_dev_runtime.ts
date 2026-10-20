/**
 * `react/jsx-dev-runtime` as chord's binary gives it to OpenTUI, on React's
 * production JSX runtime: OpenTUI's published JS builds its elements with
 * `jsxDEV`, its ErrorBoundary's fallback among them, and React 19's
 * production `jsx-dev-runtime` exports `jsxDEV` as undefined (CHD-468).
 */
import type { ElementType, Key } from 'react';
import { Fragment, jsx, jsxs } from 'react/jsx-runtime';

export { Fragment };

/**
 * The element `jsxDEV` makes, without the source and owner only React's
 * development build reads.
 */
export function jsxDEV(
  type: ElementType,
  props: unknown,
  key: Key | undefined,
  isStaticChildren: boolean,
) {
  return (isStaticChildren ? jsxs : jsx)(type, props, key);
}
