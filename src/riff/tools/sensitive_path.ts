/** Paths whose mutations need permission even inside the session directory. */
import { basename, sep } from 'node:path';

const STARTUP = new Set([
  '.bashrc',
  '.bash_profile',
  '.profile',
  '.zshrc',
  '.zprofile',
  '.zshenv',
  '.zlogin',
]);
const KEYS = new Set(['id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519']);

/** Tests a resolved path, without reading the file or guessing its contents. */
export function sensitivePath(path: string): boolean {
  const parts = path.split(sep);
  const name = basename(path);

  return (
    parts.includes('.git') ||
    parts.includes('.ssh') ||
    name.startsWith('.env') ||
    /\.(pem|key|p12|pfx)$/.test(name) ||
    KEYS.has(name) ||
    STARTUP.has(name) ||
    parts.some(
      (part, index) =>
        part === 'Library' && parts[index + 1] === 'LaunchAgents',
    )
  );
}
