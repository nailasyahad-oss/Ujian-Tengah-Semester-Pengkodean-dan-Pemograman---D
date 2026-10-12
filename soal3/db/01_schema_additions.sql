-- =====================================================================
-- SOAL 3 UTS - 01_schema_additions.sql
-- Tambahan kolom audit + tabel audit_log
-- Bisa dijalankan di atas skema soal1 (chart_of_accounts, journal_headers, journal_lines)
-- PostgreSQL 14+, butuh ekstensi pgcrypto untuk SHA-256
-- =====================================================================



-- =====================================================================
-- 1. TAMBAH KOLOM AUDIT PADA journal_headers
-- =====================================================================
ALTER TABLE journal_headers
    ADD COLUMN IF NOT EXISTS created_by     TEXT,
    ADD COLUMN IF NOT EXISTS created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS hash_checksum  TEXT,
    ADD COLUMN IF NOT EXISTS posted_at      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS posted_by      TEXT,
    ADD COLUMN IF NOT EXISTS reversed_by_header_id BIGINT
        REFERENCES journal_headers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reversal_of_header_id BIGINT
        REFERENCES journal_headers(id) ON DELETE SET NULL;

-- Pastikan status_posting memiliki nilai default dan constraint lengkap
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'journal_headers' AND constraint_name = 'chk_status_posting'
    ) THEN
        ALTER TABLE journal_headers
            ADD CONSTRAINT chk_status_posting
            CHECK (status_posting IN ('DRAFT','POSTED','REVERSED'));
    END IF;
END $$;

COMMENT ON COLUMN journal_headers.created_by      IS 'Identitas pembuat (auth.uid() atau current_user)';
COMMENT ON COLUMN journal_headers.created_at      IS 'Waktu pembuatan record (audit trail)';
COMMENT ON COLUMN journal_headers.hash_checksum   IS 'SHA-256 kanonik header+lines (integrity check)';
COMMENT ON COLUMN journal_headers.posted_at       IS 'Waktu posting (NULL jika DRAFT/REVERSED)';
COMMENT ON COLUMN journal_headers.posted_by       IS 'Identitas yang mem-posting';
COMMENT ON COLUMN journal_headers.reversed_by_header_id  IS 'Header ID jurnal pembalik (storno) yang membatalkan jurnal ini';
COMMENT ON COLUMN journal_headers.reversal_of_header_id  IS 'Header ID jurnal asal yang dibatalkan (NULL jika bukan storno)';

-- =====================================================================
-- 2. TAMBAH KOLOM AUDIT PADA journal_lines (opsional tapi direkomendasikan)
-- =====================================================================
ALTER TABLE journal_lines
    ADD COLUMN IF NOT EXISTS created_by  TEXT,
    ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN journal_lines.created_by IS 'Identitas pembuat baris';
COMMENT ON COLUMN journal_lines.created_at IS 'Waktu pembuatan baris';

-- =====================================================================
-- 3. TABEL AUDIT_LOG (append-only)
-- =====================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name      TEXT NOT NULL,
    record_id       BIGINT NOT NULL,
    action          TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE','BLOCKED_ATTEMPT')),
    old_data        JSONB,
    new_data        JSONB,
    actor           TEXT,
    at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    hash            TEXT
);

-- Indeks untuk query audit
CREATE INDEX IF NOT EXISTS idx_audit_log_table_record
    ON audit_log (table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_at
    ON audit_log (actor, at DESC);

-- Revoke DML berbahaya pada audit_log (hanya INSERT via trigger/aplikasi)
REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM PUBLIC;

COMMENT ON TABLE audit_log IS 'Log audit append-only untuk jurnal dan master data';
COMMENT ON COLUMN audit_log.table_name     IS 'Nama tabel yang berubah';
COMMENT ON COLUMN audit_log.record_id      IS 'PK record yang berubah';
COMMENT ON COLUMN audit_log.action         IS 'INSERT/UPDATE/DELETE/BLOCKED_ATTEMPT';
COMMENT ON COLUMN audit_log.old_data       IS 'Snapshot data lama (NULL untuk INSERT)';
COMMENT ON COLUMN audit_log.new_data       IS 'Snapshot data baru (NULL untuk DELETE)';
COMMENT ON COLUMN audit_log.actor          IS 'Identitas pelaku (auth.uid/current_user)';
COMMENT ON COLUMN audit_log.at             IS 'Waktu kejadian';
COMMENT ON COLUMN audit_log.hash           IS 'SHA-256 dari old_data||new_data||actor||at (integrity)';

-- Pastikan pgcrypto tersedia (dibutuhkan audit_log.hash)


-- =====================================================================
-- 4. TRIGGER AUDIT_LOG (generic untuk journal_headers & journal_lines)
--    Catatan: fungsi hash (compute_journal_hash, verify_journal_hash)
--    didefinisikan di 03_hash_checksum.sql agar tidak bentrok return type.
-- =====================================================================
CREATE OR REPLACE FUNCTION audit_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor TEXT := COALESCE(current_setting('app.current_user', TRUE), current_user);
    v_hash  TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, actor, hash)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), v_actor,
                md5((to_jsonb(NEW)::text || v_actor || now()::text), 'sha256'), 'hex'));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, actor, hash)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), v_actor,
                md5((to_jsonb(OLD)::text || to_jsonb(NEW)::text || v_actor || now()::text), 'sha256'), 'hex'));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, actor, hash)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD), v_actor,
                md5((to_jsonb(OLD)::text || v_actor || now()::text), 'sha256'), 'hex'));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

-- Pasang trigger pada journal_headers
DROP TRIGGER IF EXISTS trg_audit_journal_headers ON journal_headers;
CREATE TRIGGER trg_audit_journal_headers
AFTER INSERT OR UPDATE OR DELETE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- Pasang trigger pada journal_lines
DROP TRIGGER IF EXISTS trg_audit_journal_lines ON journal_lines;
CREATE TRIGGER trg_audit_journal_lines
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

COMMENT ON FUNCTION audit_trigger_fn()
IS 'Trigger audit generic: mencatat INSERT/UPDATE/DELETE ke audit_log dengan hash integrity.';

-- =====================================================================
-- 6. SEED DATA CONTOH (jika tabel kosong)
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM chart_of_accounts WHERE kode_akun = '1101') THEN
        INSERT INTO chart_of_accounts (kode_akun, nama_akun, normal_balance, classification) VALUES
        ('1101', 'Kas', 'DEBIT', 'ASET'),
        ('1102', 'Bank', 'DEBIT', 'ASET'),
        ('5201', 'Beban Listrik & Air', 'DEBIT', 'BEBAN'),
        ('2101', 'Utang Usaha', 'CREDIT', 'LIABILITAS');
    END IF;
END $$;
