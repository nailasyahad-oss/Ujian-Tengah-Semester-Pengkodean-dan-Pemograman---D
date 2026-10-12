-- =====================================================================
-- SOAL 3 UTS - 04_rpc_post_and_reverse.sql
-- RPC Functions: post_journal() & reverse_journal()
-- SECURITY DEFINER, validasi server-side, audit trail, hash, immutability
-- PostgreSQL 14+ (Supabase compatible)
-- =====================================================================

-- =====================================================================
-- 1. POST JOURNAL - SECURITY DEFINER
-- Input: p_header (jsonb), p_lines (jsonb array)
-- Validasi server-side: balance, akun ada, baris valid, no_bukti unik
-- Output: header_id, status, hash_checksum
-- =====================================================================
CREATE OR REPLACE FUNCTION post_journal(
    p_header JSONB,
    p_lines  JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_header_id   BIGINT;
    -- Actor: di Supabase = auth.uid() (claim sub); di lokal = current_user
    v_actor       TEXT := COALESCE(
                          current_setting('request.jwt.claim.sub', TRUE),
                          current_user
                        );
    v_total_debit  NUMERIC(18,2) := 0;
    v_total_credit NUMERIC(18,2) := 0;
    v_line_count   INT := 0;
    v_nomor_ref    TEXT;
    v_status       TEXT := 'POSTED';
    v_hash         TEXT;
    v_line         JSONB;
    v_account_id   BIGINT;
    v_debit        NUMERIC(18,2);
    v_credit       NUMERIC(18,2);
    v_desc         TEXT;
BEGIN
    -- 1. Validasi header input
    IF p_header IS NULL OR jsonb_typeof(p_header) <> 'object' THEN
        RAISE EXCEPTION 'HEADER_TIDAK_VALID: p_header harus object JSONB'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    v_nomor_ref := COALESCE(p_header->>'nomor_referensi', '');
    IF v_nomor_ref = '' THEN
        RAISE EXCEPTION 'NOMOR_REFERENSI_KOSONG: no. bukti wajib diisi'
            USING ERRCODE = 'not_null_violation';
    END IF;

    -- Cek unik no bukti
    IF EXISTS (SELECT 1 FROM journal_headers WHERE nomor_referensi = v_nomor_ref) THEN
        RAISE EXCEPTION 'NOMOR_REFERENSI_DUPLIKAT: % sudah ada', v_nomor_ref
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 2. Validasi lines array
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN
        RAISE EXCEPTION 'LINES_TIDAK_VALID: p_lines harus array JSONB'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF jsonb_array_length(p_lines) < 2 THEN
        RAISE EXCEPTION 'MINIMAL_2_LINES: jurnal minimal 2 baris (double-entry)'
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3. Loop validasi tiap line & hitung total
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_line_count := v_line_count + 1;

        -- Validasi akun
        IF NOT (v_line ? 'account_id') THEN
            RAISE EXCEPTION 'LINE_%_TIDAK_PUNYA_AKUN: baris ke-% wajib punya account_id', v_line_count, v_line_count
                USING ERRCODE = 'check_violation';
        END IF;
        v_account_id := (v_line->>'account_id')::BIGINT;
        IF NOT EXISTS (SELECT 1 FROM chart_of_accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'LINE_%_AKUN_TIDAK_ADA: account_id % tidak ditemukan', v_line_count, v_account_id
                USING ERRCODE = 'foreign_key_violation';
        END IF;

        -- Validasi debit/kredit (satu sisi saja, > 0)
        v_debit  := COALESCE((v_line->>'debit')::NUMERIC(18,2), 0);
        v_credit := COALESCE((v_line->>'credit')::NUMERIC(18,2), 0);

        IF v_debit < 0 OR v_credit < 0 THEN
            RAISE EXCEPTION 'LINE_%_NEGATIF: debit/kredit tidak boleh negatif', v_line_count
                USING ERRCODE = 'check_violation';
        END IF;

        IF v_debit = 0 AND v_credit = 0 THEN
            RAISE EXCEPTION 'LINE_%_KEDUA_NOL: debit dan kredit tidak boleh keduanya 0', v_line_count
                USING ERRCODE = 'check_violation';
        END IF;

        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'LINE_%_KEDUA_ISI: debit dan kredit tidak boleh keduanya > 0', v_line_count
                USING ERRCODE = 'check_violation';
        END IF;

        v_total_debit  := v_total_debit + v_debit;
        v_total_credit := v_total_credit + v_credit;
    END LOOP;

    -- 4. Cek keseimbangan total
    IF v_total_debit <> v_total_credit THEN
        RAISE EXCEPTION 'JURNAL_TIDAK_SEIMBANG: Total Debit (%) != Total Credit (%)',
            v_total_debit, v_total_credit
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_total_debit = 0 THEN
        RAISE EXCEPTION 'TOTAL_NOL: total jurnal tidak boleh 0'
            USING ERRCODE = 'check_violation';
    END IF;

    -- 5. Insert header dalam transaksi yang sama
    INSERT INTO journal_headers (
        tanggal_transaksi, nomor_referensi, deskripsi, status_posting,
        created_by, created_at, posted_at, posted_by, hash_checksum
    ) VALUES (
        COALESCE((p_header->>'tanggal_transaksi')::DATE, CURRENT_DATE),
        v_nomor_ref,
        p_header->>'deskripsi',
        v_status,
        v_actor,
        now(),
        now(),
        v_actor,
        NULL -- hash di-set setelah insert lines
    ) RETURNING id INTO v_header_id;

    -- 6. Insert lines
    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        INSERT INTO journal_lines (
            header_id, account_id, debit, credit, created_by, created_at
        ) VALUES (
            v_header_id,
            (v_line->>'account_id')::BIGINT,
            COALESCE((v_line->>'debit')::NUMERIC(18,2), 0),
            COALESCE((v_line->>'credit')::NUMERIC(18,2), 0),
            COALESCE(v_line->>'created_by', v_actor),
            now()
        );
    END LOOP;

    -- 7. Hitung & set hash checksum
    UPDATE journal_headers
       SET hash_checksum = compute_journal_hash(v_header_id)
     WHERE id = v_header_id
    RETURNING hash_checksum INTO v_hash;

    -- 8. Return sukses
    RETURN jsonb_build_object(
        'success', TRUE,
        'header_id', v_header_id,
        'nomor_referensi', v_nomor_ref,
        'status_posting', v_status,
        'total_debit', v_total_debit,
        'total_credit', v_total_credit,
        'hash_checksum', v_hash,
        'message', 'Jurnal berhasil di-posting'
    );

EXCEPTION WHEN OTHERS THEN
    -- Log error ke audit_log (bisa via trigger BLOCKED_ATTEMPT di lapisan aplikasi)
    RAISE;
END;
$$;

COMMENT ON FUNCTION post_journal(JSONB, JSONB)
IS 'RPC posting jurnal: validasi balance, akun, unik no_bukti; insert header+lines atomik; hitung hash; return header_id & hash.';

-- =====================================================================
-- 2. REVERSE JOURNAL (STORNO) - SECURITY DEFINER
-- Hanya untuk header POSTED; membuat jurnal pembalik (debit<->kredit ditukar)
-- Menandai asal REVERSED, mencegah storno ganda, wajib alasan
-- =====================================================================
CREATE OR REPLACE FUNCTION reverse_journal(
    p_header_id BIGINT,
    p_reason    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_actor           TEXT := COALESCE(
                              current_setting('request.jwt.claim.sub', TRUE),
                              current_user
                            );
    v_orig_status     TEXT;
    v_orig_nomor      TEXT;
    v_new_header_id   BIGINT;
    v_new_nomor       TEXT;
    v_hash            TEXT;
    v_line            RECORD;
BEGIN
    -- 1. Cek header asal ada dan POSTED
    SELECT status_posting, nomor_referensi INTO v_orig_status, v_orig_nomor
    FROM journal_headers WHERE id = p_header_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'HEADER_TIDAK_DITEMUKAN: id %', p_header_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_orig_status <> 'POSTED' THEN
        RAISE EXCEPTION 'HANYA_POSTED_YANG_BOLEH_DIREVERSAL: status saat ini %', v_orig_status
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    -- Cek sudah pernah di-reverse
    IF EXISTS (SELECT 1 FROM journal_headers WHERE reversal_of_header_id = p_header_id) THEN
        RAISE EXCEPTION 'STORNO_GANDA: jurnal % sudah pernah dibatalkan', p_header_id
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    -- Alasan wajib
    IF p_reason IS NULL OR trim(p_reason) = '' THEN
        RAISE EXCEPTION 'ALASAN_WAJIB: storno membutuhkan alasan'
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2. Set flag sesi untuk bypass immutability trigger (LOCAL = hanya transaksi ini)
    PERFORM set_config('app.allow_reversal', 'on', TRUE);

    -- 3. Mulai transaksi baru untuk jurnal pembalik
    -- Generate nomor referensi baru: STORNO-{nomor_asli}-{timestamp}
    v_new_nomor := 'STORNO-' || v_orig_nomor || '-' || to_char(now(), 'YYYYMMDDHH24MISS');

    -- Insert header baru (POSTED langsung)
    INSERT INTO journal_headers (
        tanggal_transaksi, nomor_referensi, deskripsi, status_posting,
        created_by, created_at, posted_at, posted_by,
        reversal_of_header_id, hash_checksum
    ) VALUES (
        CURRENT_DATE,
        v_new_nomor,
        'STORNO: ' || COALESCE((SELECT deskripsi FROM journal_headers WHERE id = p_header_id), '') || ' | Alasan: ' || p_reason,
        'POSTED',
        v_actor,
        now(),
        now(),
        v_actor,
        p_header_id,
        NULL
    ) RETURNING id INTO v_new_header_id;

    -- 4. Insert lines pembalik (debit<->kredit ditukar)
    FOR v_line IN
        SELECT account_id, credit AS debit, debit AS credit
        FROM journal_lines
        WHERE header_id = p_header_id
    LOOP
        INSERT INTO journal_lines (header_id, account_id, debit, credit, created_by, created_at)
        VALUES (v_new_header_id, v_line.account_id, v_line.debit, v_line.credit,
                v_actor, now());
    END LOOP;

    -- 5. Hitung hash jurnal baru
    UPDATE journal_headers
       SET hash_checksum = compute_journal_hash(v_new_header_id)
     WHERE id = v_new_header_id;

    -- 6. Tandai jurnal asal sebagai REVERSED + link ke pembalik
    UPDATE journal_headers
       SET status_posting = 'REVERSED',
           reversed_by_header_id = v_new_header_id
     WHERE id = p_header_id;

    -- 6. Return sukses
    RETURN jsonb_build_object(
        'success', TRUE,
        'original_header_id', p_header_id,
        'reversal_header_id', v_new_header_id,
        'reversal_nomor_referensi', v_new_nomor,
        'message', 'Storno berhasil dibuat'
    );

EXCEPTION WHEN OTHERS THEN
    -- Reset flag sesi (walau LOCAL auto-reset di akhir transaksi, aman)
    PERFORM set_config('app.allow_reversal', 'off', TRUE);
    RAISE;
END;
$$;

COMMENT ON FUNCTION reverse_journal(BIGINT, TEXT)
IS 'Storno jurnal POSTED: buat jurnal pembalik (debit<->kredit), tandai asal REVERSED, mencegah storno ganda, wajib alasan. Flag sesi allow_reversal=on untuk bypass immutability.';

-- =====================================================================
-- 3. FUNGSI BANTU: GET JOURNAL DETAIL (untuk frontend)
-- =====================================================================
CREATE OR REPLACE FUNCTION get_journal_detail(p_header_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_header JSONB;
    v_lines  JSONB;
BEGIN
    SELECT to_jsonb(jh) INTO v_header FROM journal_headers jh WHERE jh.id = p_header_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'NOT_FOUND');
    END IF;

    SELECT jsonb_agg(to_jsonb(jl) ORDER BY jl.id) INTO v_lines
    FROM journal_lines jl WHERE jl.header_id = p_header_id;

    RETURN jsonb_build_object(
        'header', v_header,
        'lines', COALESCE(v_lines, '[]'::JSONB)
    );
END;
$$;

COMMENT ON FUNCTION get_journal_detail(BIGINT)
IS 'Ambil detail jurnal (header + lines) untuk tampilan frontend.';

-- =====================================================================
-- 4. GRANT EXECUTE UNTUK ROLE AUTHENTICATED (Supabase)
-- Jalankan di Supabase SQL Editor setelah deploy:
-- GRANT EXECUTE ON FUNCTION post_journal(jsonb, jsonb) TO authenticated;
-- GRANT EXECUTE ON FUNCTION reverse_journal(bigint, text) TO authenticated;
-- GRANT EXECUTE ON FUNCTION get_journal_detail(bigint) TO authenticated;
-- GRANT EXECUTE ON FUNCTION verify_journal_hash(bigint) TO authenticated;
-- GRANT EXECUTE ON FUNCTION compute_journal_hash(bigint) TO authenticated;
-- GRANT SELECT ON journal_headers, journal_lines, chart_of_accounts, audit_log TO authenticated;
-- =====================================================================

-- =====================================================================
-- CATATAN KEAMANAN:
-- - SECURITY DEFINER: fungsi jalan dengan hak owner (biasanya postgres/service_role).
-- - Validasi ketat di server: balance, akun, unik, baris valid.
-- - Flag sesi app.allow_reversal=on (LOCAL) hanya di transaksi reverse_journal.
-- - Hash checksum dihitung & disimpan otomatis.
-- - Audit log tertulis via trigger (INSERT header/lines).
-- - Tidak ada service_role key di frontend; frontend hanya panggil RPC.
-- =====================================================================