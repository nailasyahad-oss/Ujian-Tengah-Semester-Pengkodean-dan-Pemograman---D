-- =====================================================================
-- SOAL 2 UTS - 03_bonus_journal.sql  (BAGIAN BONUS)
-- Perluas trigger (nama fungsi & trigger TETAP sama) agar setiap mutasi
-- persediaan otomatis membuat jurnal general ledger berpasangan.
-- Jalankan SETELAH 00 -> 01 -> 02.
--
-- STRUKTUR JURNAL (asingkan: satu baris jurnal = satu pasangan D/K):
--   PURCHASE   : D Persediaan Barang Dagangan / K Kas
--               (nilai = qty x unit_cost)
--   SALE       : D Beban Pokok Pendapatan (HPP) / K Persediaan Barang Dagangan
--               (nilai = qty x unit_cost; pure HPP perpetual -
--                pengakuan pendapatan penjualan di luar cakupan)
--   ADJUSTMENT : qty > 0 (selisih lebih) : D Persediaan / K Selisih Persediaan
--               qty < 0 (selisih kurang): D Selisih Persediaan / K Persediaan
--
-- ASUSI BIAYA:
--   * Menggunakan unit_cost yang tersimpan di inventory_items (statis).
--   * TIDADA FIFO/LIFO/average bergerak -> keterbatasan disengaja;
--     bila butuh perhitungan biaya dinamis, saldo biaya harus dihitung
--     per lapisan (layer) pada tabel pendukung (di luar tiga tabel inti).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabel ringan untuk jurnal GL hasil otomasi (OPSIONAL/BONUS)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS gl_entries CASCADE;
CREATE TABLE gl_entries (
    entry_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trx_id        INT NOT NULL REFERENCES inventory_transactions(trx_id) ON DELETE CASCADE,
    account_name  VARCHAR(100) NOT NULL,
    debit         NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit        NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    entry_date    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_gl_entries_trx_id ON gl_entries(trx_id);

COMMENT ON TABLE gl_entries IS 'BONUS SOAL2: jurnal general ledger otomatis dari trigger persediaan (satu transaksi = 2 baris berpasangan).';
COMMENT ON COLUMN gl_entries.trx_id IS 'Referensi ke inventory_transactions.trx_id; ON DELETE CASCADE agar jurnal mengikuti hidup transaksi.';
COMMENT ON COLUMN gl_entries.debit IS 'Nominal debit >= 0. Total debit HARUS = total kredit per trx_id.';
COMMENT ON COLUMN gl_entries.credit IS 'Nominal kredit >= 0. Total debit HARUS = total kredit per trx_id.';

-- ---------------------------------------------------------------------
-- Fungsi versi jurnal (nama sama seperti 01_trigger.sql, di-extend)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_item   inventory_items%ROWTYPE;   -- baris item terkunci FOR UPDATE
    v_qty    INT := NEW.qty;
    v_delta  INT := 0;
    v_amount NUMERIC(15,2);
BEGIN
    -- (c) kunci baris item lebih dulu (aman concurrency)
    SELECT * INTO v_item
    FROM inventory_items
    WHERE item_id = NEW.item_id
    FOR UPDATE;

    -- (d) item_id tidak ditemukan
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ITEM TIDAK DITEMUKAN: item_id % tidak ada di inventory_items', NEW.item_id
            USING ERRCODE = 'no_data_found';
    END IF;

    CASE NEW.trx_type
        WHEN 'PURCHASE' THEN
            IF v_qty <= 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: PURCHASE harus qty > 0 (diberikan %)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := v_qty;
        WHEN 'SALE' THEN
            IF v_qty <= 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: SALE harus qty > 0 (diberikan %)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := -v_qty;
        WHEN 'ADJUSTMENT' THEN
            IF v_qty = 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: ADJUSTMENT tidak boleh 0 (diberikan %, qty bertanda)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := v_qty;
        ELSE
            RAISE EXCEPTION 'TIPE TRANSAKSI TIDAK DIKENAL: %', NEW.trx_type
                USING ERRCODE = 'check_violation';
    END CASE;

    -- (b) anti-negative: jika gagal, EXCEPTION sebelum jurnal ditulis
    --     (dan walau jurnal sudah ditulis pula, seluruh transaksi ROLLBACK)
    IF v_item.stock_qty + v_delta < 0 THEN
        RAISE EXCEPTION
            'STOK TIDAK MENCUKUPI: item_id %, stok tersedia %, qty diminta %, stok menjadi %. Transaksi ditolak (ROLLBACK).',
            v_item.item_id, v_item.stock_qty, v_qty, v_item.stock_qty + v_delta
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE inventory_items
       SET stock_qty = stock_qty + v_delta
     WHERE item_id = v_item.item_id;

    -- NILAI JURNAL = qty x unit_cost dari baris item yang terkunci
    v_amount := ABS(v_qty) * v_item.unit_cost;

    IF NEW.trx_type = 'PURCHASE' THEN
        -- Pembelian diasumsikan tunai (alternatif: K Utang Usaha)
        INSERT INTO gl_entries (trx_id, account_name, debit, credit) VALUES
            (NEW.trx_id, 'Persediaan Barang Dagangan', v_amount, 0),
            (NEW.trx_id, 'Kas',                          0, v_amount);
    ELSIF NEW.trx_type = 'SALE' THEN
        -- Pengakuan HPP (perpetual)
        INSERT INTO gl_entries (trx_id, account_name, debit, credit) VALUES
            (NEW.trx_id, 'Beban Pokok Pendapatan (HPP)', v_amount, 0),
            (NEW.trx_id, 'Persediaan Barang Dagangan',  0, v_amount);
    ELSIF NEW.trx_type = 'ADJUSTMENT' THEN
        IF v_qty > 0 THEN
            -- selisih lebih (stock gain)
            INSERT INTO gl_entries (trx_id, account_name, debit, credit) VALUES
                (NEW.trx_id, 'Persediaan Barang Dagangan', v_amount, 0),
                (NEW.trx_id, 'Selisih Persediaan',        0, v_amount);
        ELSE
            -- selisih kurang (shrinkage/rusak/loss)
            INSERT INTO gl_entries (trx_id, account_name, debit, credit) VALUES
                (NEW.trx_id, 'Selisih Persediaan',         v_amount, 0),
                (NEW.trx_id, 'Persediaan Barang Dagangan', 0, v_amount);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_stock_and_journal ON inventory_transactions;
CREATE TRIGGER trg_update_stock_and_journal
AFTER INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();

-- =====================================================================
-- UJI BONUS: jurnal otomatis + keseimbangan + rollback
-- =====================================================================
\echo ''
\echo '====================================================================='
\echo 'BONUS - Uji jurnal otomatis + keseimbangan D=K + rollback'
\echo '====================================================================='

-- Pastikan baseline BRG001 kembali 10 (skenario uji inti sudah dijalankan)
UPDATE inventory_items SET stock_qty = 10 WHERE item_id = 'BRG001';

DO $$
DECLARE
    v_stok INT;
    v_hasil JSON;
BEGIN
    -- PURCHASE 5 (stok 10 -> 15, nilai 5 x 50.000 = 250.000)
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'PURCHASE', 5);
    -- SALE 3 (stok 15 -> 12, nilai 3 x 50.000 = 150.000)
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', 3);
    -- ADJUSTMENT +2 (stok 12 -> 14, nilai 100.000)
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', 2);
    -- ADJUSTMENT -4 (stok 14 -> 10, nilai 200.000)
    INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'ADJUSTMENT', -4);

    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'BONUS skenario normal: stok akhir % (harap 10) -> %',
        v_stok, CASE WHEN v_stok = 10 THEN 'PASS' ELSE 'FAIL' END;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BONUS skenario normal FAIL: %', SQLERRM;
END $$;

\echo ''
\echo '--- (8) Isi gl_entries dan keseimbangan SUM(debit)=SUM(credit) per transaksi'
SELECT g.trx_id, i.item_id, t.trx_type, t.qty, g.account_name, g.debit, g.credit
FROM gl_entries g
JOIN inventory_transactions t ON t.trx_id = g.trx_id
JOIN inventory_items i ON i.item_id = t.item_id
ORDER BY g.trx_id, g.entry_id;

SELECT trx_id,
       SUM(debit)  AS total_debit,
       SUM(credit) AS total_credit,
       CASE WHEN SUM(debit) = SUM(credit) THEN 'SEIMBANG' ELSE 'TIDAK SEIMBANG' END AS status
FROM gl_entries
GROUP BY trx_id
ORDER BY trx_id;

\echo ''
\echo '--- (8) Nilai persediaan = stock_qty x unit_cost'
SELECT item_id, stock_qty, unit_cost, stock_qty * unit_cost AS nilai_persediaan
FROM inventory_items ORDER BY item_id;

\echo ''
\echo '--- BONUS: transaksi tidak seimbang stok TIDAK boleh menghasilkan jurnal'

-- reset ke stok 5 agar SALE 11 jelas gagal
UPDATE inventory_items SET stock_qty = 5 WHERE item_id = 'BRG001';

DO $$
DECLARE
    v_jml_gl_lama BIGINT;
    v_jml_gl_baru BIGINT;
    v_stok INT;
BEGIN
    SELECT COUNT(*) INTO v_jml_gl_lama FROM gl_entries;
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';
    RAISE NOTICE 'SEBELUM: stok = %, jml baris gl_entries = %', v_stok, v_jml_gl_lama;

    BEGIN
        INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001', 'SALE', 11);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'SALE 11 (stok 5) ditolak: %', SQLERRM;
    END;

    SELECT COUNT(*) INTO v_jml_gl_baru FROM gl_entries;
    SELECT stock_qty INTO v_stok FROM inventory_items WHERE item_id = 'BRG001';

    RAISE NOTICE 'SESUDAH: stok = %, jml baris gl_entries = % (harap tetap %)',
        v_stok, v_jml_gl_baru, v_jml_gl_lama;

    IF v_jml_gl_baru = v_jml_gl_lama AND v_stok = 5 THEN
        RAISE NOTICE 'BONUS rollback jurnal -> PASS (tidak ada jurnal yatim)';
    ELSE
        RAISE NOTICE 'BONUS rollback jurnal -> FAIL';
    END IF;
END $$;
