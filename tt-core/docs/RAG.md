# RAG (Retrieval Augmented Generation) Guide — TT-Production v14.0

## Stack Components for RAG

| Component | Role | Addon File |
|-----------|------|-----------|
| Qdrant | Vector database (stores embeddings) | `addons/80-qdrant.addon.yml` |
| Ollama | Local LLM + embeddings model | `addons/20-openwebui.addon.yml` (pulls Ollama) |
| Open WebUI | Chat interface with RAG support | `addons/20-openwebui.addon.yml` |
| MinIO | Document storage (PDFs, files) | `addons/60-minio.addon.yml` |
| n8n | Orchestration (ingest → embed → store) | core |

## Quick Setup

```bash
# 1. Enable RAG addons
# Edit config/services.select.json:
# "enabled_services": ["qdrant", "ollama", "openwebui", "minio"]

# 2. Start services
bash scripts-linux/start-core.sh

# 3. Pull embedding model
docker exec tt-core-ollama ollama pull nomic-embed-text

# 4. Pull chat model
docker exec tt-core-ollama ollama pull llama3.2

# 5. Configure Open WebUI
# Visit http://localhost:3000 → Settings → Documents → Qdrant
# Qdrant URL: http://tt-core-qdrant:6333
# API Key: your TT_QDRANT_API_KEY from .env
```

## n8n RAG Workflow

Use the n8n Qdrant and HTTP nodes to build ingestion pipelines:
1. HTTP trigger (document upload) → File processing
2. Text splitting → Ollama embeddings
3. Store in Qdrant collection
4. Query via n8n + return to user

## Security Notes

- Qdrant is on `tt_core_internal` network (not publicly accessible)
- API key required (`TT_QDRANT_API_KEY`)
- MinIO API key required for document storage
- Never expose Qdrant API publicly without additional auth layer
