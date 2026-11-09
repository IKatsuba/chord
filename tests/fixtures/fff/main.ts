// Built as chord's binary is, it greps the directory it is given through the
// fff Worker and prints what it found, from wherever it runs.
import process from 'node:process';
import { openFinder } from '../../../src/platform/fff.ts';

const finder = openFinder(process.argv[2]!);
const found = await finder.grep('needle', {}, new AbortController().signal);

await finder.destroy();
console.log(JSON.stringify(found.items.map((item) => item.relativePath)));
