-- =====================================================================
-- SOAL 1 UTS - TEST CONSTRAINTS (POSITIF & NEGATIF)
-- Jalankan SETELAH schema.sql dan seed_test.sql
--
-- Teknik: setiap tes negatif dibungkus DO $$ ... EXCEPTION $$
-- sehingga error ditangkap dan dicatat sebagai NOTICE, skrip tetap jalan.
-- =====================================================================

\echo '====================================================================='
\echo 'PLE 1: Skenario POSITIF - jurnal seimbang (Kas D 1jt / Pendapatan K 1jt)'
\echo '====================================================================='

-- SCENARIO 1: POSITIF - jurnal seimbang harus BERHASIL
DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-01', 'JV-POS-001', 'TEST POSITIF: Kas masuk pendapatan jasa', 'POSTED')
    RETURNING id INTO v_header_id;

    INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
    (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 1000000.00, 0),
    (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '4101'), 0, 1000000.00);

    RAISE NOTICE 'PLE 1 PASS: jurnal seimbang berhasil disimpan (header_id=%)', v_header_id;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PLE 1 FAIL: jurnal seimbang seharusnya berhasil, tapi gagal: %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'PLE 2: Skenario NEGATIF - debit NEGATIF harus DITOLAK (CHECK debit >= 0)'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-02', 'JV-NEG-001', 'TEST NEGATIF: debit negatif', 'DRAFT')
    RETURNING id INTO v_header_id;

    RAISE NOTICE 'Mencoba insert debit = -50000 ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), -50000.00, 0);

    RAISE NOTICE 'PLE 2 FAIL: debit negatif seharusnya DITOLAK!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PLE 2 PASS: debit negatif ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 2 PASS (error lain): %', SQLERRM;
END $$;

-- Bersihkan sisa header jika ada (DO block gagal -> auto rollback, tapi aman)
DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-001';

\echo ''
\echo '====================================================================='
\echo 'PLE 3: Skenario NEGATIF - kredit NEGATIF harus DITOLAK (CHECK credit >= 0)'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-03', 'JV-NEG-002', 'TEST NEGATIF: kredit negatif', 'DRAFT')
    RETURNING id INTO v_header_id;

    RAISE NOTICE 'Mencoba insert credit = -75000 ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '4101'), 0, -75000.00);

    RAISE NOTICE 'PLE 3 FAIL: kredit negatif seharusnya DITOLAK!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PLE 3 PASS: kredit negatif ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 3 PASS (error lain): %', SQLERRM;
END $$;

DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-002';

\echo ''
\echo '====================================================================='
\echo 'PLE 4: Skenario NEGATIF - debit=0 & credit=0 harus DITOLAK (NOT both zero)'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-04', 'JV-NEG-003', 'TEST NEGATIF: baris nol', 'DRAFT')
    RETURNING id INTO v_header_id;

    RAISE NOTICE 'Mencoba insert debit=0 AND credit=0 ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 0, 0);

    RAISE NOTICE 'PLE 4 FAIL: baris nol seharusnya DITOLAK!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PLE 4 PASS: baris nol ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 4 PASS (error lain): %', SQLERRM;
END $$;

DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-003';

\echo ''
\echo '====================================================================='
\echo 'PLE 5: Skenario NEGATIF - FK header_id TIDAK ADA harus DITOLAK'
\echo '====================================================================='

DO $$
BEGIN
    RAISE NOTICE 'Mencoba insert line dengan header_id = 999999 (tidak ada) ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (999999, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 100000.00, 0);

    RAISE NOTICE 'PLE 5 FAIL: FK header_id tidak ada seharusnya DITOLAK!';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'PLE 5 PASS: FK header_id tidak ada ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 5 PASS (error lain): %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'PLE 6: Skenario NEGATIF - FK account_id TIDAK ADA harus DITOLAK'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-06', 'JV-NEG-004', 'TEST NEGATIF: FK account_id tidak ada', 'DRAFT')
    RETURNING id INTO v_header_id;

    RAISE NOTICE 'Mencoba insert line dengan account_id = 999999 (tidak ada) ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (v_header_id, 999999, 100000.00, 0);

    RAISE NOTICE 'PLE 6 FAIL: FK account_id tidak ada seharusnya DITOLAK!';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'PLE 6 PASS: FK account_id tidak ada ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 6 PASS (error lain): %', SQLERRM;
END $$;

DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-004';

\echo ''
\echo '====================================================================='
\echo 'PLE 7: Skenario NEGATIF - DELETE akun yang sudah dipakai harus DITOLAK'
\echo '         (FK ON DELETE RESTRICT)'
\echo '====================================================================='

DO $$
DECLARE
    v_kode VARCHAR(20) := '1101'; -- Kas, sudah dipakai di seed data
BEGIN
    RAISE NOTICE 'Mencoba DELETE akun dengan kode % yang sudah dipakai transaksi ...', v_kode;
    DELETE FROM chart_of_accounts WHERE kode_akun = v_kode;

    RAISE NOTICE 'PLE 7 FAIL: DELETE akun terpakai seharusnya DITOLAK!';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'PLE 7 PASS: DELETE akun terpakai ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 7 PASS (error lain): %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'PLE 8: Skenario NEGATIF - jurnal TIDAK SEIMBANG harus DITOLAK trigger'
\echo '         BONUS (SUM debit != SUM credit per header, ditolak saat COMMIT)'
\echo '====================================================================='

-- TRIGGER DEFERRABLE INITIALLY DEFERRED hanya bertindak saat COMMIT,
-- sehingga dibutuhkan transaksi eksplisit BEGIN ... COMMIT di luar DO block.
-- Jika COMMIT ditolak, psql otomatis ROLLBACK dan menampilkan pesan ERROR.
BEGIN;
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-08', 'JV-NEG-005', 'TEST NEGATIF: jurnal tidak seimbang (Kas D 500rb + Pendapatan K 200rb)', 'DRAFT')
    RETURNING id AS header_id \gset

    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    SELECT :header_id, id,
           CASE WHEN kode_akun = '1101' THEN 500000.00 ELSE 0 END,
           CASE WHEN kode_akun = '4101' THEN 200000.00 ELSE 0 END
    FROM chart_of_accounts
    WHERE kode_akun IN ('1101', '4101');

\echo 'Mencoba COMMIT jurnal tidak seimbang (D 500rb != K 200rb) ...'
\echo 'Harapannya: ERROR + ROLLBACK dari trg_journal_lines_balance_check'
COMMIT;

-- Bersihkan sisa jika commit berhasil (tidak seharusnya terjadi)
DELETE FROM journal_lines WHERE header_id IN (SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-NEG-005');
DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-005';

\echo ''
\echo '====================================================================='
\echo 'PLE 9: Skenario POSITIF - jurnal multi-line seimbang (3 baris)'
\echo '         (Beban Gaji D 2jt / Kas K 1.5jt + Utang Gaji K 0.5jt)'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-09', 'JV-POS-002', 'TEST POSITIF: jurnal 3 baris seimbang', 'POSTED')
    RETURNING id INTO v_header_id;

    INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
    (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '5101'), 2000000.00, 0),
    (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 0, 1500000.00),
    (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '2201'), 0, 500000.00);

    RAISE NOTICE 'PLE 9 PASS: jurnal multi-line seimbang berhasil (header_id=%)', v_header_id;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PLE 9 FAIL: jurnal seimbang seharusnya berhasil: %', SQLERRM;
END $$;

\echo ''
\echo '====================================================================='
\echo 'PLE 10: Skenario NEGATIF - debit > 0 DAN credit > 0 bersama (BONUS CHECK)'
\echo '====================================================================='

DO $$
DECLARE
    v_header_id BIGINT;
BEGIN
    INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
    VALUES ('2024-03-10', 'JV-NEG-006', 'TEST NEGATIF: baris D & K bersamaan', 'DRAFT')
    RETURNING id INTO v_header_id;

    RAISE NOTICE 'Mencoba insert debit=100000 AND credit=50000 dalam satu baris ...';
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (v_header_id, (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 100000.00, 50000.00);

    RAISE NOTICE 'PLE 10 FAIL: baris D & K bersamaan seharusnya DITOLAK!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PLE 10 PASS: baris D & K bersamaan ditolak. Error: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'PLE 10 PASS (error lain): %', SQLERRM;
END $$;

DELETE FROM journal_headers WHERE nomor_referensi = 'JV-NEG-006';

\echo ''
\echo '====================================================================='
\echo 'SELESAI - Lihat NOTICE dan ERROR di atas untuk hasil tiap tes.'
\echo ' Setiap NOTICE "PLE n PASS" = tes berperilaku sesuai harapan.'
\echo ' Setiap NOTICE "PLE n FAIL" = tes TIDAK sesuai harapan.'
\echo '====================================================================='
