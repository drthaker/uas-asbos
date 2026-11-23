"""Aplikasi Sistem Manajemen Inventori Gudang (Kelompok 3 - ASBOS).

Menggunakan Flask + Gunicorn + psycopg2 dengan seluruh konfigurasi dari
environment variable dan seluruh query SQL diparameterisasi untuk mencegah
SQL injection.
"""

import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor
from flask import (
    Flask,
    flash,
    jsonify,
    redirect,
    render_template,
    request,
    url_for,
)
from werkzeug.middleware.proxy_fix import ProxyFix


app = Flask(__name__)

# Secret key untuk flash message Flask (diambil dari environment variable)
app.secret_key = os.getenv("SECRET_KEY", "dev-inventori-gudang-key")

# ProxyFix agar Flask mengenali IP klien & protokol asli dari header
# X-Forwarded-For / X-Forwarded-Proto yang diteruskan Nginx Reverse Proxy
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

APP_VERSION = os.getenv("APP_VERSION", "v1.0.0")


def get_db_config():
    """Membaca konfigurasi PostgreSQL hanya dari environment variable."""
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME", "inventori_gudang_db"),
        "user": os.getenv("DB_USER", "inventori_user"),
        "password": os.getenv("DB_PASSWORD", ""),
        "connect_timeout": 3,
    }


@contextmanager
def get_db_connection():
    """Context manager koneksi PostgreSQL agar koneksi selalu ditutup rapi."""
    conn = psycopg2.connect(**get_db_config())
    try:
        yield conn
    finally:
        conn.close()


@app.route("/health", methods=["GET"])
def health_check():
    """Endpoint healthcheck untuk Docker HEALTHCHECK dan verifikasi CI/CD.

    Mengembalikan HTTP 200 jika PostgreSQL merespons SELECT 1, atau HTTP 503
    jika database gagal dijangkau (tanpa membocorkan kredensial/detail error).
    """
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        return jsonify({
            "status": "healthy",
            "database": "connected",
            "version": APP_VERSION,
        }), 200
    except psycopg2.Error:
        return jsonify({
            "status": "unhealthy",
            "database": "disconnected",
            "version": APP_VERSION,
        }), 503


@app.route("/api/barang", methods=["GET"])
def api_daftar_barang():
    """Endpoint REST JSON untuk menampilkan daftar seluruh barang gudang."""
    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT
                        b.id,
                        b.sku,
                        b.nama,
                        b.kategori_id,
                        k.nama AS kategori_nama,
                        b.stok,
                        b.satuan,
                        b.lokasi_rak,
                        b.stok_minimum,
                        (b.stok <= b.stok_minimum) AS stok_menipis,
                        b.updated_at
                    FROM barang b
                    JOIN kategori k ON k.id = b.kategori_id
                    ORDER BY (b.stok <= b.stok_minimum) DESC, b.nama ASC;
                    """
                )
                rows = cur.fetchall()
        data = []
        for row in rows:
            item = dict(row)
            if item.get("updated_at"):
                item["updated_at"] = item["updated_at"].isoformat()
            data.append(item)
        low_count = sum(1 for item in data if item["stok_menipis"])
        return jsonify({
            "status": "ok",
            "total": len(data),
            "stok_menipis_count": low_count,
            "data": data,
        }), 200
    except psycopg2.Error:
        return jsonify({
            "status": "error",
            "message": "Gagal mengambil data barang dari database.",
        }), 503


@app.route("/", methods=["GET"])
def index():
    """Halaman utama: ringkasan inventori, daftar barang, form, dan riwayat."""
    keyword = request.args.get("q", "").strip()
    kategori_filter = request.args.get("kategori", "").strip()
    hanya_menipis = request.args.get("menipis", "") == "1"

    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Ambil semua kategori untuk dropdown filter & tambah barang
                cur.execute(
                    "SELECT id, nama FROM kategori ORDER BY nama ASC;"
                )
                kategori_list = cur.fetchall()

                # Query daftar barang dengan filter terparameterisasi
                clauses = []
                params = []
                if keyword:
                    clauses.append("(b.sku ILIKE %s OR b.nama ILIKE %s)")
                    like_val = f"%{keyword}%"
                    params.extend([like_val, like_val])
                if kategori_filter.isdigit():
                    clauses.append("b.kategori_id = %s")
                    params.append(int(kategori_filter))
                if hanya_menipis:
                    clauses.append("b.stok <= b.stok_minimum")

                where_sql = ""
                if clauses:
                    where_sql = "WHERE " + " AND ".join(clauses)

                query_barang = f"""
                    SELECT
                        b.id,
                        b.sku,
                        b.nama,
                        b.kategori_id,
                        k.nama AS kategori_nama,
                        b.stok,
                        b.satuan,
                        b.lokasi_rak,
                        b.stok_minimum,
                        (b.stok <= b.stok_minimum) AS stok_menipis
                    FROM barang b
                    JOIN kategori k ON k.id = b.kategori_id
                    {where_sql}
                    ORDER BY (b.stok <= b.stok_minimum) DESC, b.sku ASC;
                """
                cur.execute(query_barang, tuple(params))
                barang_list = cur.fetchall()

                # Daftar semua barang untuk dropdown transaksi stok
                cur.execute(
                    """
                    SELECT id, sku, nama, stok, satuan
                    FROM barang
                    ORDER BY sku ASC;
                    """
                )
                semua_barang = cur.fetchall()

                # Ringkasan KPI gudang (keseluruhan)
                cur.execute(
                    """
                    SELECT
                        COUNT(*) AS total_sku,
                        COALESCE(SUM(stok), 0) AS total_unit,
                        COUNT(*) FILTER (
                            WHERE stok <= stok_minimum
                        ) AS total_menipis
                    FROM barang;
                    """
                )
                summary = cur.fetchone()

                # 10 riwayat transaksi stok terbaru
                cur.execute(
                    """
                    SELECT
                        t.id,
                        b.sku,
                        b.nama AS barang_nama,
                        b.satuan,
                        t.tipe,
                        t.jumlah,
                        t.catatan,
                        t.waktu
                    FROM transaksi_stok t
                    JOIN barang b ON b.id = t.barang_id
                    ORDER BY t.waktu DESC, t.id DESC
                    LIMIT 10;
                    """
                )
                transaksi_list = cur.fetchall()

        return render_template(
            "index.html",
            barang_list=barang_list,
            semua_barang=semua_barang,
            kategori_list=kategori_list,
            transaksi_list=transaksi_list,
            summary=summary,
            keyword=keyword,
            kategori_filter=kategori_filter,
            hanya_menipis=hanya_menipis,
            app_version=APP_VERSION,
        )
    except psycopg2.Error:
        return render_template(
            "index.html",
            barang_list=[],
            semua_barang=[],
            kategori_list=[],
            transaksi_list=[],
            summary={"total_sku": 0, "total_unit": 0, "total_menipis": 0},
            keyword=keyword,
            kategori_filter=kategori_filter,
            hanya_menipis=hanya_menipis,
            app_version=APP_VERSION,
            db_error=True,
        ), 503


@app.route("/barang", methods=["POST"])
def tambah_barang():
    """Menambahkan barang baru ke tabel barang menggunakan query aman."""
    sku = request.form.get("sku", "").strip().upper()
    nama = request.form.get("nama", "").strip()
    kategori_id_raw = request.form.get("kategori_id", "").strip()
    stok_raw = request.form.get("stok", "0").strip()
    satuan = request.form.get("satuan", "").strip()
    lokasi_rak = request.form.get("lokasi_rak", "").strip().upper()
    stok_min_raw = request.form.get("stok_minimum", "5").strip()

    if not all([sku, nama, kategori_id_raw, satuan, lokasi_rak]):
        flash("Semua field wajib diisi untuk menambah barang.", "error")
        return redirect(url_for("index"))

    try:
        kategori_id = int(kategori_id_raw)
        stok = int(stok_raw)
        stok_minimum = int(stok_min_raw)
        if stok < 0 or stok_minimum < 0:
            raise ValueError("Nilai stok tidak boleh negatif.")
    except ValueError:
        flash("Stok dan stok minimum harus berupa angka >= 0.", "error")
        return redirect(url_for("index"))

    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO barang (
                        sku, nama, kategori_id, stok,
                        satuan, lokasi_rak, stok_minimum
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING id;
                    """,
                    (
                        sku,
                        nama,
                        kategori_id,
                        stok,
                        satuan,
                        lokasi_rak,
                        stok_minimum,
                    ),
                )
                barang_id = cur.fetchone()[0]
                if stok > 0:
                    cur.execute(
                        """
                        INSERT INTO transaksi_stok (
                            barang_id, tipe, jumlah, catatan
                        )
                        VALUES (%s, 'masuk', %s, %s);
                        """,
                        (barang_id, stok, "Stok awal saat input barang baru"),
                    )
            conn.commit()
        flash(f"Barang {sku} ({nama}) berhasil ditambahkan.", "success")
    except psycopg2.errors.UniqueViolation:
        flash(f"Gagal: SKU '{sku}' sudah terdaftar di gudang.", "error")
    except psycopg2.Error:
        flash("Gagal menyimpan barang ke database.", "error")

    return redirect(url_for("index"))


@app.route("/transaksi", methods=["POST"])
def catat_transaksi():
    """Mencatat transaksi stok masuk/keluar secara atomik di PostgreSQL."""
    barang_id_raw = request.form.get("barang_id", "").strip()
    tipe = request.form.get("tipe", "").strip().lower()
    jumlah_raw = request.form.get("jumlah", "").strip()
    catatan = request.form.get("catatan", "").strip()

    if tipe not in ("masuk", "keluar"):
        flash("Tipe transaksi harus 'masuk' atau 'keluar'.", "error")
        return redirect(url_for("index"))

    try:
        barang_id = int(barang_id_raw)
        jumlah = int(jumlah_raw)
        if jumlah <= 0:
            raise ValueError("Jumlah harus lebih dari 0.")
    except ValueError:
        flash("Pilih barang yang valid dan jumlah harus > 0.", "error")
        return redirect(url_for("index"))

    try:
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Kunci baris barang (FOR UPDATE) agar stok aman dari race
                cur.execute(
                    """
                    SELECT id, sku, nama, stok, satuan
                    FROM barang
                    WHERE id = %s
                    FOR UPDATE;
                    """,
                    (barang_id,),
                )
                item = cur.fetchone()
                if not item:
                    flash("Barang tidak ditemukan.", "error")
                    return redirect(url_for("index"))

                if tipe == "keluar" and item["stok"] < jumlah:
                    flash(
                        f"Stok {item['sku']} tidak mencukupi "
                        f"(tersedia {item['stok']} {item['satuan']}).",
                        "error",
                    )
                    return redirect(url_for("index"))

                delta = jumlah if tipe == "masuk" else -jumlah
                cur.execute(
                    """
                    UPDATE barang
                    SET stok = stok + %s, updated_at = NOW()
                    WHERE id = %s;
                    """,
                    (delta, barang_id),
                )
                cur.execute(
                    """
                    INSERT INTO transaksi_stok (
                        barang_id, tipe, jumlah, catatan
                    )
                    VALUES (%s, %s, %s, %s);
                    """,
                    (barang_id, tipe, jumlah, catatan),
                )
            conn.commit()
        flash(
            f"Transaksi stok {tipe} untuk {item['sku']} "
            f"({jumlah} {item['satuan']}) berhasil dicatat.",
            "success",
        )
    except psycopg2.Error:
        flash("Gagal mencatat transaksi stok.", "error")

    return redirect(url_for("index"))


if __name__ == "__main__":
    bind_host = os.getenv("APP_BIND", "127.0.0.1")
    bind_port = int(os.getenv("APP_PORT", "8000"))
    app.run(host=bind_host, port=bind_port, debug=False)
