const root=process.cwd();
const {createElement:h}=await import(root+'/node_modules/react/index.js');
const {useTerminalDimensions}=await import(root+'/node_modules/@opentui/react/index.js');
const {openTerminal,render,useApp}=await import(root+'/src/ui/app/renderer.tsx');
const {usePress}=await import(root+'/src/ui/app/input.ts');
const {ModelPicker,ConfigPicker}=await import(root+'/src/ui/pickers/Pickers.tsx');
const {modelsFrom}=await import(root+'/src/session/models.ts');
const {optionsFromConfigOptions}=await import(root+'/src/session/config.ts');
const middle='long label 界👩‍💻 '.repeat(12);
const option=(id,name,category,values)=>({id,name,type:'select',category,currentValue:values[0].value,options:values});
const configOptions=[option('model','Model','model',[{value:'long',name:`Model ${middle} tail`},{value:'short',name:'Short model'}]),option('effort','Effort','thought_level',[{value:'long',name:`Value ${middle} tail`},{value:'short',name:'Short value'}]),option('other',`Option ${middle} tail`,'other',[{value:'long',name:'Value tail'}])];
const options=optionsFromConfigOptions(configOptions);
const agent='fixture-'+'界👩‍💻long'.repeat(12)+'-tail';
const kind=process.argv[2]??'model';
function Fixture(){const {height:rows}=useTerminalDimensions();const {exit}=useApp();usePress((input,key)=>{if(key.escape||(key.ctrl&&input==='q')){exit();return true;}});const props={rows:Math.max(3,Math.floor(rows/4)),room:rows,agent,active:true};const picker=kind==='model'?h(ModelPicker,{...props,models:modelsFrom(configOptions),configOptions,onPick:()=>{}}):h(ConfigPicker,{...props,options,option:kind==='values'?options.find(o=>o.id==='effort'):undefined,from:undefined,onOpen:()=>{},onPick:()=>{}});return h('box',{height:'100%',width:'100%',justifyContent:'flex-end',flexDirection:'column'},picker);}
const terminal=await openTerminal({mouse:true});const app=render(h(Fixture),terminal);await app.waitUntilExit();
