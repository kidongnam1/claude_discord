import fs from "node:fs";
import path from "node:path";

export const AGENTS = ["codex", "agy", "hermes"];
export const MODES = ["read", "write"];
export const DISCORD_MESSAGE_LIMIT = 1900;

export function parseEnv(text) {
  const result = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    result[key] = value;
  }
  return result;
}

export function splitList(value = "") {
  return value
    .split(/[;,\r\n]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function comparablePath(value) {
  const normalized = path.resolve(value).replace(/[\\/]+$/, "");
  return process.platform === "win32" ? normalized.toLowerCase() : normalized;
}

export function resolveAllowedRepo(requested, allowedRepos, defaultRepo) {
  const roots = allowedRepos.map((item) => path.resolve(item));
  const target = path.resolve(requested || defaultRepo || roots[0] || "");
  const match = roots.find((root) => comparablePath(root) === comparablePath(target));
  if (!match) {
    throw new Error("요청한 저장소가 ROUTER_ALLOWED_REPOS 허용 목록에 없습니다.");
  }
  if (!fs.existsSync(match) || !fs.statSync(match).isDirectory()) {
    throw new Error(`저장소 폴더가 없습니다: ${match}`);
  }
  return match;
}

export function makeJobId(now = new Date(), random = Math.random) {
  const stamp = now.toISOString().replace(/[-:TZ.]/g, "").slice(0, 14);
  return `${stamp}-${random().toString(36).slice(2, 7)}`;
}

export function chunkDiscord(text, limit = DISCORD_MESSAGE_LIMIT) {
  const source = String(text || "(출력 없음)");
  const chunks = [];
  let remaining = source;
  while (remaining.length > limit) {
    let cut = remaining.lastIndexOf("\n", limit);
    if (cut < Math.floor(limit * 0.5)) cut = limit;
    chunks.push(remaining.slice(0, cut));
    remaining = remaining.slice(cut).replace(/^\n/, "");
  }
  chunks.push(remaining);
  return chunks;
}

export function buildInvocation({ agent, mode, prompt, repo, commands = {} }) {
  if (!AGENTS.includes(agent)) throw new Error(`지원하지 않는 AI: ${agent}`);
  if (!MODES.includes(mode)) throw new Error(`지원하지 않는 모드: ${mode}`);
  if (!String(prompt || "").trim()) throw new Error("프롬프트가 비어 있습니다.");

  if (agent === "codex") {
    const defaultCodexScript = process.platform === "win32"
      ? path.join(process.env.APPDATA || "", "npm", "node_modules", "@openai", "codex", "bin", "codex.js")
      : "";
    const command = commands.codex || (process.platform === "win32" ? process.execPath : "codex");
    const prefix = !commands.codex && defaultCodexScript ? [defaultCodexScript] : [];
    return {
      command,
      args: [
        ...prefix,
        "exec",
        "--json",
        "--color",
        "never",
        "--sandbox",
        mode === "read" ? "read-only" : "workspace-write",
        "-C",
        repo,
        prompt
      ],
      cwd: repo
    };
  }

  if (agent === "agy") {
    return {
      command: commands.agy || "agy",
      args: [
        "--print",
        prompt,
        "--output-format",
        "stream-json",
        "--project",
        repo,
        "--mode",
        mode === "read" ? "plan" : "accept-edits",
        "--sandbox"
      ],
      cwd: repo
    };
  }

  const hermesReadPrompt = [
    "읽기 전용 분석 요청입니다.",
    "로컬 파일, 터미널, 브라우저 자동화, 외부 메시지 전송을 사용하지 마세요.",
    "제공된 질문만 분석하고, 저장소 파일 확인이 필요하면 필요한 파일을 명시하세요.",
    "",
    prompt
  ].join("\n");
  const hermesWritePrompt = [
    `작업 루트는 ${repo} 입니다. 이 루트 밖의 파일을 변경하지 마세요.`,
    "삭제, 배포, 결제, 외부 메시지 전송은 별도 사용자 승인이 없으면 수행하지 마세요.",
    "",
    prompt
  ].join("\n");
  const defaultHermes = process.platform === "win32"
    ? path.join(process.env.LOCALAPPDATA || "", "hermes", "hermes-agent", "venv", "Scripts", "hermes.exe")
    : "hermes";
  return {
    command: commands.hermes || defaultHermes,
    args: mode === "read"
      ? ["-t", "web,vision", "-z", hermesReadPrompt]
      : ["-z", hermesWritePrompt],
    cwd: repo
  };
}

export function summarizeOutput(stdout, stderr, maxLength = 12000) {
  const combined = [stdout, stderr && `\n[stderr]\n${stderr}`].filter(Boolean).join("").trim();
  if (!combined) return "(출력 없음)";
  return combined.length <= maxLength ? combined : `…(앞부분 생략)…\n${combined.slice(-maxLength)}`;
}

export function extractCliOutput(agent, stdout, stderr) {
  if (agent === "hermes") return summarizeOutput(stdout, stderr);
  const answers = [];
  for (const line of String(stdout || "").split(/\r?\n/)) {
    if (!line.trim().startsWith("{")) continue;
    try {
      const event = JSON.parse(line);
      if (event.type === "item.completed" && event.item?.type === "agent_message" && event.item.text) {
        answers.push(event.item.text);
      } else if (event.type === "result" && typeof event.result === "string") {
        answers.push(event.result);
      } else if (event.type === "assistant" && typeof event.message?.content === "string") {
        answers.push(event.message.content);
      } else if (typeof event.response === "string") {
        answers.push(event.response);
      }
    } catch {
      // JSONL이 아닌 일반 출력은 아래 폴백에서 그대로 보존한다.
    }
  }
  if (!answers.length) return summarizeOutput(stdout, stderr);
  return summarizeOutput(answers.join("\n\n"), stderr);
}

export function redactSecrets(text, secrets = []) {
  let result = String(text || "");
  for (const secret of secrets.filter((value) => typeof value === "string" && value.length >= 8)) {
    result = result.split(secret).join("[REDACTED]");
  }
  return result;
}
