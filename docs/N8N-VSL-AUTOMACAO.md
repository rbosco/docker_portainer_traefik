# Automação n8n: VSL (roteiro → cenas → lip sync → unir → Drive)

Documentação do workflow de criação de VSL com controle por Google Drive, geração de cenas (kie.ai), lip sync por cena e entrega do vídeo final no Drive.

## Importar o workflow no n8n

1. No n8n, acesse **Workflows** e use **Import from File** (menu ⋮ no canto superior direito).
2. Selecione o arquivo:  
   `workflows/n8n-vsl-roteiro-cenas-lipsync-drive.json`
3. Após a importação, **configure as credenciais** em cada nó que exibir aviso:
   - **Google Drive Trigger** e **Ler arquivo roteiro** / **Upload vídeo final**: crie ou selecione uma credencial **Google Drive OAuth2** (conta com acesso à pasta do projeto).
   - **kie.ai – Gerar vídeo cena** e **kie.ai – Status vídeo**: crie uma credencial **Header Auth** com:
     - Nome: `Authorization`
     - Valor: `Bearer SEU_KIE_AI_API_KEY` (obtenha em [kie.ai/api-key](https://kie.ai/api-key)).
   - **Lip sync (fal.ai)**: crie **Header Auth** para a API escolhida (fal.ai, Lipsync.studio ou Lipdub) conforme a documentação de cada uma.
4. Nos nós **Google Drive Trigger** e **Ler arquivo roteiro**, selecione o **Drive** e a **pasta** correspondente à pasta `01-Roteiros` (ID da pasta no Google Drive).
5. No nó **Upload vídeo final**, selecione a pasta `05-Videos-Prontos` como destino.
6. **Concatenação:** o nó "Concatenação (ffmpeg/API)" está como placeholder. Substitua por:
   - **Opção A:** um nó **Execute Command** com ffmpeg (ambiente com ffmpeg instalado), ou  
   - **Opção B:** um nó **HTTP Request** para uma API de concatenação que receba `videoUrls` e devolva o vídeo único.  
   O nó seguinte (Upload vídeo final) espera o binário do vídeo na propriedade `data` do item.

## Formato do roteiro (arquivo na pasta 01-Roteiros)

O arquivo que dispara o workflow deve ser um **JSON** com a estrutura abaixo. Salve como `.json` (ex.: `meu-vsl.json`) na pasta do Drive configurada no trigger.

```json
{
  "nomeProjeto": "nome-do-projeto",
  "aspectRatio": "9:16",
  "quality": "720p",
  "cenas": [
    {
      "prompt": "Descrição da cena 1 para a kie.ai (text-to-video)",
      "texto": "Texto opcional para TTS / narração da cena",
      "duracao": 5,
      "ordem": 0
    },
    {
      "prompt": "Descrição da cena 2",
      "duracao": 5,
      "ordem": 1
    }
  ]
}
```

| Campo          | Obrigatório | Descrição |
|----------------|-------------|-----------|
| `nomeProjeto`  | Não         | Nome do projeto; usado no nome do arquivo final (default: `vsl`). |
| `aspectRatio`  | Não         | Proporção do vídeo: `16:9`, `9:16`, `1:1`, `4:3`, `3:4` (default: `9:16`). |
| `quality`      | Não         | `720p` ou `1080p` (default: `720p`). Para 10s na Runway, não usar 1080p. |
| `cenas`        | Sim         | Array de cenas. |
| `cenas[].prompt` | Sim       | Texto do prompt para a API kie.ai (Runway). |
| `cenas[].texto`  | Não        | Texto para TTS/narração (se usar lip sync com áudio gerado). |
| `cenas[].duracao`| Não        | Duração em segundos: `5` ou `10` (default: `5`). |
| `cenas[].ordem`  | Não        | Ordem da cena (default: índice no array). |

## Estrutura de pastas no Google Drive

Recomendada para o projeto:

```
VSL-Producao/
├── 01-Roteiros/             ← Trigger: novos arquivos aqui disparam o workflow
├── 02-Referencias/          ← Imagens por cena (opcional)
├── 03-Em-Producao/          ← Controle (taskIds, status)
├── 04-Cenas-Intermediarias/
│   ├── brutas/
│   └── com-lipsync/
├── 05-Videos-Prontos/       ← Saída: vídeo final
└── 06-Logs-Erros/
```

## APIs utilizadas

- **kie.ai (Runway):** geração de vídeo por cena. [Documentação](https://docs.kie.ai/runway-api/generate-ai-video). Autenticação: Bearer token.
- **Google Drive:** trigger, leitura do roteiro e upload do vídeo final. Credencial OAuth2 no n8n.
- **Lip sync:** fal.ai ([Sync Lipsync](https://fal.ai/models/fal-ai/sync-lipsync/api)), Lipsync.studio ou Lipdub. Configurar URL e body no nó conforme a API escolhida.

## Fluxo do workflow

1. **Google Drive Trigger** detecta novo arquivo em `01-Roteiros`.
2. **Ler arquivo roteiro** baixa o conteúdo do arquivo.
3. **Parse roteiro em cenas** converte o JSON em lista de itens (uma cena por item).
4. **Loop por cena** processa uma cena por vez:
   - **kie.ai – Gerar vídeo cena** envia o prompt para a API Runway.
   - **Aguardar geração** (30 s) e **kie.ai – Status vídeo** consultam o status até `success`.
   - **Status success?** encaminha para **Lip sync** quando a geração teve sucesso.
   - **Guardar ref cena** devolve um item com `video_url` para o loop.
5. Ao terminar o loop, **Listar vídeos para concat** monta a lista de URLs.
6. **Concatenação (ffmpeg/API)** deve produzir o vídeo único (configurar ffmpeg ou API).
7. **Upload vídeo final** envia o arquivo para `05-Videos-Prontos`.

## Onde configurar API keys

- **kie.ai:** credencial Header Auth no n8n com `Authorization: Bearer <API_KEY>`.
- **Lip sync (fal.ai etc.):** credencial Header Auth conforme documentação da API.
- Não inclua chaves no JSON do workflow; use apenas as credenciais do n8n.
