import {existsSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';

// Regenerate from the installed original package; CHORD_SOURCE selects
// the checkout, otherwise ../../../chord from packages/chord_tui. A
// worktree sets CHORD_SOURCE. No dependency is installed here.
const source = resolve(process.env.CHORD_SOURCE ?? '../../../chord');
const fzfModule = `${source}/node_modules/fzf/dist/fzf.es.js`;
if (!existsSync(fzfModule)) {
  console.error(
    `No chord checkout with its dependencies at ${source}: set CHORD_SOURCE ` +
      'to a chord checkout where bun install has run.',
  );
  process.exit(1);
}
const cases = [
  {name:'duplicate identities and zero limit', items:['same','same','sampler','same'], queries:['','sam','same','missing'], limit:0},
  {name:'duplicate identities and cut ties', items:['same','same','sampler','same'], queries:['','sam','same'], limit:2, byLength:true},
  {name:'normalization disabled', items:['éclair','e\u0301clair','ECLAIR','ec\u0301lair','🙂éclair'], queries:['é','e\u0301','ecl','É','🙂e'], normalize:false},
  {name:'UTF16 and controls', items:['a🙂b','🙂a🙂b','a\u200db','e\u0301🙂界','\x1b[31mred\x1b[0m','line\nname','a\tb','\ud800x','x\udfff'], queries:['🙂','ab','e界','31','\x1b','\n','\t','\ud800','\udfff']},
  {name:'case sensitive unicode', items:['İstanbul','istanbul','Σίσυφος','σίσυφος','ẞeta','ßeta','Æon','æon'], queries:['i','İ','σ','Σ','ß','ẞ','æ','Æ'], casing:'case-sensitive'},
  {name:'case insensitive unicode', items:['İstanbul','istanbul','Σίσυφος','σίσυφος','ẞeta','ßeta','Æon','æon'], queries:['i','İ','σ','Σ','ß','ẞ','æ','Æ'], casing:'case-insensitive'},
  {name:'slab boundary V2', items:['ab'.repeat(256)], queries:['ab'.repeat(100)]},
  {name:'slab boundary V1', items:['ab'.repeat(256)+'a'], queries:['ab'.repeat(100)]},
  {name:'long accent fallback', items:['é/'.repeat(800)+'stop','e/'.repeat(800)+'stop'], queries:['e/'.repeat(70)+'stop','É/'.repeat(70)]},
];

for (const casing of ['smart-case', 'case-insensitive', 'case-sensitive']) {
  cases.push({name:`special casing boundaries ${casing}`,
    items:['i\u0307stanbul', 'istanbul', 'İstanbul', 'ος', 'οσ', "ος'", "οσ'α", 'ο\u200dς', 'ο\u200dσα', '𐐨ς', '𐐨σ', 'aς', 'aσ', '界σ'],
    queries:['İ', 'İst', 'ΟΣ', "ΟΣ'", "ΟΣ'Α", 'Ο\u200dΣ', 'Ο\u200dΣΑ', '𐐀Σ', 'aΣ', '界Σ', 'Σ'],
    casing});
}
let seed=139;
const next=()=> (seed=(Math.imul(seed,1664525)+1013904223)>>>0);
const alphabet=['a','b','c','A','B','/','_',' ','é','界','🙂'];
const random=length=>Array.from({length},()=>alphabet[next()%alphabet.length]).join('');
for (const casing of ['smart-case','case-insensitive','case-sensitive']) {
  cases.push({name:`seeded ${casing}`, items:Array.from({length:30},()=>random(12)),queries:Array.from({length:12},()=>random(2)),casing,byLength:true,limit:9});
}
let moduleId=0;
const out=[];
for(const c of cases){
  const {Fzf,byLengthAsc}=await import(`${source}/node_modules/fzf/dist/fzf.es.js?tester=${moduleId++}`);
  const items=c.items.map((text,index)=>({text,index}));
  const options={selector:item=>item.text,casing:c.casing??'smart-case',normalize:c.normalize??true,...(c.limit!==undefined?{limit:c.limit}:{}),...(c.byLength?{tiebreakers:[byLengthAsc]}:{})};
  const results=[];
  for(const query of c.queries){
    const found=new Fzf(items,options).find(query);
    const rows=[];
    for(const r of found){
      if(query===''){rows.push([r.item.index,r.score,r.start,r.end,[]]);continue;}
      const {Fzf:Fresh}=await import(`${source}/node_modules/fzf/dist/fzf.es.js?tester=${moduleId++}`);
      const [fresh]=new Fresh([r.item],options).find(query);
      rows.push([r.item.index,r.score,fresh.start,r.end,[...fresh.positions].sort((a,b)=>a-b)]);
    }
    results.push(rows);
  }
  out.push({...c,results});
}
writeFileSync('test/text/fzf_tester_golden.json',JSON.stringify(out));
console.log(`${out.length} independent cases, ${out.reduce((n,c)=>n+c.queries.length,0)} queries`);
