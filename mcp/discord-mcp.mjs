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

export function loadConfig(envPath = ENV_PATH) {
  if (!fs.existsSync(envPath)) {
    throw new Error(`Discord environment file not found: ${envPath}`);
  }
  return parseEnv(fs.readFileSync(envPath, "utf8"));
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
      "User-Agent": "DiscordBot (https://github.com/kidongnam1/claude_discord, 1.1.0)"
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
    version: "1.1.0"
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
      return textResult({
        id: thread.id,
        name: thread.name,
        parent_id: thread.parent_id,
        type: thread.type
      });
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
