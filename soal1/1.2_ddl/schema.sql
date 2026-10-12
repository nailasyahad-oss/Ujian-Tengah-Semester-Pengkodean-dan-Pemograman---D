-- =====================================================================
-- SOAL 1 UTS - DDL POSTGRESQL GENERAL LEDGER
-- Idempoten: aman dijalankan berulang kali
-- PostgreSQL 14+
-- =====================================================================

-- Hapus urutan terbalik karena FK
DROP TABLE IF EXISTS journal_lines CASCADE;
DROP TABLE IF EXISTS journal_headers CASCADE;
DROP TABLE IF EXISTS chart_of_accounts CASCADE;

-- =====================================================================
-- 1. CHART OF ACCOUNTS - Master Akun
-- =====================================================================
CREATE TABLE chart_of_accounts (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kode_akun       VARCHAR(20) NOT NULL,
    nama_akun       VARCHAR(200) NOT NULL,
    normal_balance  VARCHAR(10) NOT NULL CHECK (normal_balance IN ('DEBIT', 'CREDIT')),
    classification  VARCHAR(20) NOT NULL CHECK (classification IN ('ASET', 'LIABILITAS', 'EKUITAS', 'PENDAPATAN', 'BEBAN')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- UNIQUE constraint pada kode_akun (natural key)
ALTER TABLE chart_of_accounts
    ADD CONSTRAINT uq_chart_of_accounts_kode_akun UNIQUE (kode_akun);

-- Index untuk performa lookup by kode_akun
CREATE INDEX idx_chart_of_accounts_kode_akun ON chart_of_accounts (kode_akun);

-- Komentar tabel & kolom
COMMENT ON TABLE chart_of_accounts IS 'Master daftar akun akuntansi (Chart of Accounts)';
COMMENT ON COLUMN chart_of_accounts.id IS 'Surrogate key, auto-increment';
COMMENT ON COLUMN chart_of_accounts.kode_akun IS 'Kode akun alami (mis. 1101 Kas, 4101 Pendapatan Jasa), UNIQUE untuk lookup cepat';
COMMENT ON COLUMN chart_of_accounts.nama_akun IS 'Nama deskriptif akun';
COMMENT ON COLUMN chart_of_accounts.normal_balance IS 'Saldo normal akun: DEBIT (Aset/Beban) atau CREDIT (Liabilitas/Ekuitas/Pendapatan)';
COMMENT ON COLUMN chart_of_accounts.classification IS 'Klasifikasi laporan keuangan: ASET, LIABILITAS, EKUITAS, PENDAPATAN, BEBAN';
COMMENT ON CONSTRAINT uq_chart_of_accounts_kode_akun ON chart_of_accounts IS 'Mencegah duplikasi kode akun; kode akun adalah natural key bisnis';

-- =====================================================================
-- 2. JOURNAL HEADERS - Header Transaksi Jurnal
-- =====================================================================
CREATE TABLE journal_headers (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tanggal_transaksi   DATE NOT NULL,
    nomor_referensi     VARCHAR(50) NOT NULL,
    deskripsi           TEXT,
    status_posting      VARCHAR(20) NOT NULL CHECK (status_posting IN ('DRAFT', 'POSTED', 'REVERSED')) DEFAULT 'DRAFT',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    posted_at           TIMESTAMPTZ
);

-- UNIQUE constraint pada nomor_referensi (nomor bukti unik)
ALTER TABLE journal_headers
    ADD CONSTRAINT uq_journal_headers_nomor_referensi UNIQUE (nomor_referensi);

-- Index untuk query by tanggal & status
CREATE INDEX idx_journal_headers_tanggal ON journal_headers (tanggal_transaksi);
CREATE INDEX idx_journal_headers_status ON journal_headers (status_posting);

-- Komentar
COMMENT ON TABLE journal_headers IS 'Header transaksi jurnal: satu transaksi atomik (double-entry)';
COMMENT ON COLUMN journal_headers.id IS 'Surrogate key';
COMMENT ON COLUMN journal_headers.tanggal_transaksi IS 'Tanggal transaksi (DATE, bukan timestamp, untuk konsistensi periode akuntansi)';
COMMENT ON COLUMN journal_headers.nomor_referensi IS 'Nomor bukti/bukti transaksi (mis. JV-2024-001), UNIQUE untuk audit trail';
COMMENT ON COLUMN journal_headers.deskripsi IS 'Keterangan/uraian transaksi';
COMMENT ON COLUMN journal_headers.status_posting IS 'Status: DRAFT (draft), POSTED (diposting immutable), REVERSED (dibalik via reversing entry)';
COMMENT ON COLUMN journal_headers.created_at IS 'Waktu pembuatan record (audit trail)';
COMMENT ON COLUMN journal_headers.posted_at IS 'Waktu posting; NULL jika DRAFT/REVERSED';
COMMENT ON CONSTRAINT uq_journal_headers_nomor_referensi ON journal_headers IS 'Mencegah duplikasi nomor bukti; setiap transaksi harus punya bukti unik';

-- =====================================================================
-- 3. JOURNAL LINES - Detail Baris Jurnal
-- =====================================================================
CREATE TABLE journal_lines (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    header_id   BIGINT NOT NULL,
    account_id  BIGINT NOT NULL,
    debit       NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit      NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- CHECK constraint level baris: tidak boleh keduanya nol
    CONSTRAINT chk_journal_lines_not_both_zero CHECK (NOT (debit = 0 AND credit = 0)),
    -- CHECK constraint bonus: tidak boleh keduanya > 0 sekaligus (satu baris = satu sisi)
    CONSTRAINT chk_journal_lines_not_both_positive CHECK (NOT (debit > 0 AND credit > 0))
);

-- Foreign Key: journal_lines.header_id -> journal_headers(id)
ALTER TABLE journal_lines
    ADD CONSTRAINT fk_journal_lines_header
    FOREIGN KEY (header_id) REFERENCES journal_headers (id)
    ON DELETE RESTRICT;

-- Foreign Key: journal_lines.account_id -> chart_of_accounts(id)
ALTER TABLE journal_lines
    ADD CONSTRAINT fk_journal_lines_account
    FOREIGN KEY (account_id) REFERENCES chart_of_accounts (id)
    ON DELETE RESTRICT;

-- Index pada FK untuk performa join & FK check
CREATE INDEX idx_journal_lines_header_id ON journal_lines (header_id);
CREATE INDEX idx_journal_lines_account_id ON journal_lines (account_id);

-- Komentar
COMMENT ON TABLE journal_lines IS 'Detail baris jurnal: setiap baris = satu sisi DEBIT atau KREDIT dari satu transaksi';
COMMENT ON COLUMN journal_lines.id IS 'Surrogate key';
COMMENT ON COLUMN journal_lines.header_id IS 'FK ke journal_headers; ON DELETE RESTRICT mencegah hapus header yang masih punya line';
COMMENT ON COLUMN journal_lines.account_id IS 'FK ke chart_of_accounts; ON DELETE RESTRICT mencegah hapus akun yang sudah dipakai transaksi';
COMMENT ON COLUMN journal_lines.debit IS 'Nominal DEBIT (>=0). NUMERIC(18,2) exact numeric untuk uang, bukan FLOAT';
COMMENT ON COLUMN journal_lines.credit IS 'Nominal KREDIT (>=0). NUMERIC(18,2) exact numeric untuk uang, bukan FLOAT';
COMMENT ON CONSTRAINT chk_journal_lines_not_both_zero ON journal_lines IS 'Setiap baris harus punya nilai: DEBIT > 0 XOR KREDIT > 0. Tidak boleh keduanya 0';
COMMENT ON CONSTRAINT chk_journal_lines_not_both_positive ON journal_lines IS 'BONUS: Satu baris hanya boleh DEBIT ATAU KREDIT, tidak keduanya > 0 sekaligus';
COMMENT ON CONSTRAINT fk_journal_lines_header ON journal_lines IS 'Integritas referensial: line tidak bisa tanpa header induk';
COMMENT ON CONSTRAINT fk_journal_lines_account ON journal_lines IS 'Integritas referensial: line harus merujuk akun valid; RESTRICT lindungi histori';

-- =====================================================================
-- BONUS: TRIGGER DEFERRABLE UNTUK VALIDASI KESEIMBANGAN DEBIT = KREDIT PER HEADER
-- =====================================================================
-- Catatan: CHECK constraint per-baris TIDAK BISA memeriksa keseimbangan antar baris
-- karena CHECK hanya evaluasi per-row. Keseimbangan melibatkan SUM agregat multi-baris
-- dalam satu transaksi (header_id). Oleh karena itu diperlukan trigger DEFERRABLE
-- yang dievaluasi saat COMMIT (INITIALLY DEFERRED).

-- Fungsi trigger
CREATE OR REPLACE FUNCTION fn_check_journal_balance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_header_id BIGINT;
    v_sum_debit NUMERIC(18,2);
    v_sum_credit NUMERIC(18,2);
BEGIN
    -- Tentukan header_id dari row yang berubah (INSERT/UPDATE/DELETE)
    IF TG_OP = 'DELETE' THEN
        v_header_id := OLD.header_id;
    ELSE
        v_header_id := NEW.header_id;
    END IF;

    -- Hitung total debit & credit untuk header tersebut
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO v_sum_debit, v_sum_credit
    FROM journal_lines
    WHERE header_id = v_header_id;

    -- Validasi keseimbangan
    IF v_sum_debit <> v_sum_credit THEN
        RAISE EXCEPTION 'JURNAL TIDAK SEIMBANG: Header ID % - Total Debit (%) != Total Credit (%). Transaksi rollback.',
            v_header_id, v_sum_debit, v_sum_credit
        USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL; -- AFTER trigger tidak perlu return NEW
END;
$$;

-- Trigger: AFTER INSERT OR UPDATE OR DELETE, DEFERRABLE INITIALLY DEFERRED
-- Artinya: validasi dilakukan di akhir transaksi (COMMIT), bukan per statement
DROP TRIGGER IF EXISTS trg_journal_lines_balance_check ON journal_lines;
CREATE CONSTRAINT TRIGGER trg_journal_lines_balance_check
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();

COMMENT ON FUNCTION fn_check_journal_balance IS 'Trigger function: memvalidasi SUM(debit) = SUM(credit) per header_id saat COMMIT. DEFERRABLE INITIALLY DEFERRED memastikan cek terjadi akhir transaksi, bukan per statement.';
COMMENT ON TRIGGER trg_journal_lines_balance_check ON journal_lines IS 'BONUS: Constraint trigger DEFERRABLE. Menutup celah transaksi API lolos tanpa pasangan Debit-Kredit valid. Evaluasi saat COMMIT.';

-- =====================================================================
-- SELESAI
-- =====================================================================