# nextdns-sync

## 🙏 Acknowledgment

This project was originally created by [John Doe](https://github.com/ryosoftware).

John implemented the core logic of this tool, including the synchronization workflow and the comparison algorithm that determines which rewrites must be added, updated, or deleted — the heart of the project.

This version includes additional improvements made by me, with the assistance of Microsoft Copilot, such as:

- Multi‑stage Docker image optimization  
- Enhanced logging system (INFO + detailed DEBUG mode)  
- Consistent English log messages  
- Improved project structure  
- A clean and functional Makefile  
- General refinements and quality‑of‑life improvements  

All credit for the original idea and foundation of the project goes to John.

## 📘 Introduction

A lightweight and reliable synchronization service that keeps **AdGuard Home rewrites** in sync with **NextDNS rewrites**.

Designed to run as a small Docker container, with clean logging, health checks, and optional dry‑run mode.

This tool is ideal for users who maintain local DNS rewrites in AdGuard Home but also want them replicated in NextDNS for roaming devices.

## 🚀 Features

- Syncs AdGuard Home rewrites → NextDNS rewrites
- Detects differences (ADD / UPDATE / DELETE)
- Clean and consistent logging (INFO + detailed DEBUG mode)
- Healthcheck endpoint (`/health`)
- Dry‑run mode (`--dry-run`)
- Runs continuously with a configurable sync interval
- Minimal dependencies, fast startup, production‑ready

## 📁 Project structure

```
nextdns-sync/
├── compose.yaml
├── .env.sample
├── Makefile
├── README.md
└── build/
    ├── app.py
    ├── dockerfile
    └── requirements.txt
```

## ⚙️ Requirements

- Python 3.10+
- Docker (recommended)
- A valid **NextDNS API key**
- A valid **NextDNS configuration ID**
- A readable `AdGuardHome.yaml` file containing your rewrites

## 🔧 Environment variables

| Variable | Description | Required |
|---------|-------------|----------|
| `NEXTDNS_CONFIG_ID` | Your NextDNS profile ID | Yes |
| `NEXTDNS_API_KEY` | Your NextDNS API key | Yes |
| `SYNC_INTERVAL_SECONDS` | Sync interval (default: 3600) | No |
| `LOG_LEVEL` | Logging level (`INFO`, `DEBUG`, `ERROR`) | No |

Example `.env`:

```
NEXTDNS_CONFIG_ID=xxxxxx
NEXTDNS_API_KEY=yyyyyy
SYNC_INTERVAL_SECONDS=3600
LOG_LEVEL=INFO
```

## 🐳 Running with Docker Compose

```bash
docker compose up -d
```

View logs:

```bash
docker compose logs -f nextdns-sync
```

## 🧪 Dry‑run mode

Simulates changes without applying them:

```bash
docker compose run --rm nextdns-sync --dry-run
```

## 📡 Healthcheck

The container exposes a simple HTTP healthcheck:

```
GET http://localhost:8080/health
```

Returns:

```
200 OK
```

## 📝 Logging

### INFO mode (default)
Shows:

- Sync interval
- Differences summary (PLAN)
- ADD / UPDATE / DELETE operations
- Sync completion

Example:

```
[INFO] nextdns-sync: PLAN — ADD=0, UPDATE=0, DELETE=0
[INFO] nextdns-sync: Synchronization completed successfully
[INFO] nextdns-sync: Sync finished
```

### DEBUG mode
Enable with:

```
LOG_LEVEL=DEBUG
```

Adds:

- Loaded AdGuard entries
- Loaded NextDNS entries
- Normalized rewrite counts
- Detailed comparison logs
- Payloads sent to NextDNS
- Sync duration

Example:

```
[DEBUG] nextdns-sync: Loaded 42 AdGuard rewrites
[DEBUG] nextdns-sync: Marking for UPDATE: example.com (AdGuard=1.2.3.4, NextDNS=5.6.7.8)
[DEBUG] nextdns-sync: POST payload: {'name': 'test.local', 'content': '1.2.3.4'}
```

## 🔄 How synchronization works

1. Load rewrites from `AdGuardHome.yaml`
2. Fetch rewrites from NextDNS API
3. Compare both sets
4. Build a PLAN:
   - ADD missing entries
   - UPDATE mismatched entries
   - DELETE orphaned entries
5. Apply changes (unless dry‑run)
6. Log results

## 💡 FUTURE IDEAS

These are potential enhancements that could be added later:

### 1) **Retries with exponential backoff**
Improve resilience by retrying API calls when NextDNS is temporarily unavailable.

### 2) **Structured JSON logging**
Useful for Grafana Loki or other log aggregation systems.

### 3) **Prometheus metrics endpoint**
Expose metrics such as:
- sync duration  
- number of rewrites added/updated/deleted  
- last successful sync timestamp  

Ideal for monitoring dashboards.
