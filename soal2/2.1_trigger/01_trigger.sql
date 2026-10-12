-- =====================================================================
-- SOAL 2 UTS - 01_trigger.sql
-- FUNCTION + TRIGGER: trg_update_stock_and_journal
-- (BAGIAN INTI: hanya otomasi mutasi stok; jurnal GL ada di file BONUS
--  03_bonus_journal.sql yang memakai nama fungsi yang sama versi jurnal)
--
-- Pilihan: AFTER INSERT FOR EACH ROW.
--   Alasan: (1) trx_id SERIAL baru terisi SETELAH baris disimpan, jadi
--   hanya dalam AFTER INSERT NEW.trx_id memiliki nilai (dibutuhkan
--   referensi jurnal di 03_bonus_journal.sql); (2) CHECK/FK pada
--   inventory_transactions dievaluasi lebih dulu, sehingga fungsi hanya
--   memproses baris yang sudah sah; (3) RAISE EXCEPTION di AFTER trigger
--   tetap membatalkan SELURUH transaksi (statement + koneksi), sehingga
--   baris inventory_transactions tidak tersimpan.
-- ---------------------------------------------------------------------
-- ASUSI SEMANTIK qty (dipertahankan di seluruh soal2):
--   PURCHASE  : qty > 0  -> stock_qty = stock_qty + qty
--   SALE      : qty > 0  -> stock_qty = stock_qty - qty
--   ADJUSTMENT: qty BERTANDA (signed), positif = tambah, negatif =
--               kurang, 0 = ditolak
-- =====================================================================

CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_item      inventory_items%ROWTYPE;  -- baris item terkunci FOR UPDATE
    v_qty       INT := NEW.qty;
    v_delta     INT := 0;                 -- perubahan stok (bertanda)
BEGIN
    -- (d) Anti concurrency: kunci baris item DULU, baru baca & tulis.
    --     Ini mencegah pola "baca stok -> cek di aplikasi -> tulis".
    --     Transaksi lain yang menyentuh item sama akan MENUNGGU kunci ini,
    --     sehingga setelah dilanjutkan mereka membaca stok TERBARU.
    SELECT *
    INTO v_item
    FROM inventory_items
    WHERE item_id = NEW.item_id
    FOR UPDATE;

    -- (d) item_id tidak ditemukan -> pesan jelas
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ITEM TIDAK DITEMUKAN: item_id % tidak ada di inventory_items', NEW.item_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Validasi qty + hitung perubahan stok sesuai tipe transaksi
    CASE NEW.trx_type
        WHEN 'PURCHASE' THEN
            -- (a) validasi dasar: PURCHASE wajib qty > 0
            IF v_qty <= 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: PURCHASE harus qty > 0 (diberikan %)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := v_qty;                    -- tambah stok
        WHEN 'SALE' THEN
            -- (a) validasi dasar: SALE wajib qty > 0
            IF v_qty <= 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: SALE harus qty > 0 (diberikan %)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := -v_qty;                   -- kurang stok
        WHEN 'ADJUSTMENT' THEN
            -- (a) ADJUSTMENT bertanda: boleh negatif, TIDAK boleh 0
            IF v_qty = 0 THEN
                RAISE EXCEPTION 'QTY TIDAK VALID: ADJUSTMENT tidak boleh 0 (diberikan %, qty bertanda)', v_qty
                    USING ERRCODE = 'check_violation';
            END IF;
            v_delta := v_qty;                    -- bertanda (+/-)
        ELSE
            -- pertahanan tambahan (CHECK di DDL sudah membatasi,
            -- tapi fungsi juga harus mandiri)
            RAISE EXCEPTION 'TIPE TRANSAKSI TIDAK DIKENAL: %', NEW.trx_type
                USING ERRCODE = 'check_violation';
    END CASE;

    -- (b) Anti-negative inventory: hasil stok akhir tidak boleh < 0
    IF v_item.stock_qty + v_delta < 0 THEN
        RAISE EXCEPTION
            'STOK TIDAK MENCUKUPI: item_id %, stok tersedia %, qty diminta %, stok menjadi %. Transaksi ditolak (ROLLBACK).',
            v_item.item_id, v_item.stock_qty, v_qty, v_item.stock_qty + v_delta
            USING ERRCODE = 'check_violation';
    END IF;

    -- (a)(c) Update stok secara atomik pada baris yang sudah dikunci
    UPDATE inventory_items
       SET stock_qty = stock_qty + v_delta
     WHERE item_id = v_item.item_id;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trg_update_stock_and_journal()
IS 'SOAL2 inti: memutakhirkan inventory_items.stock_qty otomatis saat INSERT inventory_transactions. Mengunci baris item (FOR UPDATE) untuk keamanan concurrency, menolak stok negatif, dan memvalidasi qty. Versi jurnal GL ada di 03_bonus_journal.sql.';

-- Trigger per baris (idempoten)
DROP TRIGGER IF EXISTS trg_update_stock_and_journal ON inventory_transactions;
CREATE TRIGGER trg_update_stock_and_journal
AFTER INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();

COMMENT ON TRIGGER trg_update_stock_and_journal ON inventory_transactions
IS 'Trigger AFTER INSERT: setiap transaksi persediaan langsung memperbarui stok fisik dan menolak stok negatif di level database.';
