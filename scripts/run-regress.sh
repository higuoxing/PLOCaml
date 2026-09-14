#!/usr/bin/env bash
# Run the ported official PL/Python-style pg_regress suite against an
# already-installed plocamlu (cargo pgrx install) and a running Postgres.
set -euo pipefail

PG_CONFIG="${PG_CONFIG:-/usr/lib/postgresql/16/bin/pg_config}"
PGPORT="${PGPORT:-28816}"
PGHOST="${PGHOST:-127.0.0.1}"
export PG_CONFIG PGPORT PGHOST

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

make -C "$ROOT" installcheck PG_CONFIG="$PG_CONFIG"
