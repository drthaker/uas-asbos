-- Data awal (seed) Sistem Manajemen Inventori Gudang (Kelompok 3 - ASBOS)
-- Menggunakan ON CONFLICT DO NOTHING agar aman dijalankan lebih dari sekali.

INSERT INTO kategori (nama, deskripsi) VALUES
    ('Elektronik & IT', 'Perangkat komputer, jaringan, dan aksesoris elektronik gudang'),
    ('Alat Tulis Kantor', 'Perlengkapan administrasi, kertas, dan kebutuhan operasional'),
    ('Peralatan Gudang', 'Perlengkapan logistik, keselamatan kerja, dan alat bantu angkut'),
    ('Bahan Kemasan', 'Kardus, lakban, bubble wrap, dan label pengiriman')
ON CONFLICT (nama) DO NOTHING;

-- Sengaja menyertakan beberapa barang dengan stok <= stok_minimum
-- agar indikator "Stok Menipis" langsung terlihat saat pengujian dan live demo.
INSERT INTO barang (sku, nama, kategori_id, stok, satuan, lokasi_rak, stok_minimum)
VALUES
    (
        'ELK-001', 'Barcode Scanner Wireless 2D',
        (SELECT id FROM kategori WHERE nama = 'Elektronik & IT'),
        12, 'unit', 'RAK-A1', 5
    ),
    (
        'ELK-002', 'Printer Label Thermal 80mm',
        (SELECT id FROM kategori WHERE nama = 'Elektronik & IT'),
        3, 'unit', 'RAK-A2', 4
    ),
    (
        'ATK-001', 'Kertas Thermal Label 100x150mm',
        (SELECT id FROM kategori WHERE nama = 'Alat Tulis Kantor'),
        45, 'roll', 'RAK-B1', 15
    ),
    (
        'ATK-002', 'Spidol Permanen Hitam',
        (SELECT id FROM kategori WHERE nama = 'Alat Tulis Kantor'),
        8, 'pak', 'RAK-B2', 10
    ),
    (
        'GDG-001', 'Helm Keselamatan Proyek Kuning',
        (SELECT id FROM kategori WHERE nama = 'Peralatan Gudang'),
        18, 'pcs', 'RAK-C1', 6
    ),
    (
        'GDG-002', 'Sarung Tangan Kerja Anti-Slip',
        (SELECT id FROM kategori WHERE nama = 'Peralatan Gudang'),
        4, 'pasang', 'RAK-C2', 10
    ),
    (
        'KMS-001', 'Kardus Packing 40x30x30 cm',
        (SELECT id FROM kategori WHERE nama = 'Bahan Kemasan'),
        120, 'lembar', 'RAK-D1', 30
    ),
    (
        'KMS-002', 'Lakban Bening 48mm x 90m',
        (SELECT id FROM kategori WHERE nama = 'Bahan Kemasan'),
        6, 'roll', 'RAK-D2', 12
    )
ON CONFLICT (sku) DO NOTHING;

-- Isi riwayat transaksi awal hanya jika tabel transaksi_stok masih kosong
INSERT INTO transaksi_stok (barang_id, tipe, jumlah, catatan)
SELECT b.id, v.tipe, v.jumlah, v.catatan
FROM (
    VALUES
        ('ELK-001', 'masuk', 12, 'Penerimaan stok awal dari supplier PT Nusantara'),
        ('ELK-002', 'masuk', 5, 'Penerimaan awal printer label gudang'),
        ('ELK-002', 'keluar', 2, 'Distribusi ke meja packing zona timur'),
        ('KMS-001', 'masuk', 150, 'Restock kardus bulanan'),
        ('KMS-001', 'keluar', 30, 'Pengiriman paket order minggu pertama')
) AS v(sku, tipe, jumlah, catatan)
JOIN barang b ON b.sku = v.sku
WHERE NOT EXISTS (SELECT 1 FROM transaksi_stok LIMIT 1);
