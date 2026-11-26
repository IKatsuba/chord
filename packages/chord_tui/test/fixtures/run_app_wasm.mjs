// Runs a module from `dart compile wasm` under Node: argv is the .mjs
// loader and the .wasm it loads.
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const [loader, wasm] = process.argv.slice(2);
const { compile } = await import(pathToFileURL(loader).href);
const app = await compile(await readFile(wasm));
const instance = await app.instantiate({});
instance.invokeMain();
