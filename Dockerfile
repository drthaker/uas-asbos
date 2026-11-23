# Gunakan python:3.12-slim karena jauh lebih ringan dari image full
# dan memperkecil permukaan serangan (attack surface).
FROM python:3.12-slim

# Mencegah Python membuat file .pyc dan memastikan log langsung tampil (unbuffered)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_BIND=127.0.0.1 \
    APP_PORT=8000

WORKDIR /app

# Salin requirements.txt lebih dulu agar Docker bisa memanfaatkan layer cache:
# perubahan pada app.py tidak akan memicu pip install ulang.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Buat user non-root (prinsip Least Privilege) agar proses aplikasi
# di dalam container tidak berjalan sebagai root.
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup --no-create-home appuser

# Salin kode aplikasi dengan kepemilikan milik appuser
COPY --chown=appuser:appgroup app.py ./
COPY --chown=appuser:appgroup templates ./templates
COPY --chown=appuser:appgroup static ./static

# Jalankan container sebagai user non-root
USER appuser

EXPOSE 8000

# HEALTHCHECK memakai Python stdlib (tanpa instal curl) agar image tetap ramping.
# Endpoint /health memverifikasi koneksi nyata ke PostgreSQL (HTTP 200/503).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; p = os.getenv('APP_PORT', '8000'); urllib.request.urlopen(f'http://127.0.0.1:{p}/health', timeout=3)" || exit 1

# Gunakan Gunicorn (WSGI server produksi, bukan Flask dev server).
# Memakai 'exec' agar Gunicorn menjadi PID 1 dan menerima sinyal SIGTERM dengan bersih.
CMD ["sh", "-c", "exec gunicorn --bind ${APP_BIND}:${APP_PORT} --workers 2 --threads 4 --timeout 30 --access-logfile - --error-logfile - app:app"]
