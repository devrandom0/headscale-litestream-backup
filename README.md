# Headscale + Litestream Active/Backup

A general-purpose Docker solution for running [headscale](https://github.com/juanfont/headscale) with continuous SQLite replication to any S3-compatible storage via [Litestream](https://litestream.io/).

**Active/Backup model**: if the active instance goes down, start the same image elsewhere — it automatically restores the latest state from S3 and resumes.

## How It Works

1. **Startup**: entrypoint checks S3 for an existing backup. If the local DB is missing and a replica exists, it restores it automatically.
2. **Runtime**: Litestream continuously replicates the SQLite WAL to S3 in near real-time.
3. **Failover**: Deploy the same image with the same env vars on another host. It restores from S3 and starts serving.

## Quick Start

```bash
# 1. Copy and edit environment variables
cp .env.example .env
# Edit .env with your S3 credentials

# 2. Add your headscale config
cp /path/to/your/headscale.yaml config/headscale.yaml

# 3. Start
docker compose up -d
```

## Configuration

All configuration is via environment variables (see `.env.example`):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `S3_ACCESS_KEY_ID` | Yes* | — | S3 access key |
| `S3_SECRET_ACCESS_KEY` | Yes* | — | S3 secret key |
| `S3_BUCKET` | Yes* | — | S3 bucket name |
| `S3_ENDPOINT` | Yes* | — | S3 endpoint URL |
| `S3_REGION` | Yes* | — | S3 region |
| `LITESTREAM_ENABLED` | No | `true` | Set to `false` to run headscale without replication (e.g. local dev) |
| `LITESTREAM_BACKUP_DIR` | No | `headscale-backups` | S3 path prefix for replica files |
| `LITESTREAM_SYNC_INTERVAL` | No | `10s` | How often to sync WAL to S3 |
| `LITESTREAM_RETENTION` | No | `24h` | How long to keep snapshots |
| `LITESTREAM_RETENTION_CHECK_INTERVAL` | No | `1h` | How often to check retention |
| `LITESTREAM_SNAPSHOT_INTERVAL` | No | `6h` | How often to take full snapshots |
| `HEADSCALE_DB_PATH` | No | `/var/lib/headscale/db.sqlite` | Path to SQLite database |

*Required when `LITESTREAM_ENABLED=true` (the default).

### S3-Compatible Providers

Works with any S3-compatible storage:

| Provider | Endpoint Example |
|----------|-----------------|
| MinIO | `http://minio:9000` |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |
| Backblaze B2 | `https://s3.us-west-000.backblazeb2.com` |
| Wasabi | `https://s3.wasabisys.com` |
| DigitalOcean Spaces | `https://<region>.digitaloceanspaces.com` |

## Failover Procedure

1. Stop the active instance (or it crashes)
2. On backup host, ensure `.env` has the same S3 credentials
3. Run `docker compose up -d`
4. The entrypoint auto-restores from S3 and starts headscale
5. Update DNS/load balancer to point to the new instance

## Architecture

```
┌──────────────────────┐         ┌──────────────┐
│   Active Instance    │         │  S3 Storage  │
│                      │ ──WAL──▶│  (any S3)    │
│  headscale + litestream│        │              │
└──────────────────────┘         └──────┬───────┘
                                        │
                                        │ restore
                                        ▼
                                 ┌──────────────────────┐
                                 │  Backup Instance     │
                                 │                      │
                                 │  headscale + litestream│
                                 └──────────────────────┘
```

## Headscale Config

Mount your own `headscale.yaml` at `/etc/headscale/config.yaml`. Make sure `database.type` is set to `sqlite` and the path matches `HEADSCALE_DB_PATH`.

> ⚠️ **Important (headscale v0.23+):** Set `wal_autocheckpoint: 0` — Litestream must own WAL checkpointing to guarantee replication consistency. If headscale checkpoints the WAL autonomously, Litestream can miss frames and produce a corrupt replica.

```yaml
database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true
    wal_autocheckpoint: 0   # required — let Litestream control WAL checkpointing
```

## Building

```bash
# Single arch
docker compose build

# Multi-arch
docker buildx build --platform linux/amd64,linux/arm64 -t headscale-litestream .
```

## Thanks

- [Luis Lavena](https://luislavena.info/til/backup-headscale-using-litestream/) — for the original write-up on combining headscale and Litestream
- [Niklas Rosenstein](https://github.com/NiklasRosenstein/headscale-fly-io) — for the fly.io-specific implementation that inspired this general solution
- [juanfont/headscale](https://github.com/juanfont/headscale) — the open-source Tailscale control server
- [benbjohnson/litestream](https://github.com/benbjohnson/litestream) — streaming SQLite replication

## License

[MIT](./LICENSE)
