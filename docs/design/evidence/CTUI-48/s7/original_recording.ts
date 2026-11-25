// Capture launcher only: original UI, fake agent, recording clipboard factory.
// Run from the task root; CHORD_SOURCE locates the read-only sibling checkout.
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const source = process.env.CHORD_SOURCE!;
const mode = process.argv[2] ?? "auto";
const theme = process.argv[3] ?? "dark";
const place = resolve(`build/ctui48-s7-original-${mode}-${theme}`);
mkdirSync(`${place}/config/chord`, {recursive:true});
mkdirSync(`${place}/state`, {recursive:true});
mkdirSync("build/ctui48-s7-project", {recursive:true});
process.env.XDG_CONFIG_HOME = `${place}/config`;
process.env.XDG_STATE_HOME = `${place}/state`;
process.env.CHORD_RESOURCE_FIXTURE = "true";
process.env.NODE_ENV = "production";
if(theme === "plain") process.env.NO_COLOR = "1";
writeFileSync(`${place}/config/chord/settings.json`, JSON.stringify({theme: theme === "light" ? "light" : "dark", copyOnSelect:mode !== "manual"}));
const journal = `${place}/record.jsonl`;
writeFileSync(journal, "");
const record = (event: object) => appendFileSync(journal, `${JSON.stringify(event)}\n`);
const { startServices, cli } = await import(`${source}/src/main.tsx`);
// Lead-approved presentation input avoids a private owner directory in header.
// This does not change HOME, original source, session or selection behavior.
const { cloneElement } = await import(Bun.resolveSync("react", source));
const render = startServices.render;
const presentation = (element: any) => cloneElement(element, {home: "capture-home"});
startServices.render = ((element: any, ...args: any[]) => {
  const app = render(presentation(element), ...args);
  const rerender = app.rerender.bind(app);
  app.rerender = (next: any) => rerender(presentation(next));
  return app;
}) as typeof render;
startServices.copier = (() => ({
 copy(text: string, signal: AbortSignal) {
  record({event:"attempt",text,cancelled:signal.aborted});
  signal.addEventListener("abort",()=>record({event:"cancel"}),{once:true});
  if(mode === "timeout") return new Promise(()=>{});
  if(mode === "failure") return Promise.resolve({host:{status:"failed",error:new Error("recording clipboard refused")},terminal:{status:"not-attempted",capability:"unknown"}});
  record({event:"write",text});
  return Promise.resolve({host:{status:"not-attempted",capability:"unknown"},terminal:{status:"attempted",capability:"supported"}});
 },
 disposed: async()=>{},
})) as typeof startServices.copier;
const {fakeAgentCommand} = await import(`${source}/tests/fixtures/fake.ts`);
const {quote} = await import(Bun.resolveSync("shell-quote",source));
await cli.parse(["fake","--agent-command",quote(fakeAgentCommand()),"-C","build/ctui48-s7-project","--no-mcp-servers"]);
