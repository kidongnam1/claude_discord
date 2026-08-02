import assert from "node:assert/strict";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);

const SCRIPT_DIR = new URL("../scripts/", import.meta.url).pathname.replace(
  /^\/([a-zA-Z]:)/,
  "$1"
);
const HARNESS_SCRIPT = join(SCRIPT_DIR, "harness-status.sh");

function toWslPath(windowsPath) {
  return windowsPath
    .replace(/^([a-zA-Z]):/, (_, drive) => `/mnt/${drive.toLowerCase()}`)
    .replaceAll("\\", "/");
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

const HARNESS_SCRIPT_BASH = toWslPath(HARNESS_SCRIPT);

// Helper: WSL 경로로 변환한 임시 HARNESS_DIR에 상태를 격리한다.
async function runHarnessAction(tempRoot, action, ...args) {
  // Windows 임시 경로를 WSL /mnt 경로로 변환한다.
  const harnessDir = join(tempRoot, ".harness-state");
  try {
    const { stdout, stderr } = await execFileAsync(
      "bash",
      [
        "-lc",
        `HARNESS_DIR=${shellQuote(toWslPath(harnessDir))} ${[
          HARNESS_SCRIPT_BASH,
          action,
          ...args,
        ].map(shellQuote).join(" ")}`,
      ],
      {
        timeout: 10000,
        cwd: join(SCRIPT_DIR, ".."),
        env: process.env,
      }
    );
    return { stdout, stderr, code: 0 };
  } catch (e) {
    return { stdout: e.stdout || "", stderr: e.stderr || "", code: e.code || 1 };
  }
}

async function setupTempProject() {
  return mkdtemp(join(tmpdir(), "harness-test-"));
}

test("init creates a valid JSON state file with correct defaults", async () => {
  const tempRoot = await setupTempProject();
  try {
    const r = await runHarnessAction(tempRoot, "init", "test-thread-01", "Test task");
    assert.equal(r.code, 0, `init failed: ${r.stderr}`);
    const stateFile = join(tempRoot, ".harness-state", "test-thread-01.json");
    const raw = await readFile(stateFile, "utf8");
    const state = JSON.parse(raw);

    assert.equal(state.thread_id, "test-thread-01");
    assert.equal(state.task_name, "Test task");
    assert.equal(state.stage, "plan");
    assert.equal(state.scale, "medium");
    assert.equal(state.retry_count, 0);
    assert.equal(state.g1_approved, false);
    assert.equal(state.g4_completed, false);
    assert.ok(state.created_at, "created_at should exist");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("stage updates the stage field correctly", async () => {
  const tempRoot = await setupTempProject();
  try {
    assert.equal((await runHarnessAction(tempRoot, "init", "test-thread-02", "Stage test")).code, 0);
    assert.equal((await runHarnessAction(tempRoot, "stage", "test-thread-02", "build")).code, 0);
    const r = await runHarnessAction(tempRoot, "get", "test-thread-02");
    assert.equal(r.code, 0, `get failed: ${r.stderr}`);
    const state = JSON.parse(r.stdout);
    assert.equal(state.stage, "build");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("approve g1 sets g1_approved to true", async () => {
  const tempRoot = await setupTempProject();
  try {
    assert.equal((await runHarnessAction(tempRoot, "init", "test-thread-03", "Approve test")).code, 0);
    assert.equal((await runHarnessAction(tempRoot, "approve", "test-thread-03", "g1")).code, 0);
    const r = await runHarnessAction(tempRoot, "get", "test-thread-03");
    assert.equal(r.code, 0);
    const state = JSON.parse(r.stdout);
    assert.equal(state.g1_approved, true);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("scale sets the scale field", async () => {
  const tempRoot = await setupTempProject();
  try {
    assert.equal((await runHarnessAction(tempRoot, "init", "test-thread-04", "Scale test")).code, 0);
    assert.equal((await runHarnessAction(tempRoot, "scale", "test-thread-04", "small")).code, 0);
    const r = await runHarnessAction(tempRoot, "get", "test-thread-04");
    assert.equal(r.code, 0);
    const state = JSON.parse(r.stdout);
    assert.equal(state.scale, "small");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("retry increments retry_count and warns at max", async () => {
  const tempRoot = await setupTempProject();
  try {
    assert.equal((await runHarnessAction(tempRoot, "init", "test-thread-05", "Retry test")).code, 0);
    assert.equal((await runHarnessAction(tempRoot, "retry", "test-thread-05")).code, 0);
    assert.equal((await runHarnessAction(tempRoot, "retry", "test-thread-05")).code, 0);
    // 3번째 retry에서 exit code 2 (max_retries 도달)
    const r3 = await runHarnessAction(tempRoot, "retry", "test-thread-05");
    assert.equal(r3.code, 2);
    assert.match(r3.stderr, /max retries/);
    const rGet = await runHarnessAction(tempRoot, "get", "test-thread-05");
    const state = JSON.parse(rGet.stdout);
    assert.equal(state.retry_count, 3);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("get without argument does not crash (unbound variable fix)", async () => {
  const tempRoot = await setupTempProject();
  try {
    const r = await runHarnessAction(tempRoot, "get");
    // unbound variable fix: must NOT crash with "unbound variable"
    assert.doesNotMatch(r.stderr, /unbound variable/);
    // Should be a clean error message instead
    assert.match(r.stderr, /harness task not found/);
    assert.equal(r.code, 1);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("list with no tasks returns info message", async () => {
  const tempRoot = await setupTempProject();
  try {
    const r = await runHarnessAction(tempRoot, "list");
    assert.equal(r.code, 0);
    assert.match(r.stdout, /no harness tasks/);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});
