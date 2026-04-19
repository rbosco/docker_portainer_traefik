import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { createReadStream, statSync } from "node:fs";

const endpoint = process.env.S3_ENDPOINT ?? "http://minio:9000";
const region = process.env.S3_REGION ?? "us-east-1";
const bucket = process.env.S3_BUCKET ?? "remotion";
const publicEndpoint = process.env.S3_PUBLIC_ENDPOINT ?? endpoint;
const forcePathStyle = (process.env.S3_FORCE_PATH_STYLE ?? "true") === "true";

if (!process.env.S3_ACCESS_KEY || !process.env.S3_SECRET_KEY) {
  console.warn("[s3] S3_ACCESS_KEY/S3_SECRET_KEY nao definidos — uploads vao falhar");
}

export const s3 = new S3Client({
  endpoint,
  region,
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY ?? "",
    secretAccessKey: process.env.S3_SECRET_KEY ?? "",
  },
  forcePathStyle,
});

export async function uploadFile(key: string, filePath: string, contentType: string) {
  const size = statSync(filePath).size;
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: createReadStream(filePath),
      ContentType: contentType,
      ContentLength: size,
    }),
  );
  return publicUrl(key);
}

export function publicUrl(key: string): string {
  const base = publicEndpoint.replace(/\/$/, "");
  return `${base}/${bucket}/${key}`;
}

export const s3Config = { endpoint, publicEndpoint, bucket, region, forcePathStyle };
