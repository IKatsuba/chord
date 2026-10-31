/**
 * `openat(2)`, which `node:fs` does not have: the one call that opens a name
 * inside a directory already open, so a directory swapped for a link after it
 * was opened cannot redirect the open. Through `bun:ffi`, as OpenTUI's native
 * library loads (`docs/decisions.md`, "The settings tool's read of a project
 * file").
 */
import { dlopen, FFIType, read } from 'bun:ffi';
import process from 'node:process';

/** The open file, or why not, by `errno`. */
export type OpenedAt = { readonly fd: number } | { readonly errno: number };

export type OpenAt = (dir: number, name: string, flags: number) => OpenedAt;

/** The libc of each target's platform, musl's after glibc's as a fallback. */
const LIBC: Readonly<Record<string, readonly string[]>> = {
  darwin: ['/usr/lib/libSystem.B.dylib'],
  linux: [
    'libc.so.6',
    `libc.musl-${process.arch === 'arm64' ? 'aarch64' : 'x86_64'}.so.1`,
  ],
};

function load(name: string, errno: string): OpenAt {
  const { symbols } = dlopen(name, {
    openat: {
      args: [FFIType.i32, FFIType.ptr, FFIType.i32],
      returns: FFIType.i32,
    },
    [errno]: { args: [], returns: FFIType.ptr },
  });
  const errnoAt = symbols[errno] as unknown as () => number;

  return (dir, file, flags) => {
    const fd = symbols.openat(dir, Buffer.from(`${file}\0`), flags);

    return fd >= 0
      ? { fd }
      : { errno: read.i32(errnoAt() as Parameters<typeof read.i32>[0]) };
  };
}

let loaded: OpenAt | null | undefined;

/**
 * `openat`, or undefined where no libc gives it, which its caller must take
 * as a refusal: there is no safe way to open the name otherwise.
 */
export function openAt(): OpenAt | undefined {
  if (loaded === undefined) {
    loaded = null;

    for (const name of LIBC[process.platform] ?? []) {
      try {
        loaded = load(
          name,
          process.platform === 'darwin' ? '__error' : '__errno_location',
        );

        break;
      } catch {
        // The next name, or none: the caller refuses.
      }
    }
  }

  return loaded ?? undefined;
}
