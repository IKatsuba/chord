/**
 * How much riff's read, list and search give the model in one call. The
 * design names no numbers (CHD-485, "Tools"); these are chord's choice.
 */
export const LIMITS = {
  /** Lines a read returns when the call names no `limit`. */
  readLines: 2000,
  /** Bytes a read returns at most, whatever its range. */
  readBytes: 256 * 1024,
  /** Characters of one line a read returns before cutting it. */
  readLineChars: 2000,
  /** Bytes of shell output the model receives at most. */
  shellBytes: 256 * 1024,
  /** Lines of shell output the model receives at most. */
  shellLines: 2000,
  /** Bytes file-type looks at to tell a binary file. */
  sniffBytes: 4100,
  /** Entries a list returns when the call names no `limit`. */
  listPage: 100,
  /** Entries a list returns at most. */
  listMax: 500,
  /** Matches a search returns when the call names no `limit`. */
  searchPage: 100,
  /** Matches a search returns at most. */
  searchMax: 500,
  /** Matching lines a search takes from one file. */
  searchPerFile: 20,
  /** Context lines a search gives around a match at most. */
  searchContext: 10,
  /** How long one search may run before it answers with what it found. */
  searchMs: 10_000,
  /** Bytes of one skill file the `skill` tool reads at most, to page it. */
  skillBytes: 4 * 1024 * 1024,
  /** Resources a skill's first page names at most. */
  skillResources: 100,
} as const;
