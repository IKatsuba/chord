import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const original = await import(pathToFileURL(resolve(process.env.CHORD_SOURCE!, 'src/files.ts')).href);
console.log(JSON.stringify((await original.listFiles(process.argv[2])).sort()));
