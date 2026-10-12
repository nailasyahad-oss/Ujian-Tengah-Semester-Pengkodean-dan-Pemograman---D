# SOAL 1 UTS — Desain Arsitektur Data, Normalisasi, & Penegakan Asas Berpasangan

**Mata Kuliah:** Pemrograman/Coding Akuntansi — FEB Undip
**Topik:** Modul General Ledger mandiri dengan integritas Debit–Kredit di level DATABASE (PostgreSQL)

## Latar Belakang

Sistem lama mengalami *unbalanced balance sheet* karena validasi Debit–Kredit hanya dilakukan di **frontend**. Akibatnya, transaksi yang masuk melalui **API** lolos tanpa pasangan Debit–Kredit yang valid. Solusi pada pengerjaan ini menegakkan integritas di level **basis data** — bukan hanya aplikasi — melalui kombinasi:

1. **CHECK constraint** level baris (`debit >= 0`, `credit >= 0`, tidak boleh keduanya nol, tidak boleh keduanya > 0),
2. **Foreign Key** `ON DELETE RESTRICT` dan **UNIQUE** sebagai penjaga integritas referensial,
3. **Constraint trigger `DEFERRABLE INITIALLY DEFERRED`** yang memverifikasi `SUM(debit) = SUM(credit)` per header saat `COMMIT` — inilah penutup celah "transaksi API tanpa pasangan Debit–Kredit".

## Struktur Artefak

```
soal1/
├── README.md                    <- berkas ini
├── 1.1_erd/
│   ├── erd.mmd                  <- diagram ERD Mermaid (erDiagram)
│   └── erd.md                   <- penjelasan relasi, kardinalitas, kolom
├── 1.2_ddl/
│   ├── schema.sql               <- DDL PostgreSQL lengkap + BONUS trigger
│   ├── seed_test.sql            <- data uji valid (positif)
│   ├── test_constraints.sql     <- skrip uji positif & negatif (10 skenario)
│   └── execution_output.txt     <- output eksekusi asli PostgreSQL 16.2
├── 1.3_analisis/
│   └── analisis_audit_3nf.md    <- esai analisis akademis (~800 kata)
└── prompt_log.md                <- log prompt AI + ringkasan hasil
```

## Arsitektur Tiga Tabel

| Tabel | Peran | Relasi |
|---|---|---|
| `chart_of_accounts` | Master akun (kode, nama, saldo normal, klasifikasi) | `1 ─── 0..* journal_lines` |
| `journal_headers` | Header transaksi (tanggal, bukti, status) | `1 ─── 1..* journal_lines` |
| `journal_lines` | Baris jurnal (akun, debit, kredit) | sisi "banyak" dari dua relasi |

ERD: [1.1_erd/erd.mmd](1.1_erd/erd.mmd) — penjelasan: [1.1_erd/erd.md](1.1_erd/erd.md)

## Cara Menjalankan

Prasyarat: PostgreSQL 14+ (dijalankan dan diuji pada **PostgreSQL 16.2**). Urutan eksekusi wajib:

```bash
# 1. Buat database (opsional)
psql -U postgres -c "CREATE DATABASE uts_gl;"

# 2. Jalankan DDL
psql -U postgres -d uts_gl -f soal1/1.2_ddl/schema.sql

# 3. Isi data uji valid
psql -U postgres -d uts_gl -f soal1/1.2_ddl/seed_test.sql

# 4. Jalankan seluruh tes positif & negatif
psql -U postgres -d uts_gl -f soal1/1.2_ddl/test_constraints.sql
```

`ON_ERROR_STOP` dibiarkan nonaktif (default) karena tes negatif memang harus menghasilkan error yang ditangkap blok `DO $$ ... EXCEPTION $$` dan dicatat sebagai `NOTICE`.

## Hasil Pengujian (10 skenario)

| # | Skenario | Jenis | Ekspektasi | Hasil |
|---|---|---|---|---|
| 1 | Kas D 1.000.000 / Pendapatan K 1.000.000 | Positif | Berhasil | **PASS** |
| 2 | `debit = -50000` | Negatif | Ditolak `check constraint journal_lines_debit_check` | **PASS** |
| 3 | `credit = -75000` | Negatif | Ditolak `check constraint journal_lines_credit_check` | **PASS** |
| 4 | `debit = 0 AND credit = 0` | Negatif | Ditolak `check constraint chk_journal_lines_not_both_zero` | **PASS** |
| 5 | `header_id = 999999` (tak ada) | Negatif | Ditolak `fk_journal_lines_header` | **PASS** |
| 6 | `account_id = 999999` (tak ada) | Negatif | Ditolak `fk_journal_lines_account` | **PASS** |
| 7 | `DELETE` akun 1101 (Kas, terpakai) | Negatif | Ditolak `fk_journal_lines_account ON DELETE RESTRICT` | **PASS** |
| 8 | Jurnal tidak seimbang (D 500.000 ≠ K 200.000) | Negatif | Ditolak trigger saat `COMMIT`: `JURNAL TIDAK SEIMBANG: Header ID 11 - Total Debit (500000.00) != Total Credit (200000.00)` | **PASS** |
| 9 | Jurnal 3 baris seimbang (D 2jt = K 1,5jt + 0,5jt) | Positif | Berhasil | **PASS** |
| 10 | `debit = 100000 AND credit = 50000` satu baris | Negatif (BONUS) | Ditolak `check constraint chk_journal_lines_not_both_positive` | **PASS** |

**10/10 PASS** — tidak ada satu skenario pun yang berperilaku menyimpang.

### Output Asli Eksekusi

Output lengkap diambil langsung dari terminal (disalin tanpa suntingan) dan tersimpan di [1.2_ddl/execution_output.txt](1.2_ddl/execution_output.txt). Bagian hasil test:

```
PLE 1 PASS: jurnal seimbang berhasil disimpan (header_id=6)
PLE 2 PASS: debit negatif ditolak. Error: new row for relation "journal_lines" violates check constraint "journal_lines_debit_check"
PLE 3 PASS: kredit negatif ditolak. Error: new row for relation "journal_lines" violates check constraint "journal_lines_credit_check"
PLE 4 PASS: baris nol ditolak. Error: new row for relation "journal_lines" violates check constraint "chk_journal_lines_not_both_zero"
PLE 5 PASS: FK header_id tidak ada ditolak. Error: insert or update on table "journal_lines" violates foreign key constraint "fk_journal_lines_header"
PLE 6 PASS: FK account_id tidak ada ditolak. Error: insert or update on table "journal_lines" violates foreign key constraint "fk_journal_lines_account"
PLE 7 PASS: DELETE akun terpakai ditolak. Error: update or delete on table "chart_of_accounts" violates foreign key constraint "fk_journal_lines_account" on table "journal_lines"
PLE 8: ERROR:  JURNAL TIDAK SEIMBANG: Header ID 11 - Total Debit (500000.00) != Total Credit (200000.00). Transaksi rollback.
PLE 9 PASS: jurnal multi-line seimbang berhasil (header_id=12)
PLE 10 PASS: baris D & K bersamaan ditolak. Error: new row for relation "journal_lines" violates check constraint "chk_journal_lines_not_both_positive"
```

Verifikasi akhir: seluruh 7 jurnal (5 seed + 2 test positif) berstatus **SEIMBANG**.

## Checklist Kesesuaian

### 1.1 ERD —
- [x] Tiga tabel: `chart_of_accounts`, `journal_headers`, `journal_lines`
- [x] Mermaid `erDiagram` dengan PK/FK, tipe data, kardinalitas
- [x] Kardinalitas `chart_of_accounts 1 ─ 0..* journal_lines` dan `journal_headers 1 ─ 1..* journal_lines`
- [x] `erd.md` menjelaskan setiap relasi dan alasan desain

### 1.2 DDL & Constraint —
- [x] PK `BIGINT GENERATED ALWAYS AS IDENTITY` konsisten di tiga tabel
- [x] FK `journal_lines.header_id` dan `journal_lines.account_id` dengan `ON DELETE RESTRICT`
- [x] CHECK `debit >= 0`, `credit >= 0`, `NOT (debit = 0 AND credit = 0)`, plus BONUS `NOT (debit > 0 AND credit > 0)`
- [x] `NUMERIC(18,2) NOT NULL DEFAULT 0` (bukan FLOAT)
- [x] CHECK `normal_balance IN ('DEBIT','CREDIT')`, CHECK `status_posting IN ('DRAFT','POSTED','REVERSED')`, UNIQUE `kode_akun` & `nomor_referensi`
- [x] Index pada FK: `idx_journal_lines_header_id`, `idx_journal_lines_account_id`
- [x] Komentar SQL Bahasa Indonesia (`COMMENT ON` + `--`)
- [x] `schema.sql` idempoten (`DROP ... IF EXISTS` + `CREATE OR REPLACE`)
- [x] BONUS: `fn_check_journal_balance()` + `trg_journal_lines_balance_check` `DEFERRABLE INITIALLY DEFERRED` — ditolak pada COMMIT transaksi tidak seimbang
- [x] Komentar menjelaskan bahwa CHECK per-baris tidak bisa memeriksa keseimbangan antar baris

### 1.3 Analisis —
- [x] `analisis_audit_3nf.md` Bahasa Indonesia, akademis, ~800 kata
- [x] Contoh flat table + redundansi; 1NF → 2NF → 3NF (parsial & transitif); anomali insert/update/delete
- [x] Audit trail & keamanan finansial; tabel perbandingan Flat vs Header–Line

### Aturan Kerja —
- [x] Identifier SQL `snake_case` Bahasa Inggris; penjelasan Bahasa Indonesia
- [x] SQL diuji nyata di PostgreSQL 16.2 (bukan hanya ditulis)
- [x] Tidak ada tabel di luar tiga tabel wajib (+ 1 fungsi & 1 trigger BONUS)
- [x] Output asli disalin tanpa karangan
- [x] `git init` + commit per sub-soal

## Analisis

Lihat [1.3_analisis/analisis_audit_3nf.md](1.3_analisis/analisis_audit_3nf.md): mengapa Header–Line mengalahkan tabel flat dari sisi normalisasi (redundansi, anomali) dan keamanan finansial (atomicity, audit trail, reversing entry, segregasi tugas).
