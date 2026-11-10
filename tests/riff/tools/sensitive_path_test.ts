import { describe, expect, test } from 'bun:test';
import { sensitivePath } from '../../../src/riff/tools/sensitive_path.ts';

describe('sensitive mutation paths', () => {
  test('recognizes protected segments and basenames at any depth', () => {
    for (const path of [
      '.git',
      '.git/config',
      'nested/.git/HEAD',
      '.env',
      '.env.local',
      'cert.pem',
      'cert.key',
      'cert.p12',
      'cert.pfx',
      'id_rsa',
      'id_dsa',
      'id_ecdsa',
      'id_ed25519',
      '.ssh',
      '.ssh/config',
      '.bashrc',
      '.bash_profile',
      '.profile',
      '.zshrc',
      '.zprofile',
      '.zshenv',
      '.zlogin',
      'Library/LaunchAgents',
      'Library/LaunchAgents/job.plist',
    ]) {
      expect(sensitivePath(`/project/${path}`)).toBe(true);
    }
  });

  test('does not mistake ordinary names for sensitive segments', () => {
    for (const path of [
      '.github/a.yml',
      'src/env.ts',
      '.environment/file',
      'keys.txt',
      'cert.pem.txt',
      'id_rsa.pub',
      '.ssh-copy/config',
      'Library/LaunchAgentsCopy/job',
    ]) {
      expect(sensitivePath(`/project/${path}`)).toBe(false);
    }
  });
});
