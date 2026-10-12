-- =====================================================================
-- SOAL 3 UTS - 05_tests.sql
-- Uji positif/negatif RPC post_journal, reverse_journal, hash, immutability
-- Jalankan SETELAH 01-04 di PostgreSQL 14+ (Supabase/local)
-- Catatan: JSONB dibangun dengan jsonb_build_object/array + subquery
--           (tidak boleh menyisipkan SQL mentah di dalam string JSON).
-- =====================================================================

\echo '====================================================================='
\echo 'PERSIAPAN: reset data & pastikan fungsi tersedia'
\echo '====================================================================='
TRUNCATE audit_log, journal_lines, journal_headers RESTART IDENTITY CASCADE;

-- Seed akun minimal (id deterministic via ON CONFLICT)
INSERT INTO chart_of_accounts (kode_akun, nama_akun, normal_balance, classification) VALUES
('1101', 'Kas', 'DEBIT', 'ASET'),
('1102', 'Bank', 'DEBIT', 'ASET'),
('5201', 'Beban Listrik & Air', 'DEBIT', 'BEBAN'),
('2101', 'Utang Usaha', 'CREDIT', 'LIABILITAS')
ON CONFLICT (kode_akun) DO NOTHING;

-- Tampilkan id akun yang dipakai
SELECT kode_akun, id FROM chart_of_accounts ORDER BY kode_akun;

\echo ''
\echo '====================================================================='
\echo 'TES 1: POST JURNAL SEIMBANG (KAS KELUAR - Beban Listrik 500rb)'
\echo '         D Beban Listrik 500.000 / K Kas 500.000'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-01',
        'nomor_referensi', 'KK-2024-001',
        'deskripsi', 'Bayar listrik'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201'),
            'debit', 500000, 'credit', 0
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 500000
        )
    )
) AS hasil_post_1;

\echo ''
\echo '--- Verifikasi jurnal 1: status POSTED, hash terisi, verify = true ---'
SELECT id, nomor_referensi, status_posting,
       CASE WHEN hash_checksum IS NULL THEN 'NULL' ELSE substring(hash_checksum FROM 1 FOR 16) || '...' END AS hash_prefix,
       (SELECT match FROM verify_journal_hash(jh.id)) AS verify
FROM journal_headers jh WHERE nomor_referensi = 'KK-2024-001';

\echo ''
\echo '--- Audit log jurnal 1 ---'
SELECT action, actor, at, new_data->>'nomor_referensi' AS nomor
FROM audit_log WHERE table_name = 'journal_headers' ORDER BY at;

\echo ''
\echo '====================================================================='
\echo 'TES 2: POST JURNAL TIDAK SEIMBANG (HARUS ERROR)'
\echo '         D 300.000 != K 200.000'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-02',
        'nomor_referensi', 'KK-2024-002',
        'deskripsi', 'Tidak seimbang'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201'),
            'debit', 300000, 'credit', 0
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 200000
        )
    )
) AS hasil_post_2;

\echo ''
\echo '====================================================================='
\echo 'TES 3: POST JURNAL DUPLIKAT NO BUKTI (HARUS ERROR)'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-03',
        'nomor_referensi', 'KK-2024-001',
        'deskripsi', 'Duplikat'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201'),
            'debit', 100000, 'credit', 0
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 100000
        )
    )
) AS hasil_post_3;

\echo ''
\echo '====================================================================='
\echo 'TES 4: POST JURNAL LINE KEDUA NOL (HARUS ERROR)'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-04',
        'nomor_referensi', 'KK-2024-003',
        'deskripsi', 'Line nol'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201'),
            'debit', 0, 'credit', 0
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 0
        )
    )
) AS hasil_post_4;

\echo ''
\echo '====================================================================='
\echo 'TES 5: POST JURNAL LINE KEDUA ISI (HARUS ERROR)'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-05',
        'nomor_referensi', 'KK-2024-004',
        'deskripsi', 'Line keduanya isi'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201'),
            'debit', 100000, 'credit', 50000
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 150000
        )
    )
) AS hasil_post_5;

\echo ''
\echo '====================================================================='
\echo 'TES 6: POST JURNAL AKUN TIDAK ADA (HARUS ERROR)'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-06',
        'nomor_referensi', 'KK-2024-005',
        'deskripsi', 'Akun tidak ada'
    ),
    jsonb_build_array(
        jsonb_build_object('account_id', 999999, 'debit', 100000, 'credit', 0),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 100000
        )
    )
) AS hasil_post_6;

\echo ''
\echo '====================================================================='
\echo 'TES 7: UPDATE HEADER POSTED (HARUS ERROR - IMMUTABILITY)'
\echo '====================================================================='
UPDATE journal_headers
SET deskripsi = 'Diubah setelah posting'
WHERE nomor_referensi = 'KK-2024-001';

\echo ''
\echo '====================================================================='
\echo 'TES 8: DELETE HEADER POSTED (HARUS ERROR - IMMUTABILITY)'
\echo '====================================================================='
DELETE FROM journal_headers WHERE nomor_referensi = 'KK-2024-001';

\echo ''
\echo '====================================================================='
\echo 'TES 9: UPDATE LINE POSTED (HARUS ERROR - IMMUTABILITY)'
\echo '====================================================================='
UPDATE journal_lines
SET debit = 999999
WHERE header_id = (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001')
  AND account_id = (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201');

\echo ''
\echo '====================================================================='
\echo 'TES 10: DELETE LINE POSTED (HARUS ERROR - IMMUTABILITY)'
\echo '====================================================================='
DELETE FROM journal_lines
WHERE header_id = (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001')
  AND account_id = (SELECT id FROM chart_of_accounts WHERE kode_akun = '5201');

\echo ''
\echo '====================================================================='
\echo 'TES 11: INSERT LINE KE HEADER POSTED (HARUS ERROR - IMMUTABILITY)'
\echo '====================================================================='
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001'),
    (SELECT id FROM chart_of_accounts WHERE kode_akun = '2101'),
    100000, 0
);

\echo ''
\echo '====================================================================='
\echo 'TES 12: REVERSE JOURNAL (POSITIF - STORNO)'
\echo '====================================================================='
SELECT reverse_journal(
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001'),
    'Pembayaran dibatalkan karena faktur salah'
) AS hasil_reverse;

\echo ''
\echo '--- Verifikasi jurnal asal jadi REVERSED ---'
SELECT id, nomor_referensi, status_posting, reversed_by_header_id
FROM journal_headers WHERE nomor_referensi = 'KK-2024-001';

\echo ''
\echo '--- Verifikasi jurnal storno (POSTED, reversal_of_header_id terisi) ---'
SELECT id, nomor_referensi, status_posting, reversal_of_header_id
FROM journal_headers WHERE nomor_referensi LIKE 'STORNO-%';

\echo ''
\echo '--- Verifikasi lines storno (debit<->kredit ditukar) ---'
SELECT jh.nomor_referensi, coa.kode_akun, jl.debit, jl.credit
FROM journal_headers jh
JOIN journal_lines jl ON jl.header_id = jh.id
JOIN chart_of_accounts coa ON coa.id = jl.account_id
WHERE jh.nomor_referensi LIKE 'STORNO-%'
ORDER BY jh.id, jl.id;

\echo ''
\echo '====================================================================='
\echo 'TES 13: STORNO GANDA (HARUS ERROR)'
\echo '====================================================================='
SELECT reverse_journal(
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001'),
    'Coba storno lagi'
) AS hasil_reverse_2;

\echo ''
\echo '====================================================================='
\echo 'TES 13b: POST JURNAL KE-2 (untuk uji storno tanpa alasan)'
\echo '         D Utang Usaha 250.000 / K Kas 250.000'
\echo '====================================================================='
SELECT post_journal(
    jsonb_build_object(
        'tanggal_transaksi', '2024-12-07',
        'nomor_referensi', 'KK-2024-006',
        'deskripsi', 'Bayar utang usaha'
    ),
    jsonb_build_array(
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '2101'),
            'debit', 250000, 'credit', 0
        ),
        jsonb_build_object(
            'account_id', (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'),
            'debit', 0, 'credit', 250000
        )
    )
) AS hasil_post_6b;

\echo ''
\echo '====================================================================='
\echo 'TES 14: STORNO TANPA ALASAN (HARUS ERROR)'
\echo '====================================================================='
SELECT reverse_journal(
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-006'),
    ''
) AS hasil_reverse_3;

\echo ''
\echo '====================================================================='
\echo 'TES 15: VERIFIKASI HASH JURNAL ASLI (POSITIF - SEHARUSNYA MATCH)'
\echo '         (status tidak termasuk dalam hash, jadi tetap MATCH setelah storno)'
\echo '====================================================================='
SELECT * FROM verify_journal_hash(
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001')
);

\echo ''
\echo '====================================================================='
\echo 'TES 16: VERIFIKASI HASH SEMUA JURNAL'
\echo '====================================================================='
SELECT * FROM verify_all_journal_hashes();

\echo ''
\echo '====================================================================='
\echo 'TES 17: TAMPER TEST (ubah data lewat jalur superuser, bypass trigger)'
\echo '         -> verify_journal_hash HARUS false'
\echo '====================================================================='
-- session_replication_role=replica menonaktifkan SEMUA trigger (superuser only),
-- mensimulasikan tampering oleh DBA yang mengubah data tanpa rehash.
SET session_replication_role = replica;
UPDATE journal_headers
SET deskripsi = 'TAMPERED!'
WHERE nomor_referensi = 'KK-2024-001';
SET session_replication_role = DEFAULT;

SELECT * FROM verify_journal_hash(
    (SELECT id FROM journal_headers WHERE nomor_referensi = 'KK-2024-001')
);

\echo ''
\echo '====================================================================='
\echo 'TES 17B: VERIFIKASI HASH CHAIN (deteksi penyisipan/penghapusan di tengah)'
\echo '         (tamper di TES 17 seharusnya membuat data_ok=FALSE di header 1'
\echo '          dan chain_ok=FALSE di header 2 karena prev hash tidak konsisten)'
\echo '====================================================================='
SELECT * FROM verify_hash_chain();

\echo ''
\echo '====================================================================='
\echo 'TES 18: NET SALDO AKUN SETELAH STORNO (HARUS 0 UNTUK AKUN TERKAIT)'
\echo '         (jurnal asal + jurnal storno saling meniadakan)'
\echo '====================================================================='
SELECT coa.kode_akun, coa.nama_akun,
       COALESCE(SUM(jl.debit),0) AS total_debit,
       COALESCE(SUM(jl.credit),0) AS total_credit,
       COALESCE(SUM(jl.debit),0) - COALESCE(SUM(jl.credit),0) AS net_saldo
FROM journal_headers jh
JOIN journal_lines jl ON jl.header_id = jh.id
JOIN chart_of_accounts coa ON coa.id = jl.account_id
WHERE jh.nomor_referensi = 'KK-2024-001'
   OR jh.nomor_referensi LIKE 'STORNO-%'
GROUP BY coa.id, coa.kode_akun, coa.nama_akun
ORDER BY coa.kode_akun;

\echo ''
\echo '====================================================================='
\echo 'TES 19: AUDIT LOG (cek INSERT/UPDATE/DELETE tercatat)'
\echo '====================================================================='
SELECT table_name, action, actor, at,
       COALESCE(new_data->>'nomor_referensi', old_data->>'nomor_referensi') AS nomor,
       old_data->>'status_posting' AS old_status,
       new_data->>'status_posting' AS new_status
FROM audit_log
WHERE table_name IN ('journal_headers','journal_lines')
ORDER BY at;

\echo ''
\echo '====================================================================='
\echo 'SELESAI - Periksa bahwa:'
\echo '  TES 1  -> POSTED, hash terisi, verify=true'
\echo '  TES 2-6, 7-11, 13, 14 -> ERROR (ditolak)'
\echo '  TES 12 -> storno berhasil, asal REVERSED'
\echo '  TES 15,16 -> MATCH (semua jurnal utuh)'
\echo '  TES 17 -> verify=FALSE (tamper terdeteksi)'
\echo '  TES 18 -> net saldo = 0'
\echo '====================================================================='