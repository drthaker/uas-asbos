-- Skema Database Sistem Manajemen Inventori Gudang (Kelompok 3 - ASBOS)
-- Dijalankan ke database inventori_gudang_db menggunakan user non-superuser: inventori_user
-- Menggunakan IF NOT EXISTS agar skrip bersifat idempoten (aman dijalankan ulang).

CREATE TABLE IF NOT EXISTS kategori (
    id SERIAL PRIMARY KEY,
    nama VARCHAR(100) NOT NULL UNIQUE,
    deskripsi TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS barang (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE,
    nama VARCHAR(150) NOT NULL,
    kategori_id INTEGER NOT NULL REFERENCES kategori(id) ON DELETE RESTRICT,
    stok INTEGER NOT NULL DEFAULT 0 CHECK (stok >= 0),
    satuan VARCHAR(30) NOT NULL,
    lokasi_rak VARCHAR(50) NOT NULL,
    stok_minimum INTEGER NOT NULL DEFAULT 5 CHECK (stok_minimum >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transaksi_stok (
    id SERIAL PRIMARY KEY,
    barang_id INTEGER NOT NULL REFERENCES barang(id) ON DELETE CASCADE,
    tipe VARCHAR(10) NOT NULL CHECK (tipe IN ('masuk', 'keluar')),
    jumlah INTEGER NOT NULL CHECK (jumlah > 0),
    catatan TEXT DEFAULT '',
    waktu TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indeks untuk mempercepat filter kategori dan riwayat transaksi terbaru
CREATE INDEX IF NOT EXISTS idx_barang_kategori_id ON barang(kategori_id);
CREATE INDEX IF NOT EXISTS idx_transaksi_barang_waktu ON transaksi_stok(barang_id, waktu DESC);
