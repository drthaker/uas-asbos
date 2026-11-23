#!/bin/bash

AUTH_LOG="/var/log/auth.log"
NGINX_LOG="/var/log/nginx/access.log"
OUTPUT_FILE="/var/log/laporan_anomali.txt"

{
  echo "=========================================================="
  echo "LAPORAN ANALISIS LOG & ANOMALI SERVER"
  echo "Waktu Pembuatan: $(date)"
  echo "=========================================================="
  echo ""
  echo "[1] TOP 5 IP PERCOBAAN GAGAL LOGIN SSH (/var/log/auth.log)"
  echo "Jumlah | Alamat IP"
  echo "--------------------------"
  if [ -f "$AUTH_LOG" ]; then
    SSH_RESULT=$(grep -E "Failed password|Invalid user" "$AUTH_LOG" | awk '{for(i=1;i<=NF;i++) if($i=="from") print $(i+1)}' | sort | uniq -c | sort -nr | head -n 5)
    if [ -n "$SSH_RESULT" ]; then
      echo "$SSH_RESULT"
    else
      echo "(Belum ada percobaan gagal login SSH yang tercatat)"
    fi
  else
    echo "(File $AUTH_LOG tidak ditemukan)"
  fi

  echo ""
  echo "[2] TOP 5 IP PENGAKSES WEB SERVER TERBANYAK (/var/log/nginx/access.log)"
  echo "Jumlah | Alamat IP"
  echo "--------------------------"
  if [ -f "$NGINX_LOG" ]; then
    NGINX_RESULT=$(awk '{print $1}' "$NGINX_LOG" | sort | uniq -c | sort -nr | head -n 5)
    if [ -n "$NGINX_RESULT" ]; then
      echo "$NGINX_RESULT"
    else
      echo "(Belum ada trafik akses web yang tercatat)"
    fi
  else
    echo "(File $NGINX_LOG belum tersedia - menunggu instalasi Nginx oleh Anggota 2)"
  fi
  echo ""
} > "$OUTPUT_FILE"

echo "Laporan anomali berhasil dibuat di $OUTPUT_FILE"
