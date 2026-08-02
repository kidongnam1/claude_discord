import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_BASE = "https://discord.com/api/v10";
const PROJECT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ENV_PATH = process.env.DISCORD_ENV_FILE || path.join(PROJECT_DIR, ".env");
const ROLES = ["claude", "codex", "gemini"];
const SNOWFLAKE = /^\d{17,20}$/;

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

const DISCORD_ENV_KEYS = [
  "WORK_CHANNEL_ID",
  "CHAT_CHANNEL_ID",
  "APPROVER_USER_ID",
  "ORCH_BOT_TOKEN",
  "CLAUDE_BOT_TOKEN",
  "CODEX_BOT_TOKEN",
  "GEMINI_BOT_TOKEN"
];

export function loadConfig(envPath = ENV_PATH) {
  // .env 파일이 있으면 읽고, 시스템 환경변수가 우선한다.
  let fileConfig = {};
  if (fs.existsSync(envPath)) {
    fileConfig = parseEnv(fs.readFileSync(envPath, "utf8"));
  }
  const result = { ...fileConfig };
  for (const key of DISCORD_ENV_KEYS) {
    if (process.env[key]) {
      result[key] = process.env[key];
    }
  }
  return result;
}

function tokenFor(config, role) {
  const key = `${role.toUpperCase()}_BOT_TOKEN`;
  const token = config[key];
  if (!token) throw new Error(`${key} is empty`);
  return token;
}

function orchestratorToken(config) {
  return config.ORCH_BOT_TOKEN || config.CLAUDE_BOT_TOKEN || "";
}

function assertSnowflake(value, name) {
  if (!SNOWFLAKE.test(value)) {
    throw new Error(`${name} must be a Discord snowflake ID`);
  }
}

function resolveAllowedChannel(config, requested, fallbackKey) {
  const target = requested || config[fallbackKey] || "";
  assertSnowflake(target, "channel ID");
  const allowed = new Set(
    [config.WORK_CHANNEL_ID, config.CHAT_CHANNEL_ID].filter(Boolean)
  );
  if (!allowed.has(target)) {
    throw new Error("channel ID is not in the configured Discord allowlist");
  }
  return target;
}

function resolveWorkChannel(config, requested) {
  const target = requested || config.WORK_CHANNEL_ID || "";
  assertSnowflake(target, "work channel ID");
  if (target !== config.WORK_CHANNEL_ID) {
    throw new Error("thread creation is restricted to WORK_CHANNEL_ID");
  }
  return target;
}

async function discordRequest(token, method, endpoint, body) {
  const response = await fetch(`${API_BASE}${endpoint}`, {
    method,
    headers: {
      Authorization: `Bot ${token}`,
      "Content-Type": "application/json",
      "User-Agent": "DiscordBot (https://github.com/kidongnam1/claude_discord, 1.2.0)"
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });

  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { message: text.slice(0, 500) };
    }
  }

  if (!response.ok) {
    const detail = data?.message || `HTTP ${response.status}`;
    throw new Error(`Discord API ${response.status}: ${detail}`);
  }
  return data;
}

function textResult(value) {
  return {
    content: [{ type: "text", text: JSON.stringify(value, null, 2) }]
  };
}

function safeMessage(message) {
  return {
    id: message.id,
    channel_id: message.channel_id,
    author: {
      id: message.author?.id,
      username: message.author?.username,
      bot: Boolean(message.author?.bot)
    },
    content: message.content,
    timestamp: message.timestamp
  };
}

export function createServer(config = loadConfig()) {
  const server = new McpServer({
    name: "gy-discord",
    version: "1.2.0"
  });

  server.registerTool(
    "discord_connection_status",
    {
      description:
        "Validate configured Discord bot identities and default channel access without exposing tokens.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: true }
    },
    async () => {
      const channelId = config.CHAT_CHANNEL_ID || config.WORK_CHANNEL_ID || "";
      if (channelId) assertSnowflake(channelId, "default channel ID");
      const statuses = [];
      for (const role of ROLES) {
        try {
          const token = tokenFor(config, role);
          const user = await discordRequest(token, "GET", "/users/@me");
          let channel = null;
          if (channelId) {
            channel = await discordRequest(token, "GET", `/channels/${channelId}`);
          }
          statuses.push({
            role,
            connected: true,
            bot: { id: user.id, username: user.username },
            channel: channel ? { id: channel.id, name: channel.name, type: channel.type } : null
          });
        } catch (error) {
          statuses.push({ role, connected: false, error: error.message });
        }
      }
      return textResult({
        env_file: ENV_PATH,
        orchestrator_token: config.ORCH_BOT_TOKEN ? "dedicated" : "claude_fallback",
        statuses
      });
    }
  );

  server.registerTool(
    "discord_list_messages",
    {
      description: "Read recent messages from an allowed Discord channel.",
      inputSchema: {
        channelId: z.string().regex(SNOWFLAKE).optional(),
        limit: z.number().int().min(1).max(25).default(10),
        role: z.enum(ROLES).default("codex")
      },
      annotations: { readOnlyHint: true, openWorldHint: true }
    },
    async ({ channelId, limit, role }) => {
      const fallbackKey = config.CHAT_CHANNEL_ID
        ? "CHAT_CHANNEL_ID"
        : "WORK_CHANNEL_ID";
      const target = resolveAllowedChannel(config, channelId, fallbackKey);
      const messages = await discordRequest(
        tokenFor(config, role),
        "GET",
        `/channels/${target}/messages?limit=${limit}`
      );
      return textResult(messages.map(safeMessage));
    }
  );

  server.registerTool(
    "discord_send_message",
    {
      description:
        "Send one Discord message as Claude, Codex, or Gemini. Mentions are always disabled.",
      inputSchema: {
        role: z.enum(ROLES),
        content: z.string().min(1).max(1900),
        channelId: z.string().regex(SNOWFLAKE).optional()
      },
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true
      }
    },
    async ({ role, content, channelId }) => {
      const fallbackKey = config.CHAT_CHANNEL_ID
        ? "CHAT_CHANNEL_ID"
        : "WORK_CHANNEL_ID";
      const target = resolveAllowedChannel(config, channelId, fallbackKey);
      const message = await discordRequest(
        tokenFor(config, role),
        "POST",
        `/channels/${target}/messages`,
        { content, allowed_mentions: { parse: [] } }
      );
      return textResult(safeMessage(message));
    }
  );

  server.registerTool(
    "discord_create_thread",
    {
      description:
        "Create one public Discord thread in the configured work channel. Uses the dedicated orchestrator token or the Claude bot as a safe fallback.",
      inputSchema: {
        name: z.string().min(1).max(90),
        channelId: z.string().regex(SNOWFLAKE).optional()
      },
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true
      }
    },
    async ({ name, channelId }) => {
      const target = resolveWorkChannel(config, channelId);
      const token = orchestratorToken(config);
      if (!token) throw new Error("ORCH_BOT_TOKEN and CLAUDE_BOT_TOKEN are empty");
      const thread = await discordRequest(token, "POST", `/channels/${target}/threads`, {
        name,
        type: 11,
        auto_archive_duration: 1440
      });

      // ── 워커 봇 3개를 스레드에 자동 추가 ──
      // 워커 봇이 스레드에 참여해야 메시지를 게시할 수 있다 (Missing Access 50001 방지).
      // ORCH 봇이 Administrator 권한이 있어야 워커 봇을 추가할 수 있다.
      const workerBotIds = [
        config.CLAUDE_BOT_TOKEN ? "1531522623597707362" : null,
        config.CODEX_BOT_TOKEN ? "1531485839035469905" : null,
        config.GEMINI_BOT_TOKEN ? "1531486384257368280" : null
      ].filter(Boolean);

      const addedWorkers = [];
      for (const workerId of workerBotIds) {
        try {
          await discordRequest(token, "PUT", `/channels/${thread.id}/thread-members/${workerId}`, {
            user_id: workerId
          });
          addedWorkers.push(workerId);
        } catch (e) {
          // 워커 추가 실패는 스레드 생성 성공을 무효화하지 않는다
        }
      }

      return textResult({
        id: thread.id,
        name: thread.name,
        parent_id: thread.parent_id,
        type: thread.type,
        workers_added: addedWorkers.length
      });
    }
  );

  // ── 권한 관리 도구: 워커 봇 역할에 Send Messages in Threads 권한 부여 ──
  server.registerTool(
    "discord_update_role_permissions",
    {
      description:
        "Update a Discord guild role's permissions. Requires the orchestrator bot to have Manage Roles (0x10000000) or Administrator (0x8) permission. Use to grant Send Messages in Threads (0x40000) to worker bot roles.",
      inputSchema: {
        roleId: z.string().regex(SNOWFLAKE),
        addPermissions: z.string().optional().describe("Bitfield string of permissions to add (OR with current)"),
        removePermissions: z.string().optional().describe("Bitfield string of permissions to remove (AND NOT)")
      },
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: true
      }
    },
    async ({ roleId, addPermissions, removePermissions }) => {
      const token = orchestratorToken(config);
      if (!token) throw new Error("ORCH_BOT_TOKEN and CLAUDE_BOT_TOKEN are empty");

      // Get guild ID from work channel
      const channel = await discordRequest(token, "GET", `/channels/${config.WORK_CHANNEL_ID}`);
      const guildId = channel.guild_id;
      if (!guildId) throw new Error("Could not determine guild ID from work channel");

      // Get current role
      const roles = await discordRequest(token, "GET", `/guilds/${guildId}/roles`);
      const role = roles.find(r => r.id === roleId);
      if (!role) throw new Error(`Role ${roleId} not found in guild ${guildId}`);

      let currentPerms = BigInt(role.permissions);
      if (addPermissions) currentPerms = currentPerms | BigInt(addPermissions);
      if (removePermissions) currentPerms = currentPerms & ~BigInt(removePermissions);

      const updated = await discordRequest(token, "PATCH", `/guilds/${guildId}/roles/${roleId}`, {
        permissions: currentPerms.toString()
      });

      return textResult({
        roleId: updated.id,
        roleName: updated.name,
        previousPermissions: role.permissions,
        newPermissions: updated.permissions,
        added: addPermissions || "none",
        removed: removePermissions || "none"
      });
    }
  );

  // ── 권한 관리 도구: 길드 역할 목록 조회 ──
  server.registerTool(
    "discord_list_roles",
    {
      description:
        "List all roles in the Discord guild with their permissions. Useful for finding worker bot role IDs before updating permissions.",
      inputSchema: {},
      annotations: {
        readOnlyHint: true,
        openWorldHint: true
      }
    },
    async () => {
      const token = orchestratorToken(config);
      if (!token) throw new Error("ORCH_BOT_TOKEN and CLAUDE_BOT_TOKEN are empty");

      const channel = await discordRequest(token, "GET", `/channels/${config.WORK_CHANNEL_ID}`);
      const guildId = channel.guild_id;
      if (!guildId) throw new Error("Could not determine guild ID from work channel");

      const roles = await discordRequest(token, "GET", `/guilds/${guildId}/roles`);
      const SEND_MESSAGES_IN_THREADS = BigInt(0x40000);
      const SEND_MESSAGES = BigInt(0x800);
      const MANAGE_ROLES = BigInt(0x10000000);
      const ADMINISTRATOR = BigInt(0x8);

      const result = roles.map(r => {
        const perms = BigInt(r.permissions);
        return {
          id: r.id,
          name: r.name,
          position: r.position,
          permissions: r.permissions,
          send_messages: Boolean(perms & SEND_MESSAGES),
          send_messages_in_threads: Boolean(perms & SEND_MESSAGES_IN_THREADS),
          manage_roles: Boolean(perms & MANAGE_ROLES),
          administrator: Boolean(perms & ADMINISTRATOR)
        };
      });

      return textResult(result);
    }
  );

  // ── 하네스 워크플로우 상태 조회 ──
  server.registerTool(
    "discord_harness_status",
    {
      description:
        "Get the harness engineering workflow status for a task. Returns stage, scale, retry count, approval gates, and timing.",
      inputSchema: {
        threadId: z.string().regex(SNOWFLAKE).describe("Discord thread ID of the harness task")
      },
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      }
    },
    async ({ threadId }) => {
      const harnessDir = path.join(PROJECT_DIR, ".harness-state");
      const stateFile = path.join(harnessDir, `${threadId}.json`);
      if (!fs.existsSync(stateFile)) {
        return textResult({ error: `No harness task found for thread ${threadId}` });
      }
      const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
      return textResult(state);
    }
  );

  // ── 하네스 워크플로우 모든 작업 목록 ──
  server.registerTool(
    "discord_harness_list",
    {
      description:
        "List all harness engineering workflow tasks with their current stage and status.",
      inputSchema: {},
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      }
    },
    async () => {
      const harnessDir = path.join(PROJECT_DIR, ".harness-state");
      if (!fs.existsSync(harnessDir)) {
        return textResult({ tasks: [] });
      }
      const files = fs.readdirSync(harnessDir).filter(f => f.endsWith(".json"));
      const tasks = files.map(f => {
        const state = JSON.parse(fs.readFileSync(path.join(harnessDir, f), "utf8"));
        return {
          thread_id: state.thread_id,
          task_name: state.task_name,
          stage: state.stage,
          scale: state.scale,
          retry_count: state.retry_count,
          g1_approved: state.g1_approved,
          g3_approved: state.g3_approved,
          g4_completed: state.g4_completed
        };
      });
      return textResult({ tasks });
    }
  );

  return server;
}

async function main() {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(`[gy-discord-mcp] ${error.message}`);
    process.exitCode = 1;
  });
}
