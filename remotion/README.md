# Remotion render server

App Remotion customizado (Studio + Express render server) com upload direto para o MinIO (S3 compatível) desta stack.

## Scripts

- `npm run remotion:studio` — abre o Studio (porta 3000). A stack `remotion-studio` usa este comando.
- `npm start` — sobe o Express (POST `/renders`, GET `/renders/:id`, GET `/health`). A stack `remotion-render` usa este comando.

## Composition de exemplo

`HelloWorld` (150 frames / 30fps / 1280x720), recebe `inputProps` `{ title: string }`.

## API

### POST /renders

```
{
  "compositionId": "HelloWorld",
  "inputProps": { "title": "Meu primeiro render" },
  "codec": "h264"
}
```

Resposta `202`: `{ "id": "<jobId>", "status": "queued" }`.

### GET /renders/:id

```
{ "id": "...", "status": "rendering" | "uploading" | "done" | "error", "url": "https://s3.<dominio>/remotion/renders/<id>.mp4" }
```

### GET /health

Retorna config S3 (endpoint interno, endpoint público, bucket).

## Variáveis de ambiente (injetadas pela stack)

| Variável | Descrição |
|---|---|
| `S3_ENDPOINT` | URL interna do MinIO (ex.: `http://minio:9000`) |
| `S3_PUBLIC_ENDPOINT` | URL pública S3 (ex.: `https://s3.seudominio.com`) |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | Credenciais (usar `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`) |
| `S3_BUCKET` | Bucket destino (default `remotion`) |
| `S3_REGION` | Região S3 (default `us-east-1`) |
| `S3_FORCE_PATH_STYLE` | `true` para MinIO |
| `PORT` | Default `3000` |

## Uso via n8n (mesmo Swarm)

Conecte o container do n8n à rede interna desta stack para alcançar o render:

```bash
docker network connect remotion_internal $(docker ps -qf name=n8n_n8n | head -1)
```

No n8n: HTTP Request → `POST http://remotion-render:3000/renders`.
