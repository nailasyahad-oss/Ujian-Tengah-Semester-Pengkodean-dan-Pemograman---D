-- =====================================================================
-- SOAL 2 UTS - 02_serializable_retry.sql  (CUPLIKAN KODE / SNIPPET)
-- Teknik 2: ISOLATION LEVEL SERIALIZABLE + KEWAJIBAN RETRY aplikasi.
--
-- Dengan SERIALIZABLE, PostgreSQL mendeteksi konflik pola:
--   "read (stok=1) -> transaksi lain UPDATE & COMMIT -> kita UPDATE/COMMIT"
-- Transaksi kita DITOLAK dengan SQLSTATE 40001 (serialization_failure).
-- Karena itu aplikasi WAJIB menangkap 40001 dan mengulang dari BEGIN.
--
-- PERINGATAN: cuplikan ilustrasi. Demo nyata: demo_race.py.
-- =====================================================================

-- ================== SISI APLIKASI (SQL) ==================
-- Transaksi A dan B sama-sama membaca stok = 1 (stok tersisa 1 unit):

-- --- Transaksi A (kasir 1) ---
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_qty FROM inventory_items WHERE item_id = 'BRG001';  -- A baca 1
-- (jeda: kasir 2 juga membaca 1 pada waktu bersamaan)
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001','SALE',1);
COMMIT;   -- A sukses, stok menjadi 0

-- --- Transaksi B (kasir 2) ---
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_qty FROM inventory_items WHERE item_id = 'BRG001';  -- B baca 1
-- kasir 2 lanjut menulis...
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001','SALE',1);
COMMIT;
-- >>> ERROR: could not serialize access due to read/write dependencies
--     among transactions  (SQLSTATE 40001) -> SELURUH TRANSAKSI B BATAL.

-- ================== KEWAJIBAN RETRY DI APLIKASI ==================
-- Pola retry (pseudocode):
--   for attempt in 1..MAX_RETRY:
--       BEGIN ISOLATION LEVEL SERIALIZABLE
--       stok = SELECT stock_qty ... FOR UPDATE(opsional) / atau tanpa kunci
--       IF stok < qty THEN
--           ROLLBACK; return "stok tidak cukup"     -- penolakan BERSIH
--       END IF
--       INSERT transaksi ...; COMMIT
--       ON SQLSTATE 40001: ROLLBACK; backoff; CONTINUE  -- ulangi dengan bacaan baru

-- Contoh retry loop konkret (Python + pg8000) tersedia di demo_race.py
-- bagian retry setelah 40001: bacaan baru melihat stok = 0 sehingga penjualan
-- ditolak secara EKSPLISIT, bukan gagal misterius.

-- ================== CATATAN ==================
-- * SERIALIZABLE menaikkan laju abort; batasi percobaan (mis. 3x) dan
--   gunakan backoff acak (mis. 50-200 ms).
-- * Untuk satu item sederhana, FOR UPDATE (teknik 1) atau UPDATE bersyarat
--   lebih murah karena tidak perlu retry.
