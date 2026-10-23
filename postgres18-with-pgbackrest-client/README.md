# postgres18-with-pgbackrest-client

**English** | [繁體中文](README.zh-TW.md)

A PostgreSQL image based on the official `postgres:18` image, with:

- **pgBackRest**: lets the container act as a pgBackRest database host for `archive_command` and backups.
- **pgvector** (since 1.1.0): provides the `vector` extension for vector storage and similarity search.

Current version: **1.1.0**. See [CHANGELOG.md](CHANGELOG.md) for changes and [GUIDELINE.md](GUIDELINE.md) for maintenance requirements.

[Contributing](../CONTRIBUTING.md) · [Security](../SECURITY.md) · [MIT License](../LICENSE)

## Directory layout

```text
postgres18-with-pgbackrest-client/
├── dockerfile
├── .dockerignore
├── README.md
├── README.zh-TW.md
├── CHANGELOG.md
└── GUIDELINE.md
```

## Contents

| Component | Source | Added in |
|---|---|---|
| PostgreSQL 18 | Official `postgres:18` image | 1.0.0 |
| `pgbackrest` | PGDG apt repository | 1.0.0 |
| `ca-certificates` | Debian apt | 1.0.0 |
| `postgresql-18-pgvector` | PGDG apt repository | 1.1.0 |

The following directories are created with ownership set to `postgres:postgres`:

| Path | Purpose |
|---|---|
| `/etc/pgbackrest` | `pgbackrest.conf` configuration |
| `/var/log/pgbackrest` | pgBackRest logs |
| `/var/spool/pgbackrest` | Spool for asynchronous archiving (`archive-async=y`) |

## Build

```bash
cd postgres18-with-pgbackrest-client

docker build -f dockerfile -t postgres18-with-pgbackrest-client:1.1.0 .
```

Verify the installed tools:

```bash
docker run --rm postgres18-with-pgbackrest-client:1.1.0 pgbackrest version
docker run --rm postgres18-with-pgbackrest-client:1.1.0 dpkg -l postgresql-18-pgvector
```

## Usage

### Docker Compose example

```yaml
services:
  postgres:
    image: postgres18-with-pgbackrest-client:1.1.0
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    command:
      - postgres
      - -c
      - archive_mode=on
      - -c
      - archive_command=pgbackrest --stanza=main archive-push %p
    volumes:
      - pgdata:/var/lib/postgresql
      - ./pgbackrest/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro
      - pgbackrest-log:/var/log/pgbackrest
      - pgbackrest-spool:/var/spool/pgbackrest

volumes:
  pgdata:
  pgbackrest-log:
  pgbackrest-spool:
```

> The official PostgreSQL 18 image uses `/var/lib/postgresql/18/docker` as its data directory. Mount the volume at `/var/lib/postgresql`, rather than the older `/var/lib/postgresql/data` path.

Set the stanza name, repository location, and other options in your `pgbackrest.conf`. Backup scheduling is handled by a separate `pgbackrest-agent` container.

### Enable pgvector

The image installs extension files. Enable the extension separately in each database that needs it:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

To enable it during initial database setup, mount a SQL file under `/docker-entrypoint-initdb.d/`:

```sql
-- initdb/01-pgvector.sql
CREATE EXTENSION IF NOT EXISTS vector;
```

```yaml
    volumes:
      - ./initdb:/docker-entrypoint-initdb.d:ro
```

> Initialization scripts run only when the data directory is empty, and this example applies to `POSTGRES_DB`. Run `CREATE EXTENSION` manually for existing databases.

Quick verification:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT id FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 1;
```

## Upgrade from 1.0.0 to 1.1.0

1. Build or pull the `1.1.0` image.
2. Update the image tag in Compose, then run `docker compose up -d postgres`.
3. Run `CREATE EXTENSION IF NOT EXISTS vector;` in databases that need it.

This image update requires no data migration. Once a database uses `vector`, its pgBackRest restore target must also include pgvector, as provided by image version 1.1.0 or later.

## Maintenance and licensing

See the root [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md) for shared practices. Image-specific testing, compatibility, and release rules are in [GUIDELINE.md](GUIDELINE.md). Original work is licensed under the [MIT License](../LICENSE). PostgreSQL, pgBackRest, pgvector, the base image, and dependencies retain their own licenses.
