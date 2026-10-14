/** A one-pixel PNG, as base64: what a test's clipboard holds. */
export const PIXEL_PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/** Its bytes, as a file holds them. */
export const PIXEL_BYTES: Uint8Array = new Uint8Array(
  Buffer.from(PIXEL_PNG, 'base64'),
);
