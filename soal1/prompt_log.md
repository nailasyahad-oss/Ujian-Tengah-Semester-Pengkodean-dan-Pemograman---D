# Prompt Log — SOAL 1 UTS Pemrograman/Coding Akuntansi

Dokumen ini mencatat prompt yang digunakan bersama asisten AI (Kilocode) beserta ringkasan hasil pengerjaan.

---

## Prompt Utama (instruksi mahasiswa)

> Kerjakan SOAL 1 UTS Pemrograman/Coding Akuntansi (Desain Arsitektur Data, Normalisasi, & Penegakan Asas Berpasangan) di workspace ini.
>
> Konteks: Entitas ritel modern membangun modul General Ledger mandiri. Sistem lama mengalami unbalanced balance sheet karena validasi Debit-Kredit hanya di frontend, sehingga transaksi via API lolos tanpa pasangan Debit-Kredit valid. Solusi harus menegakkan integritas di level DATABASE (PostgreSQL), bukan hanya di aplikasi.
>
> Sub-tugas:
> 1. **1.1** Rancang ERD Mermaid untuk `chart_of_accounts`, `journal_headers`, `journal_lines` dengan kardinalitas benar, lalu jelaskan relasi di `erd.md`.
> 2. **1.2** Tulis `schema.sql` PostgreSQL idempoten: PK, FK ON DELETE RESTRICT, CHECK (`debit >= 0`, `credit >= 0`, `NOT (debit = 0 AND credit = 0)`, bonus `NOT (debit > 0 AND credit > 0)`), `NUMERIC(18,2) NOT NULL DEFAULT 0`, UNIQUE kode akun & nomor referensi, index FK, komentar Bahasa Indonesia. BONUS: constraint trigger DEFERRABLE INITIALLY DEFERRED yang memverifikasi `SUM(debit) = SUM(credit)` per header saat COMMIT.
> 3. **Pengujian** `seed_test.sql` + `test_constraints.sql`: positif (jurnal seimbang) dan negatif (debit/kredit negatif, nol keduanya, FK tak ada, DELETE akun terpakai, jurnal tidak seimbang ditolak trigger saat COMMIT). Jalankan nyata di PostgreSQL, perbaiki sampai sesuai harapan, simpan output.
> 4. **1.3** Tulis `analisis_audit_3nf.md` (~600–900 kata, akademis): normalisasi 1NF→2NF→3NF flat table vs header–line, anomali, audit trail & keamanan finansial, tabel perbandingan.
>
> Aturan: identifier SQL snake_case Bahasa Inggris; penjelasan Bahasa Indonesia; jangan mengarang hasil eksekusi; inisialisasi git dan commit per sub-soal.

---

## Ringkasan Hasil Pengerjaan

| Sub-tugas | Artefak | Status |
|---|---|---|
| ERD | `soal1/1.1_erd/erd.mmd`, `erd.md` | Selesai — 3 entitas, kardinalitas `1─0..*` & `1─1..*`, seluruh kolom & constraint didokumentasikan |
| DDL | `soal1/1.2_ddl/schema.sql` | Selesai — PK identity, 2 FK RESTRICT, 4 CHECK, `NUMERIC(18,2)`, 2 UNIQUE, 4 index, komentar `COMMENT ON`, BONUS trigger `fn_check_journal_balance` + `trg_journal_lines_balance_check` DEFERRABLE |
| Data uji | `soal1/1.2_ddl/seed_test.sql` | Selesai — 18 akun, 5 jurnal termasuk compound entry 3 baris; semua SEIMBANG |
| Tes | `soal1/1.2_ddl/test_constraints.sql` | Selesai — **10/10 PASS**, output asli di `execution_output.txt` |
| Analisis | `soal1/1.3_analisis/analisis_audit_3nf.md` | Selesai — ~800 kata, 3NF + audit + tabel perbandingan |
| Git | repo lokal | Selesai — commit per sub-soal |

### Catatan Lingkungan & Keputusan Teknis

1. **Docker & instalasi PostgreSQL tidak tersedia** di mesin mahasiswa. Digunakan **PostgreSQL 16.2** melalui paket Python `pgserver` (binary resmi PostgreSQL yang di-*bundle*), dijalankan sebagai instance lokal sementara dengan `initdb`/`pg_ctl` internal. psql versi terverifikasi: `psql (PostgreSQL) 16.2` — memenuhi syarat "PostgreSQL 14+".
2. **Kesalahan yang ditemukan & diperbaiki saat pengujian** (bukti iterasi nyata):
   - Sintaks plpgsql ganda `EXCEPTION WHEN x THEN ... EXCEPTION WHEN y THEN` ditolak PostgreSQL; diperbaiki menjadi satu klausa `EXCEPTION` dengan beberapa `WHEN`.
   - `RAISE NOTICE` di luar blok plpgsql (top-level PLE 8) mengganti menjadi meta-command `\echo`, karena `RAISE` hanya sah di dalam fungsi/DO block.
   - Format `%.2f` dalam `RAISE EXCEPTION` tidak didukung plpgsql (hanya substitusi `%` polos) — output sempat "(500000.00.2f)"; diperbaiki sehingga pesan menjadi "(500000.00)".
3. **Desain kunci**: DEFERABILITY trigger adalah solusi inti celah API — CHECK per baris tidak mungkin memeriksa `SUM` antar baris, sehingga trigger baru dijalankan saat `COMMIT` (lihat komentar BONUS di `schema.sql`).

### Cara Mereproduksi

```bash
python run_db_tests.py        # menjalankan PostgreSQL 16.2 lokal + 3 skrip SQL berurutan
```
atau manual dengan psql apa pun terhadap PostgreSQL 14+ (lihat README.md).