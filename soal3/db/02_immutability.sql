-- =====================================================================
-- SOAL 3 UTS - 02_immutability.sql
-- Trigger pencegah UPDATE/DELETE pada header/line yang sudah POSTED/REVERSED
-- Hanya fungsi reverse_journal (dengan flag sesi) yang boleh mengubah status
-- PostgreSQL 14+
-- =====================================================================

-- =====================================================================
-- 1. FLAG SESI UNTUK IZIN REVERSAL (aman, tidak persistent)
-- =====================================================================
-- Fungsi reverse_journal akan meng-set:
--   SET LOCAL app.allow_reversal = 'on';
-- Trigger akan memeriksa current_setting('app.allow_reversal', TRUE) = 'on'
-- Flag ini hanya berlaku di transaksi yang sama (LOCAL), tidak bocor ke sesi lain.

-- =====================================================================
-- 2. TRIGGER PENCEGAH UPDATE/DELETE PADA journal_headers (POSTED/REVERSED)
-- =====================================================================
CREATE OR REPLACE FUNCTION enforce_journal_immutability_header()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_allow_reversal BOOLEAN := current_setting('app.allow_reversal', TRUE) = 'on';
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    -- Hanya berlaku untuk UPDATE dan DELETE
    IF TG_OP = 'UPDATE' THEN
        v_old_status := OLD.status_posting;
        v_new_status := NEW.status_posting;

        -- Jika status lama POSTED/REVERSED, periksa izin
        IF v_old_status IN ('POSTED','REVERSED') THEN
            -- Tanpa flag allow_reversal: TOLAK semua perubahan
            IF NOT v_allow_reversal THEN
                RAISE EXCEPTION
                    'JURNAL IMMUTABLE: Tidak boleh mengubah header berstatus % (hanya POSTED->REVERSED via reverse_journal diperbolehkan).',
                    v_old_status
                USING ERRCODE = 'object_not_in_prerequisite_state';
            END IF;

            -- Dengan flag allow_reversal (hanya reverse_journal SECURITY DEFINER):
            -- izinkan perubahan field yang relevan dengan reversal:
            --   status_posting (POSTED->REVERSED), reversed_by_header_id, hash_checksum.
            -- Field lain (no_bukti, tanggal, deskripsi, created_by/at, posted_by/at,
            -- reversal_of_header_id) TETAP tidak boleh berubah.
            IF OLD.nomor_referensi IS DISTINCT FROM NEW.nomor_referensi
               OR OLD.tanggal_transaksi IS DISTINCT FROM NEW.tanggal_transaksi
               OR OLD.deskripsi IS DISTINCT FROM NEW.deskripsi
               OR OLD.created_by IS DISTINCT FROM NEW.created_by
               OR OLD.created_at IS DISTINCT FROM NEW.created_at
               OR OLD.posted_by IS DISTINCT FROM NEW.posted_by
               OR OLD.posted_at IS DISTINCT FROM NEW.posted_at
               OR OLD.reversal_of_header_id IS DISTINCT FROM NEW.reversal_of_header_id THEN
                RAISE EXCEPTION
                    'JURNAL IMMUTABLE: Field non-status pada header % tidak boleh diubah.',
                    v_old_status
                USING ERRCODE = 'object_not_in_prerequisite_state';
            END IF;
        END IF;

    ELSIF TG_OP = 'DELETE' THEN
        -- DELETE header POSTED/REVERSED SELALU ditolak, meski flag allow_reversal on.
        -- Storno tidak menghapus jurnal asal, hanya menandai REVERSED.
        IF OLD.status_posting IN ('POSTED','REVERSED') THEN
            RAISE EXCEPTION
                'JURNAL IMMUTABLE: Tidak boleh menghapus header berstatus % (koreksi hanya lewat reverse_journal).',
                OLD.status_posting
            USING ERRCODE = 'object_not_in_prerequisite_state';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_immutable_journal_header ON journal_headers;
CREATE TRIGGER trg_immutable_journal_header
BEFORE UPDATE OR DELETE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION enforce_journal_immutability_header();

COMMENT ON TRIGGER trg_immutable_journal_header ON journal_headers
IS 'Mencegah UPDATE/DELETE pada header POSTED/REVERSED. Hanya POSTED->REVERSED via reverse_journal (flag sesi) yang diperbolehkan.';

-- =====================================================================
-- 3. TRIGGER PENCEGAH UPDATE/DELETE/INSERT PADA journal_lines (header POSTED/REVERSED)
-- =====================================================================
CREATE OR REPLACE FUNCTION enforce_journal_immutability_lines()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_header_status TEXT;
    v_allow_reversal BOOLEAN := current_setting('app.allow_reversal', TRUE) = 'on';
BEGIN
    -- Ambil status header induk
    SELECT status_posting INTO v_header_status
    FROM journal_headers
    WHERE id = COALESCE(NEW.header_id, OLD.header_id);

    -- Jika header POSTED/REVERSED, cek izin
    IF v_header_status IN ('POSTED','REVERSED') THEN
        IF TG_OP = 'INSERT' THEN
            -- Hanya izinkan INSERT line baru saat reversal (flag on),
            -- yaitu saat reverse_journal membuat line jurnal pembalik.
            IF NOT v_allow_reversal THEN
                RAISE EXCEPTION
                    'JURNAL IMMUTABLE: Tidak boleh menambah line ke header % (hanya saat reversal via RPC).',
                    v_header_status
                USING ERRCODE = 'object_not_in_prerequisite_state';
            END IF;
        ELSE
            -- UPDATE dan DELETE line pada header POSTED/REVERSED SELALU ditolak,
            -- meski flag allow_reversal on. Storno tidak mengubah line jurnal asal.
            RAISE EXCEPTION
                'JURNAL IMMUTABLE: Tidak boleh mengubah/menghapus line pada header %.',
                v_header_status
            USING ERRCODE = 'object_not_in_prerequisite_state';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_immutable_journal_lines ON journal_lines;
CREATE TRIGGER trg_immutable_journal_lines
BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION enforce_journal_immutability_lines();

COMMENT ON TRIGGER trg_immutable_journal_lines ON journal_lines
IS 'Mencegah INSERT/UPDATE/DELETE line pada header POSTED/REVERSED. Hanya saat reversal (flag sesi) yang diperbolehkan.';

-- =====================================================================
-- 4. FUNGSI BANTU UNTUK MENGECEK IMMUTABILITY (dipakai RPC)
-- =====================================================================
CREATE OR REPLACE FUNCTION is_header_mutable(p_header_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status_posting INTO v_status FROM journal_headers WHERE id = p_header_id;
    RETURN v_status = 'DRAFT';
END;
$$;

COMMENT ON FUNCTION is_header_mutable(BIGINT)
IS 'TRUE jika header masih DRAFT (boleh diubah/hapus). FALSE jika POSTED/REVERSED.';

-- =====================================================================
-- CATATAN DESAIN:
-- - Flag sesi (app.allow_reversal) bersifat LOCAL: hanya berlaku di transaksi RPC reverse_journal.
-- - Trigger BEFORE memastikan penolakan sebelum perubahan terjadi.
-- - Error code 'object_not_in_prerequisite_state' (55000) cocok untuk kondisi state tidak valid.
-- - Hanya RPC reverse_journal (SECURITY DEFINER) yang bisa set flag dan memodifikasi POSTED.
-- =====================================================================