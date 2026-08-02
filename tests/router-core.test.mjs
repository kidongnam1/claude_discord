import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  buildInvocation,
  chunkDiscord,
  extractCliOutput,
  makeJobId,
  parseEnv,
  redactSecrets,
  resolveAllowedRepo
} from "../router/router-core.mjs";
import { JobStore } from "../router/job-store.mjs";

test("parseEnv는 값을 데이터로만 읽는다", () => {
  const parsed = parseEnv('SAFE=value\nEVIL=$(touch nope)\nQUOTED="hello world"');
  assert.equal(parsed.SAFE, "value");
  assert.equal(parsed.EVIL, "$(touch nope)");
  assert.equal(parsed.QUOTED, "hello world");
});

test("저장소는 정확히 등록된 루트만 허용한다", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "router-repo-"));
  const child = path.join(root, "child");
  await fs.mkdir(child);
  assert.equal(resolveAllowedRepo(root, [root], root), path.resolve(root));
  assert.throws(() => resolveAllowedRepo(child, [root], root), /허용 목록/);
  await fs.rm(root, { recursive: true, force: true });
});

test("Codex 읽기와 쓰기 샌드박스를 분리한다", () => {
  const read = buildInvocation({ agent: "codex", mode: "read", prompt: "검토", repo: process.cwd() });
  const write = buildInvocation({ agent: "codex", mode: "write", prompt: "수정", repo: process.cwd() });
  assert.equal(read.args[read.args.indexOf("--sandbox") + 1], "read-only");
  assert.equal(write.args[write.args.indexOf("--sandbox") + 1], "workspace-write");
  assert.equal(read.args.at(-1), "검토");
});

test("Antigravity는 plan과 accept-edits를 분리한다", () => {
  const read = buildInvocation({ agent: "agy", mode: "read", prompt: "검토", repo: process.cwd() });
  const write = buildInvocation({ agent: "agy", mode: "write", prompt: "수정", repo: process.cwd() });
  assert.equal(read.args[read.args.indexOf("--mode") + 1], "plan");
  assert.equal(write.args[write.args.indexOf("--mode") + 1], "accept-edits");
});

test("Hermes 읽기 모드는 로컬 변경 도구를 제공하지 않는다", () => {
  const read = buildInvocation({ agent: "hermes", mode: "read", prompt: "분석", repo: process.cwd() });
  assert.deepEqual(read.args.slice(0, 3), ["--safe-mode", "-t", "web,vision"]);
  assert.equal(read.args.includes("--yolo"), false);
});

test("Discord 메시지를 제한 길이 안에서 나눈다", () => {
  const chunks = chunkDiscord("가".repeat(4300), 1900);
  assert.equal(chunks.length, 3);
  assert.ok(chunks.every((chunk) => chunk.length <= 1900));
});

test("CLI 출력의 환경변수 비밀값을 가린다", () => {
  assert.equal(redactSecrets("token=abcdefgh1234", ["abcdefgh1234"]), "token=[REDACTED]");
  assert.equal(redactSecrets("짧은 값 abc", ["abc"]), "짧은 값 abc");
});

test("Codex JSONL에서 최종 답변만 추출한다", () => {
  const stdout = [
    JSON.stringify({ type: "thread.started", thread_id: "abc" }),
    JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: "검토 완료" } })
  ].join("\n");
  assert.equal(extractCliOutput("codex", stdout, ""), "검토 완료");
});

test("작업 ID와 작업 상태를 디스크에 보존한다", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "router-store-"));
  const file = path.join(root, "jobs.json");
  const id = makeJobId(new Date("2026-08-02T10:00:00Z"), () => 0.5);
  const store = await new JobStore(file).load();
  await store.put({ id, status: "queued", createdAt: "2026-08-02T10:00:00Z" });
  await store.patch(id, { status: "completed" });
  const restored = await new JobStore(file).load();
  assert.equal(restored.get(id).status, "completed");
  await fs.rm(root, { recursive: true, force: true });
});
