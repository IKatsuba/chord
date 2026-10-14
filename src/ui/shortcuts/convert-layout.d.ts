/** convert-layout ships no types; one layout's module is these two. */
declare const layout: {
  /** Text typed on US keys as the layout's keys in the same places give it. */
  fromEn(text: string): string;
  /** Text typed on the layout as the US keys in the same places give it. */
  toEn(text: string): string;
};

export default layout;
