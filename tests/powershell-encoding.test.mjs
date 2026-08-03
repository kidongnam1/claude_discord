import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scriptsDir = path.join(projectDir, "scripts");

test("한글 PowerShell 스크립트는 Windows PowerShell 5.1용 UTF-8 BOM을 가진다", () => {
  const failures = [];
  for (const name of fs.readdirSync(scriptsDir).filter((item) => item.endsWith(".ps1"))) {
    const bytes = fs.readFileSync(path.join(scriptsDir, name));
    const hasNonAscii = bytes.some((value) => value > 0x7f);
    const hasUtf8Bom = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf;
    if (hasNonAscii && !hasUtf8Bom) failures.push(name);
  }
  assert.deepEqual(failures, []);
});
