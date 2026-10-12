-- =====================================================================
-- SOAL 2 UTS - 02_test_trigger.sql
-- Uji positif & negatif trigger INTI (stok). Jalankan: 00 -> 01 -> 02
-- Setiap kasus negatif dibungkus DO $$ ... EXCEPTION $$ supaya
-- errornya dicatat dan skrip tetap berjalan.
-- =====================================================================

\echo ''
\echo '====================================================================='
\echo 'TAHAP 1 - SEED: item BRG001 stok 10, unit_cost 50.000'
\echo '====================================================================='
SELECT item_id, item_name, stock_qty, unit_cost FROM inventory_items ORDER BY item_id;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 2 - POSITIF: PURCHASE 5 -> stok 15'
\echo '====================================================================='
DO $$
DECLARE v_stok INT;
BEGIN
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'Stok sebelum: %', v_stok;

    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'PURCHASE', 5);

    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'POSITIF PURCHASE 5: stok sesudah = % (harap 15) -> %',
        v_stok, CASE WHEN v_stok = 15 THEN 'PASS' ELSE 'FAIL' END;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'POSITIF PURCHASE 5 FAIL: %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 3 - POSITIF: SALE 3 -> stok 12'
\echo '====================================================================='
DO $$
DECLARE v_stok INT;
BEGIN
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', 3);
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'POSITIF SALE 3: stok sesudah = % (harap 12) -> %',
        v_stok, CASE WHEN v_stok = 12 THEN 'PASS' ELSE 'FAIL' END;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'POSITIF SALE 3 FAIL: %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 4 - POSITIF: ADJUSTMENT +2 -> 14, lalu ADJUSTMENT -4 -> 10'
\echo '====================================================================='
DO $$
DECLARE v_stok INT;
BEGIN
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', 2);
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'POSITIF ADJUSTMENT +2: stok = % (harap 14) -> %', v_stok,
        CASE WHEN v_stok = 14 THEN 'PASS' ELSE 'FAIL' END;

    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', -4);
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'POSITIF ADJUSTMENT -4: stok = % (harap 10) -> %', v_stok,
        CASE WHEN v_stok = 10 THEN 'PASS' ELSE 'FAIL' END;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'POSITIF ADJUSTMENT FAIL: %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 5 - NEGATIF: SALE 11 saat stok 10 (harus ERROR, stok tetap 10)'
\echo '====================================================================='
DO $$
DECLARE
    v_stok_lama INT;
    v_stok_baru INT;
    v_jml_trx_lama BIGINT;
    v_jml_trx_baru BIGINT;
BEGIN
    SELECT stock_qty INTO v_stok_lama FROM inventory_items WHERE item_id = 'BRG001';
    SELECT COUNT(*) INTO v_jml_trx_lama FROM inventory_transactions;

    RAISE NOTICE 'SEBELUM : stok = %, jumlah baris trx = %', v_stok_lama, v_jml_trx_lama;
    RAISE NOTICE 'Mencoba INSERT SALE 11 ...';
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', 11);

    RAISE NOTICE 'NEGATIF SALE 11 FAIL: seharusnya ERROR!';
EXCEPTION WHEN OTHERS THEN
    SELECT stock_qty INTO v_stok_baru FROM inventory_items WHERE item_id = 'BRG001';
    SELECT COUNT(*) INTO v_jml_trx_baru FROM inventory_transactions WHERE item_id = 'BRG001';
    RAISE NOTICE 'Error: %', SQLERRM;
    RAISE NOTICE 'SESUDAH : stok = % (harap 10), trx BRG001 = % (harap 4)', v_stok_baru, v_jml_trx_baru;
    IF v_stok_baru = 10 AND v_jml_trx_baru = v_jml_trx_lama THEN
        RAISE NOTICE 'NEGATIF SALE 11 -> PASS (stok & jumlah trx tidak berubah)';
    ELSE
        RAISE NOTICE 'NEGATIF SALE 11 -> FAIL';
    END IF;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 6 - NEGATIF: qty <= 0 pada SALE dan PURCHASE'
\echo '====================================================================='
DO $$
DECLARE v_jml INT;
BEGIN
    -- SALE dengan qty 0
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', 0);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF SALE qty=0 -> PASS: %', SQLERRM;
    END;

    -- SALE dengan qty -3
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', -3);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF SALE qty=-3 -> PASS: %', SQLERRM;
    END;

    -- PURCHASE dengan qty 0
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'PURCHASE', 0);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF PURCHASE qty=0 -> PASS: %', SQLERRM;
    END;

    -- PURCHASE dengan qty -10
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'PURCHASE', -10);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF PURCHASE qty=-10 -> PASS: %', SQLERRM;
    END;

    -- ADJUSTMENT qty 0 (bertanda tapi 0 ditolak)
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', 0);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF ADJUSTMENT qty=0 -> PASS: %', SQLERRM;
    END;

    SELECT COUNT(*) INTO v_jml FROM inventory_transactions;
    RAISE NOTICE 'Sesudah uji qty tidak valid: jumlah total trx = % (semua ditolak)', v_jml;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TAHAP 6 FAIL (tak terduga): %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 7 - NEGATIF: item_id tidak ditemukan + ADJUSTMENT memaksa stok negatif'
\echo '====================================================================='
DO $$
DECLARE
    v_jml_lama BIGINT;
    v_jml_baru BIGINT;
    v_stok INT;
BEGIN
    SELECT COUNT(*) INTO v_jml_lama FROM inventory_transactions;
    RAISE NOTICE 'Jumlah trx sebelum uji: %', v_jml_lama;

    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('TIDAKADA', 'PURCHASE', 5);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF item tidak ditemukan -> PASS: %', SQLERRM;
    END;

    -- ADJUSTMENT -100 saat stok hanya 10 -> harus ditolak (stok akhir -90)
    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', -100);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF ADJUSTMENT -100 (stok 10) -> PASS: %', SQLERRM;
    END;

    SELECT COUNT(*) INTO v_jml_baru FROM inventory_transactions;
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'Jumlah trx sesudah uji: %, stok BRG001 = % (harap tetap 10)', v_jml_baru, v_stok;
    IF v_jml_baru = v_jml_lama AND v_stok = 10 THEN
        RAISE NOTICE 'TAHAP 7 -> PASS (tidak ada baris trx baru, stok utuh)';
    ELSE
        RAISE NOTICE 'TAHAP 7 -> FAIL';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TAHAP 7 FAIL (tak terduga): %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 7b - NEGATIF: item_id tidak ditemukkan (jalur fungsi kita)'
\echo '          (FK sementara dimatikan via dynamic SQL agar pesan fungsi'
\echo '           yang terlihat; ENABLE lagi di akhir, transaksi utuh)'
\echo '====================================================================='
DO $$
DECLARE
    v_fk_trigger TEXT;
BEGIN
    -- Ambil nama trigger FK internal (RI_ConstraintTrigger_*)
    SELECT tg.tgname INTO v_fk_trigger
    FROM pg_trigger tg
    JOIN pg_constraint c ON c.oid = tg.tgconstraint
    WHERE tg.tgrelid = 'inventory_transactions'::regclass
      AND c.contype = 'f'
    LIMIT 1;

    -- Matikan sementara HANYA trigger FK (bukan trigger kita)
    EXECUTE format('ALTER TABLE inventory_transactions DISABLE TRIGGER %I', v_fk_trigger);
    RAISE NOTICE 'Trigger FK "%" dimatikan sementara.', v_fk_trigger;

    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty)
        VALUES ('TIDAKADA', 'PURCHASE', 5);
        RAISE NOTICE 'NEGATIF 7b FAIL: item tak ada seharusnya DITOLAK fungsi kita!';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'NEGATIF 7b PASS (ditolak oleh fungsi kita): %', SQLERRM;
    END;

    -- Hidupkan kembali (walau blok gagal, ROLLBACK otomatis memulihkan)
    EXECUTE format('ALTER TABLE inventory_transactions ENABLE TRIGGER %I', v_fk_trigger);
    RAISE NOTICE 'Trigger FK "%" dihidupkan kembali.', v_fk_trigger;
END $$;

\echo ''
\echo '====================================================================='
\echo 'TAHAP 8 - BUKTI AKHIR: mutasi stok & nilai persediaan'
\echo '====================================================================='
-- Riwayat mutasi BRG001
SELECT trx_id, item_id, trx_type, qty, trx_date
FROM inventory_transactions
WHERE item_id = 'BRG001'
ORDER BY trx_id;

-- Stok & nilai persediaan = stock_qty * unit_cost
SELECT item_id, item_name, stock_qty, unit_cost, stock_qty * unit_cost AS nilai_persediaan
FROM inventory_items
ORDER BY item_id;

-- Ringkasan per tipe transaksi (kendali silang: TOTAL SEMUA = STOK AKHIR)
SELECT COALESCE(SUM(CASE trx_type WHEN 'PURCHASE' THEN qty WHEN 'SALE' THEN -qty WHEN 'ADJUSTMENT' THEN qty END), 0) AS net_moved
FROM inventory_transactions
WHERE item_id = 'BRG001';
