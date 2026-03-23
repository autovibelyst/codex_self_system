# Volume Backup List (TT-Core)

All data lives under `compose\tt-core\volumes\` as bind mounts.
Back up by copying that folder tree.

## Always back up (Core)
| Folder | Service | Notes |
|---|---|---|
| `volumes\postgres\data` | Postgres | Main DB — critical |
| `volumes\n8n` | n8n | Workflows, credentials |
| `volumes\pgadmin\data` | pgAdmin | Server configs |

| `volumes\redisinsight\data` | RedisInsight | Connection configs |

## Back up if profile enabled
| Folder | Profile | Notes |
|---|---|---|
| `volumes\mariadb\data` | wordpress | WordPress DB |
| `volumes\wordpress\html` | wordpress | WordPress files, uploads |
| `volumes\qdrant\storage` | qdrant | Vector data |
| `volumes\openwebui\data` | ai | Chat history, settings |
| `volumes\kanboard\data` | kanboard | Tasks, projects |
| `volumes\kanboard\plugins` | kanboard | Installed plugins |
| `volumes\metabase\data`   | metabase | Dashboards, settings |
| `volumes\openclaw\data`   | openclaw | Agent config, memory, state |

## Do NOT back up (large / rebuildable)
| Folder | Reason |
|---|---|
| `volumes\ollama\models` | Very large (10–50 GB/model). Re-pull with `ollama pull`. |
| `volumes\redis\data` | Cache only — safe to lose. |
