#!/usr/bin/env node
// discord-daily-report.mjs — Discord 데일리 리포트 생성
// #작업 채널의 최근 메시지를 조회해서 요약

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ENV_PATH = path.join(path.dirname(__dirname), ".env");

function parseEnv(text) {
  const result = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const sep = line.indexOf("=");
    if (sep < 1) continue;
    result[line.slice(0, sep).trim()] = line.slice(sep + 1).trim();
  }
  return result;
}

const config = parseEnv(fs.readFileSync(ENV_PATH, "utf8"));
const orchToken = config.ORCH_BOT_TOKEN || config.CLAUDE_BOT_TOKEN;
const workChannel = config.WORK_CHANNEL_ID;
const chatChannel = config.CHAT_CHANNEL_ID;

const now = new Date();
const kstTime = new Date(now.getTime() + (9 * 60 * 60 * 1000));
const dateStr = kstTime.toISOString().slice(0, 10);

// Get recent messages from #작업 channel
const resp = await fetch(`https://discord.com/api/v10/channels/${workChannel}/messages?limit=25`, {
  headers: {
    Authorization: `Bot ${orchToken}`,
    "User-Agent": "DiscordBot (gy, 1.1.0)"
  }
});
const messages = await resp.json();

// Count messages by author
const byAuthor = {};
let threadCount = 0;
for (const msg of messages) {
  const author = msg.author?.username || "unknown";
  byAuthor[author] = (byAuthor[author] || 0) + 1;
  if (msg.thread) threadCount++;
}

// Get recent threads
const threadsResp = await fetch(`https://discord.com/api/v10/channels/${workChannel}/threads/active`, {
  headers: { Authorization: `Bot ${orchToken}` }
});
let activeThreads = [];
try {
  const threadsData = await threadsResp.json();
  activeThreads = threadsData.threads || [];
} catch {}

const report = `[DAILY REPORT] ${dateStr} KST

#작업 채널 최근 활동:
- 최근 메시지: ${messages.length}건
- 활성 스레드: ${activeThreads.length}개

메시지 작성자별:
${Object.entries(byAuthor).map(([author, count]) => `- ${author}: ${count}건`).join("\n")}

${activeThreads.length > 0 ? "활성 스레드:" : ""}
${activeThreads.map(t => `- ${t.name} (id: ${t.id})`).join("\n")}

— Discord 데일리 리포트 자동 생성`;

// Post to #수다 channel
const postResp = await fetch(`https://discord.com/api/v10/channels/${chatChannel}/messages`, {
  method: "POST",
  headers: {
    Authorization: `Bot ${orchToken}`,
    "Content-Type": "application/json",
    "User-Agent": "DiscordBot (https://github.com/kidongnam1/claude_discord, 1.1.0)"
  },
  body: JSON.stringify({ content: report, allowed_mentions: { parse: [] } })
});

const result = await postResp.json();
console.log(`Daily report posted: HTTP ${postResp.status}, message_id=${result.id || "error"}`);
if (postResp.status !== 200) {
  console.error(JSON.stringify(result).slice(0, 200));
  process.exit(1);
}
