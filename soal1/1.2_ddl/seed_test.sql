-- =====================================================================
-- SOAL 1 UTS - SEED DATA UJI VALID (POSITIF)
-- Data master akun + jurnal seimbang untuk pengujian
-- Jalankan SETELAH schema.sql
-- =====================================================================

-- =====================================================================
-- 1. MASTER AKUN (chart_of_accounts)
-- =====================================================================
INSERT INTO chart_of_accounts (kode_akun, nama_akun, normal_balance, classification) VALUES
-- ASET (Normal Balance: DEBIT)
('1101', 'Kas', 'DEBIT', 'ASET'),
('1102', 'Bank', 'DEBIT', 'ASET'),
('1201', 'Piutang Usaha', 'DEBIT', 'ASET'),
('1501', 'Perlengkapan', 'DEBIT', 'ASET'),
('1801', 'Peralatan', 'DEBIT', 'ASET'),
('1901', 'Akumulasi Penyusutan Peralatan', 'CREDIT', 'ASET'), -- Kontra aset

-- LIABILITAS (Normal Balance: CREDIT)
('2101', 'Utang Usaha', 'CREDIT', 'LIABILITAS'),
('2201', 'Utang Gaji', 'CREDIT', 'LIABILITAS'),
('2301', 'Utang Pajak', 'CREDIT', 'LIABILITAS'),

-- EKUITAS (Normal Balance: CREDIT)
('3101', 'Modal Pemilik', 'CREDIT', 'EKUITAS'),
('3201', 'Prive', 'DEBIT', 'EKUITAS'), -- Kontra ekuitas

-- PENDAPATAN (Normal Balance: CREDIT)
('4101', 'Pendapatan Jasa', 'CREDIT', 'PENDAPATAN'),
('4102', 'Pendapatan Penjualan', 'CREDIT', 'PENDAPATAN'),

-- BEBAN (Normal Balance: DEBIT)
('5101', 'Beban Gaji', 'DEBIT', 'BEBAN'),
('5201', 'Beban Sewa', 'DEBIT', 'BEBAN'),
('5301', 'Beban Listrik & Air', 'DEBIT', 'BEBAN'),
('5401', 'Beban Penyusutan', 'DEBIT', 'BEBAN'),
('5501', 'Beban Lain-lain', 'DEBIT', 'BEBAN');

-- =====================================================================
-- 2. JURNAL SEIMBANG (POSITIF TEST CASES)
-- =====================================================================

-- -----------------------------------------------------
-- JURNAL 1: Kas Masuk - Pendapatan Jasa Rp 1.000.000
-- Debit: Kas (1101) 1.000.000
-- Credit: Pendapatan Jasa (4101) 1.000.000
-- -----------------------------------------------------
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
VALUES ('2024-01-15', 'JV-2024-001', 'Penerimaan pendapatan jasa tunai', 'POSTED');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
-- Debit Kas
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-001'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 1000000.00, 0),
-- Credit Pendapatan Jasa
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-001'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '4101'), 0, 1000000.00);

-- -----------------------------------------------------
-- JURNAL 2: Pembelian Perlengkapan Kredit Rp 500.000
-- Debit: Perlengkapan (1501) 500.000
-- Credit: Utang Usaha (2101) 500.000
-- -----------------------------------------------------
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
VALUES ('2024-01-20', 'JV-2024-002', 'Pembelian perlengkapan kredit', 'POSTED');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-002'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '1501'), 500000.00, 0),
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-002'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '2101'), 0, 500000.00);

-- -----------------------------------------------------
-- JURNAL 3: Bayar Gaji Rp 2.000.000 (3 lines - compound entry)
-- Debit: Beban Gaji (5101) 2.000.000
-- Credit: Kas (1101) 1.500.000
-- Credit: Utang Gaji (2201) 500.000
-- -----------------------------------------------------
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
VALUES ('2024-01-25', 'JV-2024-003', 'Pembayaran gaji karyawan sebagian tunai sebagian kredit', 'POSTED');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-003'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '5101'), 2000000.00, 0),
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-003'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '1101'), 0, 1500000.00),
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-003'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '2201'), 0, 500000.00);

-- -----------------------------------------------------
-- JURNAL 4: Penyusutan Peralatan Rp 100.000 (Adjusting Entry)
-- Debit: Beban Penyusutan (5401) 100.000
-- Credit: Akumulasi Penyusutan Peralatan (1901) 100.000
-- -----------------------------------------------------
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
VALUES ('2024-01-31', 'JV-2024-004', 'Penyusutan peralatan bulan Januari', 'POSTED');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-004'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '5401'), 100000.00, 0),
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-004'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '1901'), 0, 100000.00);

-- -----------------------------------------------------
-- JURNAL 5: DRAFT (belum posting) - untuk test status
-- -----------------------------------------------------
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting)
VALUES ('2024-02-01', 'JV-2024-005', 'Draft jurnal untuk test', 'DRAFT');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-005'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '1102'), 250000.00, 0),
((SELECT id FROM journal_headers WHERE nomor_referensi = 'JV-2024-005'),
 (SELECT id FROM chart_of_accounts WHERE kode_akun = '4102'), 0, 250000.00);

-- =====================================================================
-- VERIFIKASI DATA
-- =====================================================================
SELECT '=== CHART OF ACCOUNTS ===' AS info;
SELECT kode_akun, nama_akun, normal_balance, classification FROM chart_of_accounts ORDER BY kode_akun;

SELECT '=== JOURNAL HEADERS ===' AS info;
SELECT id, tanggal_transaksi, nomor_referensi, status_posting FROM journal_headers ORDER BY id;

SELECT '=== JOURNAL LINES (dengan nama akun) ===' AS info;
SELECT
    jh.nomor_referensi,
    coa.kode_akun,
    coa.nama_akun,
    jl.debit,
    jl.credit
FROM journal_lines jl
JOIN journal_headers jh ON jl.header_id = jh.id
JOIN chart_of_accounts coa ON jl.account_id = coa.id
ORDER BY jh.id, jl.id;

SELECT '=== VALIDASI KESEIMBANGAN PER HEADER ===' AS info;
SELECT
    jh.nomor_referensi,
    SUM(jl.debit) AS total_debit,
    SUM(jl.credit) AS total_credit,
    CASE WHEN SUM(jl.debit) = SUM(jl.credit) THEN 'SEIMBANG' ELSE 'TIDAK SEIMBANG' END AS status
FROM journal_headers jh
JOIN journal_lines jl ON jh.id = jl.header_id
GROUP BY jh.id, jh.nomor_referensi
ORDER BY jh.id;