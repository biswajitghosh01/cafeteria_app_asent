#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${BACKUP_DIR:-/var/backups/food-court-counter}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DB_NAME="${POSTGRES_DB:-food_court_db}"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%F_%H%M)"
OUT="$BACKUP_DIR/db-${STAMP}.sql"
sudo -u postgres pg_dump "$DB_NAME" > "$OUT"
gzip "$OUT"
find "$BACKUP_DIR" -name 'db-*.sql.gz' -mtime "+${RETENTION_DAYS}" -delete
echo "Backup written: ${OUT}.gz"
