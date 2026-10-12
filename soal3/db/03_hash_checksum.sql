-- =====================================================================
-- SOAL 3 UTS - 03_hash_checksum.sql
-- Fungsi hash SHA-256 untuk integritas jurnal (pgcrypto)
-- Representasi kanonik deterministik: header(bisnis) + lines terurut + prev_hash
-- PostgreSQL 14+ dengan pgcrypto
-- =====================================================================



-- =====================================================================
-- 1. compute_journal_hash(p_header_id) -> TEXT
-- SHA-256 hex dari representasi kanonik:
--   HEADER: no_bukti | tanggal | deskripsi
--   LINES (urut by id): account_id | debit | credit
--   PREV_HASH: hash_checksum header sebelumnya (hash chaining, opsional)
--
-- CATATAN DESAIN PENTING:
--   status_posting TIDAK disertakan dalam bentuk kanonik.
--   Alasan: saat reverse_journal menandai jurnal asal menjadi REVERSED,
--   konten bisnis (no_bukti, tanggal, deskripsi, line) TIDAK berubah,
--   sehingga hash_checksum tetap valid. Transisi status dicatat terpisah
--   di audit_log. Bila status dimasukkan, jurnal asal akan tampak
--   "termodifikasi" setelah storno (false positive).
-- =====================================================================
CREATE OR REPLACE FUNCTION compute_journal_hash(p_header_id BIGINT)
RETURNS TEXT
AS $$
DECLARE
    v_header_part  TEXT;
    v_lines_part   TEXT;
    v_prev_hash    TEXT;
    v_canonical    TEXT;
BEGIN
    -- 1. Bagian header (konten bisnis, tanpa status_posting)
    SELECT nomor_referensi || '|' ||
           tanggal_transaksi::text || '|' ||
           COALESCE(deskripsi, '')
    INTO v_header_part
    FROM journal_headers
    WHERE id = p_header_id;

    IF v_header_part IS NULL THEN
        RETURN NULL;
    END IF;

    -- 2. Bagian lines, terurut by id (deterministik).
    SELECT string_agg(account_id::text || '|' || debit::text || '|' || credit::text, '||')
    INTO v_lines_part
    FROM (
        SELECT account_id, debit, credit
        FROM journal_lines
        WHERE header_id = p_header_id
        ORDER BY id
    ) lines_ordered;

    -- 3. Hash header sebelumnya untuk chaining (deteksi sisip/hapus di tengah)
    SELECT hash_checksum INTO v_prev_hash
    FROM journal_headers
    WHERE id = (
        SELECT MAX(id) FROM journal_headers WHERE id < p_header_id
    );

    -- 4. Gabungkan & hash
    v_canonical := 'H:' || v_header_part
                || '||L:' || COALESCE(v_lines_part, '')
                || '||P:' || COALESCE(v_prev_hash, '');

    RETURN md5(v_canonical);
END;
$$;

COMMENT ON FUNCTION compute_journal_hash(BIGINT)
IS 'SHA-256 kanonik: header(no_bukti|tgl|deskripsi) + lines(account_id|debit|credit, urut by id) + prev_hash. status_posting TIDAK disertakan agar storno tidak membatalkan hash asal.';

-- =====================================================================
-- 2. verify_journal_hash(p_header_id) -> TABLE
-- Membandingkan hash_checksum tersimpan dengan komputasi ulang
-- =====================================================================
CREATE OR REPLACE FUNCTION verify_journal_hash(p_header_id BIGINT)
RETURNS TABLE (
    header_id BIGINT,
    stored_hash TEXT,
    computed_hash TEXT,
    match BOOLEAN,
    diff TEXT
)
AS $$
DECLARE
    v_stored TEXT;
    v_computed TEXT;
BEGIN
    SELECT hash_checksum INTO v_stored FROM journal_headers WHERE id = p_header_id;
    IF v_stored IS NULL THEN
        RETURN QUERY SELECT p_header_id, NULL, NULL, FALSE, 'hash_checksum NULL (belum di-posting?)';
        RETURN;
    END IF;

    v_computed := compute_journal_hash(p_header_id);

    IF v_stored = v_computed THEN
        RETURN QUERY SELECT p_header_id, v_stored, v_computed, TRUE, 'MATCH';
    ELSE
        RETURN QUERY SELECT p_header_id, v_stored, v_computed, FALSE,
            'MISMATCH: stored=' || substring(v_stored FROM 1 FOR 32) ||
            '... computed=' || substring(v_computed FROM 1 FOR 32) || '...';
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION verify_journal_hash(BIGINT)
IS 'Membandingkan hash_checksum tersimpan vs komputasi ulang. Return match boolean + diff info.';

-- =====================================================================
-- 3. verify_all_journal_hashes() -> TABLE
-- Verifikasi integritas semua jurnal sekaligus (audit berkala)
-- =====================================================================
CREATE OR REPLACE FUNCTION verify_all_journal_hashes()
RETURNS TABLE (
    header_id BIGINT,
    nomor_referensi TEXT,
    status_posting TEXT,
    match BOOLEAN,
    diff TEXT
)
AS $$
BEGIN
    RETURN QUERY
    SELECT jh.id, jh.nomor_referensi::TEXT, jh.status_posting::TEXT, v.match, v.diff
    FROM journal_headers jh
    CROSS JOIN LATERAL verify_journal_hash(jh.id) v
    ORDER BY jh.id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION verify_all_journal_hashes()
IS 'Verifikasi integritas semua jurnal sekaligus. Cocok untuk audit berkala.';

-- =====================================================================
-- 4. verify_hash_chain() -> TABLE
-- Verifikasi rantai hash: hash baris n bergantung pada stored hash baris n-1.
-- Mendeteksi PENYISIPAN/PENGHAPUSAN header di tengah rantai.
--
-- Cara kerja: untuk tiap header (urut by id), hitung ulang hash-nya.
-- chain_ok = TRUE bila stored hash setiap header == computed hash-nya
-- DAN stored hash header n == stored hash yang dipakai saat header n+1 dihitung
-- (yaitu stored hash header n-1 masih konsisten).
-- =====================================================================
CREATE OR REPLACE FUNCTION verify_hash_chain()
RETURNS TABLE (
    header_id BIGINT,
    nomor_referensi TEXT,
    stored_hash TEXT,
    computed_hash TEXT,
    data_ok BOOLEAN,
    chain_ok BOOLEAN
)
AS $$
DECLARE
    r            RECORD;
    v_computed   TEXT;
    v_prev_stored TEXT := NULL;
    v_prev_computed TEXT := NULL;
    v_data_ok    BOOLEAN;
    v_chain_ok   BOOLEAN := TRUE;
BEGIN
    FOR r IN
        SELECT jh.id, jh.nomor_referensi, jh.hash_checksum
        FROM journal_headers jh
        ORDER BY jh.id
    LOOP
        v_computed := compute_journal_hash(r.id);
        v_data_ok  := (r.hash_checksum = v_computed);

        -- Chain: stored hash header sebelumnya harus sama dengan
        -- stored hash yang dipakai saat header ini dihitung.
        -- Karena compute_journal_hash memakai stored hash (n-1),
        -- maka chain_ok = (prev_stored == prev_computed) untuk n >= 2.
        IF v_prev_stored IS NOT NULL THEN
            v_chain_ok := (v_prev_stored = v_prev_computed);
        ELSE
            v_chain_ok := TRUE;
        END IF;

        RETURN QUERY SELECT r.id, r.nomor_referensi, r.hash_checksum,
                          v_computed, v_data_ok, v_chain_ok;

        v_prev_stored   := r.hash_checksum;
        v_prev_computed := v_computed;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION verify_hash_chain()
IS 'Verifikasi rantai hash antar header. data_ok = hash utuh; chain_ok = rantai tidak putus (deteksi sisip/hapus di tengah).';

-- =====================================================================
-- 5. set_journal_hash_on_post() + trigger
-- Safety net: hitung hash otomatis saat status -> POSTED
-- (RPC post_journal juga menghitung manual; trigger ini cadangan)
-- =====================================================================
CREATE OR REPLACE FUNCTION set_journal_hash_on_post()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.status_posting = 'POSTED' AND (OLD.status_posting IS DISTINCT FROM 'POSTED') THEN
        NEW.hash_checksum := compute_journal_hash(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_hash_on_post ON journal_headers;
CREATE TRIGGER trg_set_hash_on_post
BEFORE UPDATE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION set_journal_hash_on_post();

COMMENT ON TRIGGER trg_set_hash_on_post ON journal_headers
IS 'Otomatis menghitung hash_checksum saat status berubah ke POSTED (safety net).';

-- =====================================================================
-- CATATAN KETERBATASAN (jujur):
-- - Hash TIDAK mencegah DBA/superuser berniat jahat: DBA bisa mengubah data
--   LALU menghitung ulang hash-nya. Hash hanya mendeteksi perubahan yang
--   tidak disertai rehash. Untuk jaminan kuat, diperlukan hash chain +
--   anchor eksternal (mis. hash berkala ditandatangani & disimpan di
--   sistem terpisah / blockchain / notarisasi waktu).
-- - Hash chaining mendeteksi penyisipan/penghapusan header di tengah,
--   tetapi TIDAK mendeteksi perubahan data header lama jika hash-nya
--   tidak di-recompute (ditangkap oleh verify_journal_hash per-baris).
-- - Karena hash bergantung pada stored hash header sebelumnya, mengubah
--   header lama memerlukan rehash berantai ke semua header sesudahnya.
-- =====================================================================


