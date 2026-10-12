# Prompt Log — SOAL 2 UTS Pemrograman/Coding Akuntansi

## Prompt Utama (instruksi mahasiswa)

> Kerjakan SOAL 2 UTS (Otomasi Bisnis, Stored Procedures, & Database Trigger Persediaan) di folder `soal2/` repositori yang sama dengan soal1 (jangan mengubah isi soal1).
>
> Konteks: PT Diponegoro Logistik Utama memakai sistem persediaan perpetual. Saat staf mencatat retur/pengeluaran, saldo fisik gudang berubah tetapi nilai akun Persediaan Barang Dagang dan HPP di buku besar terlambat diperbarui → selisih saat stock opname. Solusi: otomasi di level database lewat trigger.
>
> Sub-tugas:
> 1. **2.1** DDL PERSIS (inventory_items, inventory_transactions) + FUNCTION/TRIGGER `trg_update_stock_and_journal`: auto-update stok (PURCHASE +, SALE −, ADJUSTMENT bertanda), validasi qty, anti-negatif dengan RAISE EXCEPTION + ERRCODE, kunci FOR UPDATE anti-concurrency, tangani item tak ditemukan. BONUS: jurnal GL berpasangan otomatis (PURCHASE/SALE/ADJUSTMENT) dengan total debit = kredit.
> 2. **2.2** Penjelasan race condition + Teknik 1 (SELECT FOR UPDATE), Teknik 2 (SERIALIZABLE + retry SQLSTATE 40001), teknik pelengkap (UPDATE bersyarat, CHECK), tabel perbandingan, catatan deadlock. Buat demo_race (2 proses/thread serentak, stok 1 unit) → tepat SATU berhasil, SATU ditolak, stok akhir 0.
>
> Aturan: identifier SQL snake_case; penjelasan Bahasa Indonesia; DDL inti jangan diubah; SQL wajib dijalankan nyata; output asli; commit per sub-soal.

---

## Ringkasan Hasil

| Sub-tugas | Artefak | Status |
|---|---|---|
| Skema | `2.1_trigger/00_schema.sql` | DDL persis soal + seed BRG001 (10×50.000), BRG002 |
| Trigger inti | `2.1_trigger/01_trigger.sql` | AFTER INSERT, FOR UPDATE, 4 validasi, ERRCODE 23514 |
| Tes inti | `2.1_trigger/02_test_trigger.sql` | 8 tahap — **semua PASS** (output_02_test.txt) |
| BONUS jurnal | `2.1_trigger/03_bonus_journal.sql` | gl_entries + jurnal berpasangan; 4/4 SEIMBANG; rollback aman |
| Penjelasan | `2.2_concurrency/penjelasan_concurrency.md` | ~500 kata + tabel perbandingan |
| Cuplikan kode | `01_select_for_update.sql`, `02_serializable_retry.sql` | Teknik 1 & 2 |
| Demo race | `2.2_concurrency/demo_race.py` | 3 teknik — **semua PASS** (output_demo_race.txt) |

### Keputusan Teknis & Asumsi
1. **AFTER INSERT** dipilih (soal meminta salah satu + alasannya): `trx_id SERIAL` baru terisi setelah insert (dibutuhkan untuk jurnal BONUS), CHECK/FK bawaan lebih dulu, dan RAISE EXCEPTION tetap membatalkan seluruh transaksi.
2. **ADJUSTMENT bertanda** (positif tambah, negatif kurang, 0 ditolak); PURCHASE/SALE wajib > 0 — dinyatakan di README + komentar kode.
3. **unit_cost statis** dari `inventory_items` (tanpa FIFO/average) — keterbatasan dinyatakan eksplisit.
4. **Nama trigger FK internal** PostgreSQL adalah `RI_ConstraintTrigger_*` (bukan nama constraint) — ditemukan saat pengujian Tahap 7b; untuk membuktikan jalur `RAISE EXCEPTION` fungsi kita sendiri, FK dimatikan sementara lewat dynamic SQL lalu dihidupkan lagi (transaksi utuh).

### Bug & Perbaikan Saat Pengujian (bukti iterasi nyata)
1. `RAISE EXCEPTION` dengan `%` lebih sedikit daripada argumen → *"too many parameters specified for RAISE"*; diperbaiki pada pesan ADJUSTMENT.
2. pg8000 (driver Python) **tidak punya** `Connection.execute` — harus melalui `cursor()`; semua helper (`reset_stock`, `get_stock`, `trx_count`) diperbaiki.
3. Server PostgreSQL lama masih memegang direktori data → konflik port; runner kini memakai direktori bertimestamp (`pgdata_soal2_<epoch>`).
4. `NameError: name 'msg' is not defined` (sisa variabel `txt` setelah refactor `sqlerror_code`) — ditemukan setelah menambahkan pelaporan exception tersimpan di thread; diperbaiki.
5. Pesan error pg8000 berupa **dict** (`{'C': '40001', ...}`) bukan string — parser SQLSTATE disesuaikan agar mendeteksi `42501/40001/23514` dengan benar.
6. Klaim "jumlah transaksi" di awal demo melebihi karena menghitung sisa data uji → tabel transaksi di-*reset* di awal setiap demo agar hitungan deterministik.
7. Assertion Teknik 2 semula menuntut kasir-A selalu menang → dibuat **invariant** (tepat satu OK, satu GAGAL) karena urutan antar-thread memang nondeterministik.

### Lingkungan
Docker & PostgreSQL lokal tidak tersedia → dipakai PostgreSQL **16.2** dari paket Python `pgserver` (biner resmi), driver Python **pg8000** murni-Python (alternatif `psycopg` gagal: DLL diblokir kebijakan Windows AppLocker).

### Cara Mereproduksi
```bash
python run_db_tests2.py                    # semua skrip + demo, output tersimpan otomatis
cd soal2/2.2_concurrency && python demo_race.py   # demo saja (sandbox otomatis bila PG* kosong)
```
