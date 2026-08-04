import fs from "node:fs";
import fsPromises from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  Client,
  GatewayIntentBits,
  REST,
  Routes,
  SlashCommandBuilder
} from "discord.js";
import {
  AGENTS,
  buildInvocation,
  chunkDiscord,
  extractCliOutput,
  makeJobId,
  parseEnv,
  redactSecrets,
  resolveAllowedRepo,
  splitList
} from "./router-core.mjs";
import { JobStore } from "./job-store.mjs";

const PROJECT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const STATE_DIR = path.join(PROJECT_DIR, ".discord-router");
const SNOWFLAKE = /^\d{17,20}$/;
const ENV_KEYS = [
  "ROUTER_BOT_TOKEN",
  "ROUTER_GUILD_ID",
  "ROUTER_ALLOWED_USER_IDS",
  "ROUTER_ALLOWED_CHANNEL_IDS",
  "ROUTER_ALLOWED_REPOS",
  "ROUTER_DEFAULT_REPO",
  "ROUTER_TIMEOUT_MINUTES",
  "CODEX_COMMAND",
  "AGY_COMMAND",
  "HERMES_COMMAND",
  "APPROVER_USER_ID",
  "WORK_CHANNEL_ID",
  "CHAT_CHANNEL_ID"
];

export function loadRouterConfig(envPath = process.env.DISCORD_ENV_FILE || path.join(PROJECT_DIR, ".env")) {
  let fileConfig = {};
  if (fs.existsSync(envPath)) fileConfig = parseEnv(fs.readFileSync(envPath, "utf8"));
  const values = { ...fileConfig };
  for (const key of ENV_KEYS) if (process.env[key]) values[key] = process.env[key];

  const approverId = values.APPROVER_USER_ID || "";
  const allowedUsers = new Set(splitList(values.ROUTER_ALLOWED_USER_IDS || approverId));
  const allowedChannels = new Set(
    splitList(values.ROUTER_ALLOWED_CHANNEL_IDS || [values.WORK_CHANNEL_ID, values.CHAT_CHANNEL_ID].filter(Boolean).join(","))
  );
  const allowedRepos = splitList(values.ROUTER_ALLOWED_REPOS || PROJECT_DIR).map((item) => path.resolve(item));
  const defaultRepo = path.resolve(values.ROUTER_DEFAULT_REPO || allowedRepos[0] || PROJECT_DIR);
  const timeoutMinutes = Math.max(1, Math.min(180, Number(values.ROUTER_TIMEOUT_MINUTES || 30)));
  const secretValues = [...new Set(
    [...Object.entries(values), ...Object.entries(process.env)]
      .filter(([key, value]) => /(?:TOKEN|KEY|SECRET|PASSWORD)$/i.test(key) && typeof value === "string")
      .map(([, value]) => value)
      .filter((value) => value.length >= 8)
  )];

  return {
    token: values.ROUTER_BOT_TOKEN || "",
    guildId: values.ROUTER_GUILD_ID || "",
    approverId,
    allowedUsers,
    allowedChannels,
    allowedRepos,
    defaultRepo,
    timeoutMs: timeoutMinutes * 60_000,
    secretValues,
    commands: {
      codex: values.CODEX_COMMAND || "",
      agy: values.AGY_COMMAND || "",
      hermes: values.HERMES_COMMAND || ""
    },
    envPath
  };
}

export function commandDefinitions() {
  const agentCommands = AGENTS.map((agent) =>
    new SlashCommandBuilder()
      .setName(agent)
      .setDescription(`${agent}에게 작업을 요청합니다.`)
      .addStringOption((option) => option.setName("prompt").setDescription("작업 내용").setRequired(true))
      .addStringOption((option) =>
        option
          .setName("mode")
          .setDescription("read는 자동, write는 승인 후 실행")
          .addChoices({ name: "읽기/분석", value: "read" }, { name: "파일 수정", value: "write" })
      )
      .addStringOption((option) => option.setName("repo").setDescription("허용 목록에 등록된 저장소 절대 경로"))
  );
  return [
    ...agentCommands,
    new SlashCommandBuilder()
      .setName("approve")
      .setDescription("대기 중인 쓰기 작업을 승인합니다.")
      .addStringOption((option) => option.setName("job").setDescription("작업 ID").setRequired(true)),
    new SlashCommandBuilder()
      .setName("status")
      .setDescription("작업 상태를 확인합니다.")
      .addStringOption((option) => option.setName("job").setDescription("비우면 최근 작업 표시")),
    new SlashCommandBuilder()
      .setName("stop")
      .setDescription("실행 중인 작업을 중지합니다.")
      .addStringOption((option) => option.setName("job").setDescription("작업 ID").setRequired(true))
  ].map((command) => command.toJSON());
}

function validateConfig(config, requireToken = true) {
  const missing = [];
  if (requireToken && !config.token) missing.push("ROUTER_BOT_TOKEN");
  if (!config.guildId) missing.push("ROUTER_GUILD_ID");
  if (!config.approverId) missing.push("APPROVER_USER_ID");
  if (!config.allowedUsers.size) missing.push("ROUTER_ALLOWED_USER_IDS");
  if (!config.allowedChannels.size) missing.push("ROUTER_ALLOWED_CHANNEL_IDS");
  if (missing.length) throw new Error(`필수 설정이 없습니다: ${missing.join(", ")}`);
  for (const [name, ids] of [
    ["ROUTER_GUILD_ID", [config.guildId]],
    ["APPROVER_USER_ID", [config.approverId]],
    ["ROUTER_ALLOWED_USER_IDS", [...config.allowedUsers]],
    ["ROUTER_ALLOWED_CHANNEL_IDS", [...config.allowedChannels]]
  ]) {
    if (ids.some((id) => !SNOWFLAKE.test(id))) throw new Error(`${name}에 잘못된 Discord ID가 있습니다.`);
  }
  resolveAllowedRepo(config.defaultRepo, config.allowedRepos, config.defaultRepo);
}

async function appendLog(level, message, details = {}) {
  await fsPromises.mkdir(STATE_DIR, { recursive: true });
  const record = JSON.stringify({ time: new Date().toISOString(), level, message, ...details });
  console.log(record);
  await fsPromises.appendFile(path.join(STATE_DIR, "router.log"), `${record}\n`, "utf8");
}

function formatJob(job) {
  return [
    `작업: ${job.id}`,
    `AI/모드: ${job.agent} / ${job.mode}`,
    `상태: ${job.status}`,
    `저장소: ${job.repo}`,
    job.exitCode === undefined || job.exitCode === null ? null : `종료 코드: ${job.exitCode}`,
    job.error ? `오류: ${job.error}` : null
  ].filter(Boolean).join("\n");
}

function isAllowedChannel(interaction, allowedChannels) {
  return allowedChannels.has(interaction.channelId) ||
    (interaction.channel?.isThread?.() && allowedChannels.has(interaction.channel.parentId));
}

function terminateProcess(child) {
  if (!child || child.killed) return;
  if (process.platform === "win32" && child.pid) {
    const killer = spawn("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], {
      windowsHide: true,
      stdio: "ignore"
    });
    killer.unref();
  } else {
    child.kill("SIGTERM");
  }
}

export async function startRouter(config = loadRouterConfig()) {
  validateConfig(config, true);
  const store = await new JobStore(path.join(STATE_DIR, "jobs.json")).load();
  const active = new Map();
  const activeChannels = new Map();
  const client = new Client({ intents: [GatewayIntentBits.Guilds] });

  async function postResult(channel, job, output) {
    const header = `**${job.agent.toUpperCase()} 작업 ${job.status}** · \`${job.id}\``;
    for (const [index, chunk] of chunkDiscord(output).entries()) {
      const prefix = index === 0 ? `${header}\n\`\`\`text\n` : "```text\n";
      await channel.send({ content: `${prefix}${chunk.replace(/```/g, "` ` `")}\n\`\`\``, allowedMentions: { parse: [] } });
    }
  }

  async function runJob(job, channel) {
    const invocation = buildInvocation({
      agent: job.agent,
      mode: job.mode,
      prompt: job.prompt,
      repo: job.repo,
      commands: config.commands
    });
    await store.patch(job.id, { status: "running", startedAt: new Date().toISOString() });
    await appendLog("info", "job_started", { jobId: job.id, agent: job.agent, mode: job.mode, repo: job.repo });

    let stdout = "";
    let stderr = "";
    const child = spawn(invocation.command, invocation.args, {
      cwd: invocation.cwd,
      env: { ...process.env, NO_COLOR: "1" },
      windowsHide: true,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"]
    });
    active.set(job.id, child);
    const timeout = setTimeout(() => terminateProcess(child), config.timeoutMs);
    child.stdout.on("data", (data) => { stdout = (stdout + data.toString("utf8")).slice(-1_000_000); });
    child.stderr.on("data", (data) => { stderr = (stderr + data.toString("utf8")).slice(-1_000_000); });

    const result = await new Promise((resolve) => {
      child.once("error", (error) => resolve({ code: null, error }));
      child.once("close", (code, signal) => resolve({ code, signal }));
    });
    clearTimeout(timeout);
    active.delete(job.id);

    const stopped = store.get(job.id)?.status === "stopping";
    const status = stopped ? "stopped" : result.code === 0 ? "completed" : "failed";
    const error = result.error?.message || (result.signal ? `signal=${result.signal}` : "");
    const output = redactSecrets(extractCliOutput(job.agent, stdout, stderr), config.secretValues);
    const completed = await store.patch(job.id, {
      status,
      exitCode: result.code,
      error,
      output,
      completedAt: new Date().toISOString()
    });
    await appendLog(status === "completed" ? "info" : "error", "job_finished", {
      jobId: job.id,
      status,
      exitCode: result.code,
      error
    });
    await postResult(channel, completed, output);
  }

  async function launchJob(job, channel) {
    activeChannels.set(job.channelId, job.id);
    try {
      await runJob(job, channel);
    } catch (error) {
      const current = store.get(job.id);
      if (!current || !["completed", "failed", "stopped"].includes(current.status)) {
        await store.patch(job.id, { status: "failed", error: error.message, completedAt: new Date().toISOString() });
      }
      await appendLog("error", "job_crashed", { jobId: job.id, error: error.stack || error.message });
      try {
        await channel.send({ content: `작업 \`${job.id}\` 실패: ${error.message}`, allowedMentions: { parse: [] } });
      } catch (notifyError) {
        await appendLog("error", "job_error_notification_failed", { jobId: job.id, error: notifyError.message });
      }
    } finally {
      if (activeChannels.get(job.channelId) === job.id) activeChannels.delete(job.channelId);
      active.delete(job.id);
    }
  }

  client.on("interactionCreate", async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    let reservedJobId = "";
    let reservedChannelId = "";
    try {
      if (!config.allowedUsers.has(interaction.user.id)) throw new Error("허용된 사용자가 아닙니다.");
      if (!isAllowedChannel(interaction, config.allowedChannels)) throw new Error("허용된 채널이 아닙니다.");

      if (AGENTS.includes(interaction.commandName)) {
        await interaction.deferReply({ ephemeral: true });
        if (activeChannels.has(interaction.channelId)) {
          throw new Error(`이 채널에서 ${activeChannels.get(interaction.channelId)} 작업이 이미 실행 중입니다.`);
        }
        const mode = interaction.options.getString("mode") || "read";
        const repo = resolveAllowedRepo(
          interaction.options.getString("repo"),
          config.allowedRepos,
          config.defaultRepo
        );
        const jobId = makeJobId();
        if (mode === "read") {
          reservedJobId = jobId;
          reservedChannelId = interaction.channelId;
          activeChannels.set(reservedChannelId, reservedJobId);
        }
        const job = await store.put({
          id: jobId,
          agent: interaction.commandName,
          mode,
          prompt: interaction.options.getString("prompt", true),
          repo,
          userId: interaction.user.id,
          channelId: interaction.channelId,
          status: mode === "write" ? "pending_approval" : "queued",
          createdAt: new Date().toISOString()
        });
        if (mode === "write") {
          await interaction.editReply(`${formatJob(job)}\n\n승인 명령: \`/approve job:${job.id}\``);
          return;
        }
        await interaction.editReply(`${formatJob(job)}\n\n읽기 전용으로 실행을 시작합니다.`);
        void launchJob(job, interaction.channel);
        return;
      }

      if (interaction.commandName === "approve") {
        if (interaction.user.id !== config.approverId) throw new Error("승인 권한자가 아닙니다.");
        const job = store.get(interaction.options.getString("job", true));
        if (!job || job.status !== "pending_approval") throw new Error("승인 대기 중인 작업이 아닙니다.");
        if (activeChannels.has(job.channelId)) throw new Error("해당 채널에 실행 중인 작업이 있습니다.");
        reservedJobId = job.id;
        reservedChannelId = job.channelId;
        activeChannels.set(reservedChannelId, reservedJobId);
        const targetChannel = await client.channels.fetch(job.channelId);
        if (!targetChannel?.isTextBased()) throw new Error("원래 작업 채널에 메시지를 보낼 수 없습니다.");
        await interaction.reply({ content: `승인 완료: \`${job.id}\` — 실행을 시작합니다.`, ephemeral: true });
        void launchJob(job, targetChannel);
        return;
      }

      if (interaction.commandName === "status") {
        const id = interaction.options.getString("job");
        const content = id
          ? formatJob(store.get(id) || { id, agent: "-", mode: "-", status: "not_found", repo: "-" })
          : store.list().slice(0, 5).map(formatJob).join("\n\n") || "저장된 작업이 없습니다.";
        await interaction.reply({ content, ephemeral: true, allowedMentions: { parse: [] } });
        return;
      }

      if (interaction.commandName === "stop") {
        const id = interaction.options.getString("job", true);
        const child = active.get(id);
        if (!child) throw new Error("현재 실행 중인 작업이 아닙니다.");
        await store.patch(id, { status: "stopping", stoppedBy: interaction.user.id });
        terminateProcess(child);
        await interaction.reply({ content: `중지 요청 완료: \`${id}\``, ephemeral: true });
      }
    } catch (error) {
      if (reservedChannelId && activeChannels.get(reservedChannelId) === reservedJobId && !active.has(reservedJobId)) {
        activeChannels.delete(reservedChannelId);
      }
      await appendLog("error", "interaction_error", { command: interaction.commandName, error: error.stack || error.message });
      const payload = { content: `실행할 수 없습니다: ${error.message}`, ephemeral: true, allowedMentions: { parse: [] } };
      if (interaction.deferred || interaction.replied) await interaction.editReply(payload);
      else await interaction.reply(payload);
    }
  });

  client.once("ready", () => {
    void (async () => {
      const rest = new REST({ version: "10" }).setToken(config.token);
      await rest.put(Routes.applicationGuildCommands(client.user.id, config.guildId), { body: commandDefinitions() });
      await appendLog("info", "router_ready", { bot: client.user.tag, guildId: config.guildId });
    })().catch(async (error) => {
      await appendLog("error", "command_registration_failed", { error: error.stack || error.message });
      client.destroy();
      process.exitCode = 1;
    });
  });

  const shutdown = async (signal) => {
    await appendLog("info", "router_shutdown", { signal });
    for (const child of active.values()) terminateProcess(child);
    client.destroy();
    process.exit(0);
  };
  process.once("SIGINT", () => void shutdown("SIGINT"));
  process.once("SIGTERM", () => void shutdown("SIGTERM"));
  await client.login(config.token);
  return client;
}

if (process.argv.includes("--check")) {
  try {
    const config = loadRouterConfig();
    validateConfig(config, false);
    console.log(JSON.stringify({
      ok: true,
      tokenConfigured: Boolean(config.token),
      guildConfigured: Boolean(config.guildId),
      allowedUsers: config.allowedUsers.size,
      allowedChannels: config.allowedChannels.size,
      allowedRepos: config.allowedRepos,
      commands: commandDefinitions().map((item) => item.name)
    }, null, 2));
  } catch (error) {
    console.error(`[ERROR] ${error.message}`);
    process.exitCode = 1;
  }
} else if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  startRouter().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}
