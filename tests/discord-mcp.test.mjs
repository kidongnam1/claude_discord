import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer, parseEnv } from "../mcp/discord-mcp.mjs";

test("parseEnv reads values without exposing shell semantics", () => {
  const result = parseEnv(`
# comment
WORK_CHANNEL_ID=123456789012345678
CLAUDE_BOT_TOKEN="token.value"
IGNORED_LINE
`);
  assert.equal(result.WORK_CHANNEL_ID, "123456789012345678");
  assert.equal(result.CLAUDE_BOT_TOKEN, "token.value");
  assert.equal(result.IGNORED_LINE, undefined);
});

test("parseEnv trims whitespace and preserves equals in values", () => {
  const result = parseEnv("TOKEN = abc=def==\r\nEMPTY=\r\n");
  assert.equal(result.TOKEN, "abc=def==");
  assert.equal(result.EMPTY, "");
});

test("MCP protocol exposes the six Discord tools", async () => {
  const server = createServer({
    WORK_CHANNEL_ID: "123456789012345678",
    CHAT_CHANNEL_ID: "123456789012345679",
    CLAUDE_BOT_TOKEN: "dummy-claude",
    CODEX_BOT_TOKEN: "dummy-codex",
    GEMINI_BOT_TOKEN: "dummy-gemini"
  });
  const client = new Client({ name: "gy-discord-test", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([
    client.connect(clientTransport),
    server.server.connect(serverTransport)
  ]);

  const result = await client.listTools();
  assert.deepEqual(
    result.tools.map((tool) => tool.name).sort(),
    [
      "discord_connection_status",
      "discord_create_thread",
      "discord_list_messages",
      "discord_list_roles",
      "discord_send_message",
      "discord_update_role_permissions"
    ]
  );

  await client.close();
  await server.close();
});

test("stdio entrypoint starts and completes an MCP handshake", async () => {
  const tempDirectory = await mkdtemp(join(tmpdir(), "gy-discord-mcp-"));
  const envFile = join(tempDirectory, ".env.test");
  await writeFile(
    envFile,
    [
      "WORK_CHANNEL_ID=123456789012345678",
      "CHAT_CHANNEL_ID=123456789012345679",
      "CLAUDE_BOT_TOKEN=dummy-claude",
      "CODEX_BOT_TOKEN=dummy-codex",
      "GEMINI_BOT_TOKEN=dummy-gemini"
    ].join("\n"),
    "utf8"
  );
  const client = new Client({ name: "gy-discord-stdio-test", version: "1.0.0" });
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["mcp/discord-mcp.mjs"],
    cwd: process.cwd(),
    env: {
      ...process.env,
      DISCORD_ENV_FILE: envFile
    }
  });
  try {
    await client.connect(transport);
    const result = await client.listTools();
    assert.equal(result.tools.length, 6);
  } finally {
    await client.close();
    await rm(tempDirectory, { recursive: true, force: true });
  }
});

test("MCP rejects channels outside the configured allowlist before network access", async () => {
  const server = createServer({
    WORK_CHANNEL_ID: "123456789012345678",
    CHAT_CHANNEL_ID: "123456789012345679",
    CLAUDE_BOT_TOKEN: "dummy-claude",
    CODEX_BOT_TOKEN: "dummy-codex",
    GEMINI_BOT_TOKEN: "dummy-gemini"
  });
  const client = new Client({ name: "gy-discord-allowlist-test", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([
    client.connect(clientTransport),
    server.server.connect(serverTransport)
  ]);

  const listResult = await client.callTool({
    name: "discord_list_messages",
    arguments: {
      channelId: "999999999999999999",
      role: "codex",
      limit: 1
    }
  });
  assert.equal(listResult.isError, true);
  assert.match(listResult.content[0].text, /allowlist/);

  const threadResult = await client.callTool({
    name: "discord_create_thread",
    arguments: {
      channelId: "123456789012345679",
      name: "not-allowed"
    }
  });
  assert.equal(threadResult.isError, true);
  assert.match(threadResult.content[0].text, /WORK_CHANNEL_ID/);

  await client.close();
  await server.close();
});
