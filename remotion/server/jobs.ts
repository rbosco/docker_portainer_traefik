import { randomUUID } from "node:crypto";

export type JobStatus = "queued" | "rendering" | "uploading" | "done" | "error";

export interface Job {
  id: string;
  status: JobStatus;
  compositionId: string;
  url?: string;
  error?: string;
  createdAt: string;
  updatedAt: string;
}

const jobs = new Map<string, Job>();

export function createJob(compositionId: string): Job {
  const now = new Date().toISOString();
  const job: Job = {
    id: randomUUID(),
    status: "queued",
    compositionId,
    createdAt: now,
    updatedAt: now,
  };
  jobs.set(job.id, job);
  return job;
}

export function updateJob(id: string, patch: Partial<Job>): Job | undefined {
  const current = jobs.get(id);
  if (!current) return undefined;
  const next: Job = { ...current, ...patch, updatedAt: new Date().toISOString() };
  jobs.set(id, next);
  return next;
}

export function getJob(id: string): Job | undefined {
  return jobs.get(id);
}
