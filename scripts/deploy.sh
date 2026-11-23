#!/usr/bin/env bash
# Skrip deployment otomatis untuk GitHub Actions (Fase 4 - ASBOS Kelompok 3)
#
# KENAPA pakai `set -euo pipefail`?
# -e: hentikan skrip segera jika ada perintah yang gagal (exit code != 0)
# -u: anggap error jika ada variabel yang belum didefinisikan
# -o pipefail: gagalkan pipeline jika perintah di tengah pipe gagal
set -euo pipefail

APP_DIR="/var/www/inventori-gudang"
HEALTH_URL="http://127.0.0.1:8000/health"
MAX_WAIT_SECONDS=60
INTERVAL_SECONDS=2

echo "[deploy] Masuk ke direktori proyek: ${APP_DIR}"
cd "${APP_DIR}"

# Pastikan file .env produksi tetap tersedia (tidak dikelola oleh Git)
if [[ ! -f .env ]]; then
  echo "[deploy] ERROR: File .env tidak ditemukan di ${APP_DIR}." >&2
  exit 1
fi

# Tarik kode terbaru dari branch main secara bersih (repo publik via HTTPS,
# sehingga VPS tidak perlu menyimpan token/credential GitHub tambahan).
# File .env aman karena masuk dalam .gitignore.
echo "[deploy] Mengambil pembaruan terbaru dari origin/main..."
git fetch origin main
git reset --hard origin/main

# Bangun ulang image jika ada perubahan dan jalankan ulang container
echo "[deploy] Menjalankan docker compose up -d --build..."
docker compose up -d --build

# Verifikasi aplikasi benar-benar sehat (HTTP 200 + DB connected) sebelum dianggap sukses
echo "[deploy] Menunggu healthcheck di ${HEALTH_URL} (timeout ${MAX_WAIT_SECONDS} detik)..."
elapsed=0
while true; do
  if curl -fsS "${HEALTH_URL}" > /dev/null 2>&1; then
    echo "[deploy] Healthcheck OK setelah ${elapsed} detik."
    curl -sS "${HEALTH_URL}"
    echo ""
    break
  fi

  if (( elapsed >= MAX_WAIT_SECONDS )); then
    echo "[deploy] ERROR: Aplikasi tidak sehat setelah ${MAX_WAIT_SECONDS} detik." >&2
    echo "[deploy] Menampilkan 40 baris log container terakhir:" >&2
    docker compose logs --tail=40 >&2 || true
    exit 1
  fi

  sleep "${INTERVAL_SECONDS}"
  elapsed=$(( elapsed + INTERVAL_SECONDS ))
done

# Hapus dangling image bekas build sebelumnya agar disk VPS tidak penuh
# (aman, tidak menghapus image atau container yang sedang berjalan)
echo "[deploy] Membersihkan dangling Docker image lama..."
docker image prune -f

echo "[deploy] Deployment berhasil dan aplikasi dalam kondisi sehat."
