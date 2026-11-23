#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/backups/postgresql"
DB_NAME="inventori_gudang_db"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SQL_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"
ARCHIVE_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

# Dump database PostgreSQL
sudo -u postgres pg_dump "${DB_NAME}" > "${SQL_FILE}"

# Kompresi ke .tar.gz lalu hapus file .sql sementara
tar -czf "${ARCHIVE_FILE}" -C "${BACKUP_DIR}" "$(basename "${SQL_FILE}")"
rm -f "${SQL_FILE}"

# Bersihkan backup lebih dari 7 hari agar disk tidak penuh
find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +7 -delete

echo "[$(date)] Backup berhasil: ${ARCHIVE_FILE}"
