# Sistem Manajemen Inventori Gudang — UAS ASBOS Kelompok 3

Repositori kode dan konfigurasi infrastruktur untuk Tugas Besar (*Project-Based Learning*) mata kuliah **Administrasi Sistem Berbasis Open Source (ASBOS)**, Program Studi Sistem Informasi, Universitas Tanjungpura Pontianak (Semester 5, Tahun Akademik 2026/2027).

- **Tema Kelompok 3:** Sistem Manajemen Inventori Gudang
- **Target VPS:** Ubuntu Server `24.04.5 LTS` (`asbos-tiga`, IP `103.55.37.230`, SSH port kustom `2222`)
- **Repositori:** `https://github.com/drthaker/uas-asbos`

---

## Arsitektur Sistem (Diagram Alur ASCII)

```text
                        [ Internet / Klien Browser ]
                                     |
                              HTTP Port 80
                         (UFW: Allow 2222, 80, 443)
                                     |
                                     v
+-----------------------------------------------------------------------------+
|                     VPS Ubuntu 24.04.5 LTS (asbos-tiga)                     |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  |  Nginx Reverse Proxy (Host, 0.0.0.0:80, server_tokens off)            |  |
|  |  Log akses: /var/log/nginx/access.log  --->  /opt/scripts/analyze_log |  |
|  +----------------------------------+------------------------------------+  |
|                                     | proxy_pass http://127.0.0.1:8000      |
|                                     v                                       |
|  +-----------------------------------------------------------------------+  |
|  |  Docker Container: inventori-gudang-app (network_mode: host)          |  |
|  |  Python 3.12-slim | User non-root: appuser | Gunicorn 127.0.0.1:8000  |  |
|  |  Flask + psycopg2 | Endpoint: /, /api/barang, /health (200/503)       |  |
|  +----------------------------------+------------------------------------+  |
|                                     | TCP 127.0.0.1:5432 (scram-sha-256)    |
|                                     v                                       |
|  +-----------------------------------------------------------------------+  |
|  |  PostgreSQL 16.15 (Host, localhost-only: 127.0.0.1:5432)              |  |
|  |  DB: inventori_gudang_db | User: inventori_user (non-superuser)       |  |
|  |  Cron 02:00: /opt/scripts/backup_db.sh -> /var/backups/postgresql     |  |
|  +-----------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------+
              ^                                         ^
              | SSH :2222 (CI key + pinned host key)    | SSH :2222 (Agentless)
              |                                         |
  [ GitHub Actions CI/CD ]                  [ Ansible Control Node (WSL) ]
  test (py_compile, flake8,                 playbook.yml (idempoten):
        docker build) -> deploy.sh          Nginx + user monitoring + config
```

---

## Struktur Repositori

```text
.
├── .github/
│   └── workflows/
│       └── deploy.yml                # Pipeline CI/CD (Job test + Job deploy via OpenSSH native)
├── ansible/
│   ├── ansible.cfg                   # Konfigurasi Ansible Control Node
│   ├── inventory.ini.example         # Templat inventory [webservers] (inventory.ini di-.gitignore)
│   └── playbook.yml                  # Playbook idempoten (Nginx, user monitoring, config + handler)
├── db/
│   ├── schema.sql                    # Skema 3 tabel: kategori, barang, transaksi_stok
│   └── seed.sql                      # Data awal realistis gudang (termasuk sampel stok menipis)
├── nginx/
│   └── inventori-gudang.conf         # Server block Nginx Reverse Proxy (dipakai Fase 3 & 5)
├── scripts/
│   ├── analyze_log.sh                # Skrip analisis log SSH & Nginx (Fase 6)
│   ├── backup_db.sh                  # Skrip backup harian PostgreSQL .tar.gz (Fase 2)
│   └── deploy.sh                     # Skrip auto-deploy VPS untuk GitHub Actions (Fase 4)
├── static/
│   └── style.css                     # Stylesheet lokal dashboard inventori gudang
├── templates/
│   └── index.html                    # Antarmuka web dashboard inventori gudang
├── .dockerignore
├── .env.example                      # Templat variabel environment (.env asli di-.gitignore)
├── .gitattributes                    # Menjaga akhir baris LF untuk skrip Linux
├── .gitignore
├── app.py                            # Aplikasi web Flask + endpoint /api/barang & /health
├── Dockerfile                        # Image python:3.12-slim non-root + HEALTHCHECK + Gunicorn
├── docker-compose.local.yml          # Compose khusus uji lokal laptop (dengan container Postgres)
├── docker-compose.yml                # Compose produksi VPS (network_mode: host, 127.0.0.1:8000)
├── requirements.txt                  # Dependensi Python (Flask, gunicorn, psycopg2-binary)
└── README.md
```

---

## Cara Pengujian Lokal (Di Laptop)

Untuk mencoba aplikasi secara lokal menggunakan Docker Desktop (tanpa menyentuh VPS):

```bash
docker compose -f docker-compose.local.yml up --build -d
# Akses di browser: http://localhost:8000
# Untuk mematikan dan menghapus volume sementara:
docker compose -f docker-compose.local.yml down -v
```

---

## Cara Deployment di VPS (Ringkasan)

1. **Siapkan `.env` di `/var/www/inventori-gudang`:** salin dari `.env.example`, atur `chmod 600 .env`, lalu isi `DB_PASSWORD` (`inventori_user`) dan `SECRET_KEY`.
2. **Inisialisasi database (sekali di awal, sebagai `inventori_user`):**
   ```bash
   set -a && source .env && set +a
   PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f db/schema.sql
   PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f db/seed.sql
   unset DB_PASSWORD SECRET_KEY
   ```
3. **Jalankan container & Nginx Reverse Proxy:**
   ```bash
   docker compose up -d --build
   sudo cp nginx/inventori-gudang.conf /etc/nginx/sites-available/inventori-gudang.conf
   sudo ln -sf /etc/nginx/sites-available/inventori-gudang.conf /etc/nginx/sites-enabled/inventori-gudang.conf
   sudo rm -f /etc/nginx/sites-enabled/default
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. **Otomatisasi CI/CD:** setiap `git push` ke branch `main` memicu `.github/workflows/deploy.yml` (menggunakan 5 GitHub Secrets: `VPS_HOST`, `VPS_PORT`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_HOST_KEY`) untuk menjalankan `scripts/deploy.sh`.
5. **Otomatisasi Ansible (dari Control Node WSL):**
   ```bash
   cd ansible
   cp inventory.ini.example inventory.ini   # isi IP, port 2222, user
   ansible-playbook --syntax-check playbook.yml
   ansible-playbook -K playbook.yml         # eksekusi kedua menghasilkan changed=0
   ```

---

## Daftar Luaran (Deliverables)

1. **Laporan Teknis (PDF):** Bab 1–4 dilengkapi tangkapan layar terminal & browser.
2. **Tautan Repositori Kode:** `https://github.com/drthaker/uas-asbos` (berisi konfigurasi CI/CD, Ansible Playbook, Dockerfile, konfigurasi Nginx, aplikasi purwarupa, dan seluruh shell script).
3. **Kredensial Akses Dosen:** akun `dianprawira` beserta *public key* dosen pada VPS.
4. **Live Demo:** presentasi langsung 15 menit.
