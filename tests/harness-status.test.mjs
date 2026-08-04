import assert from "node:assert/strict";
import { mkdtemp, rm, readFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);

// npm test는 프로젝트 루트(cwd)에서 실행되므로, 실제 스크립트를 직접 사용
const PROJECT_ROOT = process.cwd();
const HARNESS_SCRIPT = join(PROJECT_ROOT, "scripts", "harness-status.sh");

// HARNESS_DIR을 Windows 네이티브 경로로 전달하여 MSYS 경로 변환 문제 방지
async function runHarnessAction(harnessDir, action, ...args) {
  try {
    const { stdout, stderr } = await execFileAsync(
      "bash",
      [HARNESS_SCRIPT, action, ...args],
      {
        timeout: 10000,
        cwd: PROJECT_ROOT,
        env: { ...process.env, HARNESS_DIR: harnessDir },
      }
    );
    return { stdout, stderr, code: 0 };
  } catch (e) {
    return { stdout: e.stdout || "", stderr: e.stderr || "", code: e.code || 1 };
  }
}

async function makeTempHarnessDir() {
  const tempRoot = await mkdtemp(join(tmpdir(), "harness-test-"));
  const harnessDir = join(tempRoot, ".harness-state");
  await mkdir(harnessDir, { recursive: true });
  return { tempRoot, harnessDir };
}

test("init creates a valid JSON state file with correct defaults", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    const r = await runHarnessAction(harnessDir, "init", "test-thread-01", "Test task");
    assert.equal(r.code, 0, `init failed: ${r.stderr}`);
    const stateFile = join(harnessDir, "test-thread-01.json");
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
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    assert.equal((await runHarnessAction(harnessDir, "init", "test-thread-02", "Stage test")).code, 0);
    assert.equal((await runHarnessAction(harnessDir, "stage", "test-thread-02", "build")).code, 0);
    const r = await runHarnessAction(harnessDir, "get", "test-thread-02");
    assert.equal(r.code, 0, `get failed: ${r.stderr}`);
    const state = JSON.parse(r.stdout);
    assert.equal(state.stage, "build");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("approve g1 sets g1_approved to true", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    assert.equal((await runHarnessAction(harnessDir, "init", "test-thread-03", "Approve test")).code, 0);
    assert.equal((await runHarnessAction(harnessDir, "approve", "test-thread-03", "g1")).code, 0);
    const r = await runHarnessAction(harnessDir, "get", "test-thread-03");
    assert.equal(r.code, 0);
    const state = JSON.parse(r.stdout);
    assert.equal(state.g1_approved, true);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("scale sets the scale field", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    assert.equal((await runHarnessAction(harnessDir, "init", "test-thread-04", "Scale test")).code, 0);
    assert.equal((await runHarnessAction(harnessDir, "scale", "test-thread-04", "small")).code, 0);
    const r = await runHarnessAction(harnessDir, "get", "test-thread-04");
    assert.equal(r.code, 0);
    const state = JSON.parse(r.stdout);
    assert.equal(state.scale, "small");
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("retry increments retry_count and warns at max", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    assert.equal((await runHarnessAction(harnessDir, "init", "test-thread-05", "Retry test")).code, 0);
    assert.equal((await runHarnessAction(harnessDir, "retry", "test-thread-05")).code, 0);
    assert.equal((await runHarnessAction(harnessDir, "retry", "test-thread-05")).code, 0);
    const r3 = await runHarnessAction(harnessDir, "retry", "test-thread-05");
    assert.equal(r3.code, 2);
    assert.match(r3.stderr, /max retries/);
    const rGet = await runHarnessAction(harnessDir, "get", "test-thread-05");
    const state = JSON.parse(rGet.stdout);
    assert.equal(state.retry_count, 3);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("get without argument does not crash (unbound variable fix)", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    const r = await runHarnessAction(harnessDir, "get");
    assert.doesNotMatch(r.stderr, /unbound variable/);
    assert.match(r.stderr, /harness task not found/);
    assert.equal(r.code, 1);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test("list with no tasks returns info message", async () => {
  const { tempRoot, harnessDir } = await makeTempHarnessDir();
  try {
    const r = await runHarnessAction(harnessDir, "list");
    assert.equal(r.code, 0);
    assert.match(r.stdout, /no harness tasks/);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
});
