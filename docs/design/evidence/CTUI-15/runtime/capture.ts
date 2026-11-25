// Drives the original's fake agent with the port's M1 client capabilities
// (none) and records every message both ways, with milliseconds since spawn.
//
//   deno run --allow-run --allow-read --allow-write --allow-env capture.ts \
//     <chord checkout> <out dir> [scenario...]
//
// Each scenario runs in a fresh fake: initialize, session/new, one prompt
// whose text is "go" (the scenario comes from --scenario). Permission
// requests are answered with their first option. `cancel:<scenario>` sends
// session/cancel after the first agent_message_chunk; `close:<scenario>`
// cancels and then closes stdin one second later.
const [chord, out, ...wanted] = Deno.args;
const bun = Deno.env.get("CHORD_BUN") ?? "bun";

type Line = { ms: number; from: "chord" | "agent" | "stderr"; message: unknown };

async function run(spec: string): Promise<Line[]> {
  const [mode, scenario] = spec.includes(":") ? spec.split(":") : ["plain", spec];
  const started = performance.now();
  const lines: Line[] = [];
  const at = () => Math.round(performance.now() - started);
  const child = new Deno.Command(bun, {
    args: [`${chord}/tests/fixtures/fake_agent/main.ts`, "--scenario", scenario],
    cwd: chord,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  const enc = new TextEncoder();
  let nextId = 0;
  const pending = new Map<number, (m: any) => void>();
  let open = true;
  const send = async (message: Record<string, unknown>) => {
    if (!open) return;
    lines.push({ ms: at(), from: "chord", message });
    await writer.write(enc.encode(JSON.stringify(message) + "\n"));
  };
  const ask = (method: string, params: unknown) => {
    const id = nextId++;
    const answer = new Promise<any>((r) => pending.set(id, r));
    send({ jsonrpc: "2.0", id, method, params });
    return answer;
  };
  let sessionId = "";
  let cancelled = false;
  const onMessage = async (m: any) => {
    lines.push({ ms: at(), from: "agent", message: m });
    if ("id" in m && ("result" in m || "error" in m)) {
      pending.get(m.id)?.(m);
      pending.delete(m.id);
    } else if (m.method === "session/request_permission") {
      await send({
        jsonrpc: "2.0",
        id: m.id,
        result: { outcome: { outcome: "selected", optionId: m.params.options[0].optionId } },
      });
    } else if ("id" in m && m.method) {
      await send({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: "Method not found" } });
    } else if (
      m.method === "session/update" &&
      m.params.update.sessionUpdate === "agent_message_chunk" &&
      mode !== "plain" && !cancelled
    ) {
      cancelled = true;
      await send({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId } });
      if (mode === "close") {
        setTimeout(() => { open = false; writer.close().catch(() => {}); }, 1000);
      }
    }
  };
  (async () => {
    const dec = new TextDecoder();
    let buf = "";
    for await (const chunk of child.stdout) {
      buf += dec.decode(chunk, { stream: true });
      let i;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (line) await onMessage(JSON.parse(line));
      }
    }
    lines.push({ ms: at(), from: "agent", message: { "capture/stdout": "ended" } });
    for (const r of pending.values()) r({ "capture/pending": "stdout ended" });
  })();
  (async () => {
    const dec = new TextDecoder();
    for await (const chunk of child.stderr) {
      lines.push({ ms: at(), from: "stderr", message: dec.decode(chunk) });
    }
  })();
  await ask("initialize", {
    protocolVersion: 1,
    clientCapabilities: {},
    clientInfo: { name: "chord", version: "0.0.1" },
  });
  const opened = await ask("session/new", { cwd: chord, mcpServers: [] });
  sessionId = opened.result?.sessionId ?? "";
  const answer = await Promise.race([
    ask("session/prompt", { sessionId, prompt: [{ type: "text", text: "go" }] }),
    new Promise((r) => setTimeout(() => r({ "capture/timeout": 8000 }), 8000)),
  ]);
  lines.push({ ms: at(), from: "chord", message: { "capture/prompt-settled": answer } });
  // Trailing updates after the answer (the `late` scenario sends one at 20 ms).
  await new Promise((r) => setTimeout(r, 300));
  open = false;
  await writer.close().catch(() => {});
  const status = await child.status;
  lines.push({ ms: at(), from: "chord", message: { "capture/exit": status.code } });
  return lines;
}

for (const spec of wanted) {
  const lines = await run(spec);
  await Deno.writeTextFile(
    `${out}/${spec.replace(":", "-")}.jsonl`,
    lines.map((l) => JSON.stringify(l)).join("\n") + "\n",
  );
  console.log(spec, lines.length);
}
