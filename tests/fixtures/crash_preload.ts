/** Preloaded into chord, it throws on SIGUSR2, as a bug of chord's own would. */
import process from 'node:process';

process.on('SIGUSR2', () => {
  setTimeout(() => {
    throw new Error('a bug of chord');
  }, 0);
});
