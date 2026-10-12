-- =====================================================================
-- SOAL 2 UTS - 01_select_for_update.sql  (CUPLIKAN KODE / SNIPPET)
-- Teknik 1: PESSIMISTIC LOCKING - kunci baris item lebih dulu.
--
-- PERINGATAN: ini cuplikan ilustrasi untuk kode aplikasi (kasir),
-- dirancang sebagai urutan BEGIN ... COMMIT. Bukan skrip uji; untuk
-- demo yang benar-benar dijalankan, lihat demo_race.py.
--
-- Urutan eksekusi pada stok tersisa 1 unit:
--   T1: BEGIN; SELECT ... FOR UPDATE  -> MENDAPATKAN kunci baris BRG001
--   T2: BEGIN; SELECT ... FOR UPDATE  -> MENUNGGU kunci T1
--   T1: cek stok=1 (lolos); INSERT SALE 1; COMMIT  -> stok = 0
--   T2: (lanjut) membaca stok TERBARU = 0 -> TOLAK, ROLLBACK
-- =====================================================================

-- Langkah 1: buka transaksi & kunci baris item
BEGIN;
SELECT stock_qty
FROM inventory_items
WHERE item_id = 'BRG001'
FOR UPDATE;           -- baris terkunci sampai COMMIT/ROLLBACK

-- Langkah 2: aplikasi memeriksa stok hasil SELECT di atas
--   stok = 1, qty diminta = 1, stok cukup -> lanjut
--   (pemeriksaan dilakukan di aplikasi, TIDAK di frontend saja)

-- Langkah 3: catat transaksi (trigger memperbarui stok & jurnal otomatis)
INSERT INTO inventory_transactions (item_id, trx_type, qty)
VALUES ('BRG001', 'SALE', 1);

-- Langkah 4: simpan -> kunci dilepas, transaksi kedua lanjut & melihat
-- stok = 0 sehingga ditolak
COMMIT;

-- ---------------------------------------------------------------------
-- Versi satu pernyataan (aman untuk procedure/panggilan dari aplikasi):
-- selesai atau gagal total, tanpa jendela antara cek dan tulis.
-- ---------------------------------------------------------------------
-- BEGIN;
-- UPDATE inventory_items
--    SET stock_qty = stock_qty - 1
--  WHERE item_id = 'BRG001' AND stock_qty >= 1;
-- -- periksa jumlah baris terdampak:
-- GET DIAGNOSTICS v_affected = ROW_COUNT;  -- v_affected = 0 -> tolak di aplikasi
-- COMMIT;
