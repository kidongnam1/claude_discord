import fs from "node:fs/promises";
import path from "node:path";

export class JobStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.jobs = new Map();
    this.saveChain = Promise.resolve();
  }

  async load() {
    try {
      const parsed = JSON.parse(await fs.readFile(this.filePath, "utf8"));
      for (const job of parsed.jobs || []) this.jobs.set(job.id, job);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    return this;
  }

  get(id) {
    return this.jobs.get(id);
  }

  list() {
    return [...this.jobs.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async put(job) {
    this.jobs.set(job.id, { ...job, updatedAt: new Date().toISOString() });
    await this.save();
    return this.jobs.get(job.id);
  }

  async patch(id, changes) {
    const current = this.get(id);
    if (!current) throw new Error(`작업을 찾을 수 없습니다: ${id}`);
    return this.put({ ...current, ...changes });
  }

  async save() {
    this.saveChain = this.saveChain.then(async () => {
      const dir = path.dirname(this.filePath);
      await fs.mkdir(dir, { recursive: true });
      const temporary = `${this.filePath}.${process.pid}.tmp`;
      const data = JSON.stringify({ version: 1, jobs: this.list() }, null, 2);
      await fs.writeFile(temporary, `${data}\n`, "utf8");
      await fs.rename(temporary, this.filePath);
    });
    return this.saveChain;
  }
}
