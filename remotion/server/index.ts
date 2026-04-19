import express, { type Request, type Response } from "express";
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";

import { createJob, getJob, updateJob } from "./jobs";
import { uploadFile, s3Config } from "./s3";

const PORT = Number(process.env.PORT ?? 3000);
const ENTRY = join(process.cwd(), "src", "index.ts");

const renderRequestSchema = z.object({
  compositionId: z.string().min(1),
  inputProps: z.record(z.unknown()).optional(),
  codec: z.enum(["h264", "h265", "vp8", "vp9"]).optional().default("h264"),
});

let bundleLocationPromise: Promise<string> | null = null;
function getBundleLocation(): Promise<string> {
  if (!bundleLocationPromise) {
    console.log("[render] Bundling project (primeiro render, pode demorar)...");
    bundleLocationPromise = bundle({ entryPoint: ENTRY }).then((loc) => {
      console.log(`[render] Bundle pronto em ${loc}`);
      return loc;
    });
  }
  return bundleLocationPromise;
}

async function runRender(jobId: string, compositionId: string, inputProps: Record<string, unknown>, codec: "h264" | "h265" | "vp8" | "vp9") {
  const tmpDir = mkdtempSync(join(tmpdir(), `remotion-${jobId}-`));
  const outPath = join(tmpDir, `${jobId}.mp4`);
  try {
    updateJob(jobId, { status: "rendering" });
    const serveUrl = await getBundleLocation();
    const composition = await selectComposition({ serveUrl, id: compositionId, inputProps });

    await renderMedia({
      composition,
      serveUrl,
      codec,
      outputLocation: outPath,
      inputProps,
      chromiumOptions: {
        enableMultiProcessOnLinux: true,
      },
      onProgress: ({ progress }) => {
        if (Math.floor(progress * 100) % 10 === 0) {
          console.log(`[render ${jobId}] ${Math.round(progress * 100)}%`);
        }
      },
    });

    updateJob(jobId, { status: "uploading" });
    const key = `renders/${jobId}.mp4`;
    const url = await uploadFile(key, outPath, "video/mp4");
    updateJob(jobId, { status: "done", url });
    console.log(`[render ${jobId}] done -> ${url}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[render ${jobId}] erro:`, message);
    updateJob(jobId, { status: "error", error: message });
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
}

const app = express();
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true, s3: s3Config });
});

app.post("/renders", (req: Request, res: Response) => {
  const parsed = renderRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_body", details: parsed.error.flatten() });
    return;
  }
  const { compositionId, inputProps, codec } = parsed.data;
  const job = createJob(compositionId);
  void runRender(job.id, compositionId, inputProps ?? {}, codec);
  res.status(202).json({ id: job.id, status: job.status });
});

app.get("/renders/:id", (req: Request, res: Response) => {
  const job = getJob(req.params.id);
  if (!job) {
    res.status(404).json({ error: "not_found" });
    return;
  }
  res.json(job);
});

app.listen(PORT, () => {
  console.log(`[server] Remotion render server ouvindo em :${PORT}`);
  console.log(`[server] S3 endpoint=${s3Config.endpoint} bucket=${s3Config.bucket} public=${s3Config.publicEndpoint}`);
});
