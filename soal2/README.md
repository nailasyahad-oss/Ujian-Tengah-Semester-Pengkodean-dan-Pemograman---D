# SOAL 2 UTS — Otomasi Bisnis, Stored Procedures, & Database Trigger Persediaan

**Mata Kuliah:** Pemrograman/Coding Akuntansi — FEB Undip
**Studi Kasus:** PT Diponegoro Logistik Utama — sistem persediaan *perpetual*
**Dijalankan & diuji pada:** PostgreSQL 16.2 (sandbox `pgserver`, binary resmi PostgreSQL; memenuhi syarat PostgreSQL 14+)

## Masalah & Solusi

Staf mencatat retur/pengeluaran barang: **stok fisik gudang berubah, tetapi nilai akun Persediaan Barang Dagang dan HPP di buku besar terlambat diperbarui** → selisih saat *stock opname*. Solusi: otomasi di level **database** — setelah setiap `INSERT` ke `inventory_transactions`, trigger otomatis (1) memutakhirkan `inventory_items.stock_qty`, (2) menolak stok negatif dan qty tidak valid, (3) mengunci baris item untuk aman dari *race condition*, dan (4) [BONUS] membuat jurnal GL berpasangan.

## Struktur Artefak

```
soal2/
├── README.md                       <- berkas ini
├── 2.1_trigger/
│   ├── 00_schema.sql               # DDL PERSIS dari soal + seed BRG001/BRG002
│   ├── 01_trigger.sql              # FUNCTION + TRIGGER trg_update_stock_and_journal (inti)
│   ├── 02_test_trigger.sql         # uji positif & negatif (8 tahap)
│   ├── 03_bonus_journal.sql        # BONUS: gl_entries + jurnal otomatis + uji
│   └── output_*.txt                # output ASLI eksekusi tiap skrip
├── 2.2_concurrency/
│   ├── penjelasan_concurrency.md   # esai ~500 kata + tabel perbandingan
│   ├── 01_select_for_update.sql    # cuplikan Teknik 1
│   ├── 02_serializable_retry.sql   # cuplikan Teknik 2 + retry
│   ├── demo_race.py                # simulasi 2 kasir (3 teknik), output asli
│   └── output_demo_race.txt        # output ASLI demo_race.py
└── prompt_log.md                   # log prompt AI + ringkasan hasil
```

## Asumsi Eksplisit (wajib dinyatakan menurut soal)

1. **Semantik qty `ADJUSTMENT` = bertanda (signed)**: `qty > 0` menambah stok (selisih lebih: temuan fisik > buku), `qty < 0` mengurangi stok (selisih kurang: rusak/susut/hilang), `qty = 0` **ditolak**. Untuk `PURCHASE` dan `SALE`, qty wajib `> 0` (tidak berartanda); kegunaan bertanda hanya pada `ADJUSTMENT`.
2. **Trigger AFTER INSERT** (bukan BEFORE): (a) `trx_id SERIAL` baru terisi **setelah** baris disimpan — hanya dalam AFTER INSERT, `NEW.trx_id` memiliki nilai untuk referensi jurnal BONUS; (b) CHECK/FK bawaan DDL sudah dievaluasi lebih dulu; (c) `RAISE EXCEPTION` di AFTER trigger tetap membatalkan **seluruh transaksi** sehingga baris transaksi & mutasi stok tidak tersimpan.
3. **`unit_cost` statis dari `inventory_items`**: nilai jurnal = `qty × unit_cost` yang tersimpan. Tidak ada FIFO/LIFO/*moving average* — ini keterbatasan sadar; bila diperlukan, perhitungan biaya per lapisan butuh tabel pendukung (di luar tiga tabel inti).
4. **Sumber jurnal pembelian diasumsikan tunai** (`K Kas`; alternatif `K Utang Usaha`). Sementara, `SALE` hanya mengakui HPP (pengakuan pendapatan penjualan di luar cakupan trigger ini).
5. **DDL inti tidak diubah**: `inventory_items` dan `inventory_transactions` dibuat **persis** seperti soal di `00_schema.sql`. Tambahan apa pun (mis. `gl_entries`, `CHECK stock_qty >= 0`) hanya berada di file BONUS/opsional yang dilabeli jelas.

## Cara Menjalankan

```bash
# 0. (opsional) buat database
psql -U postgres -c "CREATE DATABASE uts_inv;"

# 1. skema persis soal + seed
psql -U postgres -d uts_inv -f soal2/2.1_trigger/00_schema.sql
# 2. function + trigger inti
psql -U postgres -d uts_inv -f soal2/2.1_trigger/01_trigger.sql
# 3. uji positif & negatif
psql -U postgres -d uts_inv -f soal2/2.1_trigger/02_test_trigger.sql
# 4. BONUS jurnal GL (meng-extend fungsi dengan nama sama)
psql -U postgres -d uts_inv -f soal2/2.1_trigger/03_bonus_journal.sql
```

Atau sekali jalan semuanya (butuh Python + `pgserver` + `pg8000`):

```bash
python run_db_tests2.py      # menjalankan 00→01→02→03 lalu demo_race.py
```

Untuk demo concurrency saja (otomatis membuat sandbox bila PG* env kosong):

```bash
cd soal2/2.2_concurrency
python demo_race.py
```

## Hasil Pengujian

### 2.1 Trigger — 100% sesuai harapan

| Tahap | Skenario | Ekspektasi | Hasil |
|---|---|---|---|
| 1 | Seed BRG001 stok 10, unit_cost 50.000 | terlihat | **PASS** |
| 2 | PURCHASE 5 → stok 15 | stok 15 | **PASS** |
| 3 | SALE 3 → stok 12 | stok 12 | **PASS** |
| 4 | ADJUSTMENT +2 → 14; ADJUSTMENT −4 → 10 | 14, lalu 10 | **PASS** |
| 5 | NEGATIF SALE 11 saat stok 10 | ERROR 23514, stok tetap 10, 0 baris trx baru | **PASS** |
| 6 | NEGATIF qty ≤ 0 (SALE 0, SALE−3, PURCHASE 0, PURCHASE−10, ADJUSTMENT 0) | 5× ERROR, 0 baris trx baru | **PASS** |
| 7 | NEGATIF item 'TIDAKADA'; ADJUSTMENT −100 (stok 10) | ERROR (fungsi & FK), stok tetap 10 | **PASS** |
| 7b | NEGATIF item tak ditemukan (jalur fungsi, FK sementara dimatikan) | `ITEM TIDAK DITEMUKAN: item_id TIDAKADA tidak ada di inventory_items` | **PASS** |
| 8 | Bukti akhir: 4 baris trx valid, net_moved = 0, nilai persediaan 10 × 50.000 = 500.000 | konsisten | **PASS** |

**Output asli (kutipan, `output_02_test.txt`):**

```
NOTICE:  POSITIF PURCHASE 5: stok sesudah = 15 (harap 15) -> PASS
NOTICE:  POSITIF SALE 3: stok sesudah = 12 (harap 12) -> PASS
NOTICE:  POSITIF ADJUSTMENT +2: stok = 14 (harap 14) -> PASS
NOTICE:  POSITIF ADJUSTMENT -4: stok = 10 (harap 10) -> PASS
NOTICE:  NEGATIF SALE 11 -> PASS (stok & jumlah trx tidak berubah)
NOTICE:  NEGATIF SALE qty=0 -> PASS: QTY TIDAK VALID: SALE harus qty > 0 (diberikan 0)
NOTICE:  NEGATIF ADJUSTMENT qty=0 -> PASS: QTY TIDAK VALID: ADJUSTMENT tidak boleh 0 (diberikan 0, qty bertanda)
NOTICE:  NEGATIF ADJUSTMENT -100 (stok 10) -> PASS: STOK TIDAK MENCUKUPI: item_id BRG001, stok tersedia 10, qty diminta -100, stok menjadi -90. Transaksi ditolak (ROLLBACK).
NOTICE:  NEGATIF 7b PASS (ditolak oleh fungsi kita): ITEM TIDAK DITEMUKAN: item_id TIDAKADA tidak ada di inventory_items
```

Pesan penolakan penuh (stok tidak cukup) memuat **item_id, stok tersedia, qty diminta, dan stok akhir** — memenuhi 2.1(b) dengan `ERRCODE 'check_violation'` (SQLSTATE 23514) sehingga seluruh transaksi di-ROLLBACK.

### BONUS Jurnal GL — keseimbangan & rollback terbukti

```
 trx_id | item_id |  trx_type  | qty |         account_name         |   debit   |  credit    
     13 | BRG001  | PURCHASE   |   5 | Persediaan Barang Dagangan   | 250000.00 |      0.00
     13 | BRG001  | PURCHASE   |   5 | Kas                          |      0.00 | 250000.00
     14 | BRG001  | SALE       |   3 | Beban Pokok Pendapatan (HPP) | 150000.00 |      0.00
     14 | BRG001  | SALE       |   3 | Persediaan Barang Dagangan   |      0.00 | 150000.00
     15 | BRG001  | ADJUSTMENT |   2 | Persediaan Barang Dagangan   | 100000.00 |      0.00
     15 | BRG001  | ADJUSTMENT |   2 | Selisih Persediaan           |      0.00 | 100000.00
     16 | BRG001  | ADJUSTMENT |  -4 | Selisih Persediaan           | 200000.00 |      0.00
     16 | BRG001  | ADJUSTMENT |  -4 | Persediaan Barang Dagangan   |      0.00 | 200000.00

 trx_id | total_debit | total_credit |  status    
     13 |   250000.00 |    250000.00 | SEIMBANG
     14 |   150000.00 |    150000.00 | SEIMBANG
     15 |   100000.00 |    100000.00 | SEIMBANG
     16 |   200000.00 |    200000.00 | SEIMBANG

NOTICE:  BONUS rollback jurnal -> PASS (tidak ada jurnal yatim)
```

Nilai persediaan = `stock_qty × unit_cost` = 10 × 50.000 = **500.000.00**; SALE ilegal tidak menghasilkan baris `gl_entries` (tetap 8 baris).

### 2.2 Concurrency — 3 teknik, semua PASS

Dua kasir, stok tersisa **1 unit**, `pg_sleep` memaksa tumpang tindih:

**TEKNIK 1 — `SELECT ... FOR UPDATE` (trigger)** → kasir-A COMMIT sukses; kasir-B **menunggu kunci**, lalu membaca stok terbaru = 0 dan ditolak trigger:

```
[kasir-A] COMMIT sukses
[kasir-B] ROLLBACK (error)
[kasir-B] ERROR (SQLSTATE 23514): STOK TIDAK MENCUKUPI: item_id BRG001, stok tersedia 0, qty diminta 1, stok menjadi -1...
Stok akhir    : 0  (harap 0, BUKAN -1)
Jumlah trx SALE BRG001: 1  (harap 1)
TEKNIK 1 -> PASS (tepat SATU berhasil, SATU ditolak)
```

**TEKNIK 2 — `BEGIN ISOLATION LEVEL SERIALIZABLE`** → satu COMMIT sukses, satunya **SQLSTATE 40001**, retry menolak dengan bersih:

```
[kasir-A] SERIALIZABLE, baca stok = 1
[kasir-B] SERIALIZABLE, baca stok = 1
[kasir-B] COMMIT sukses
[kasir-A] ERROR (SQLSTATE 40001): could not serialize access due to read/write dependencies among transactions
[kasir-B(retry)] percobaan 1: baca stok = 0
[kasir-B(retry)] percobaan 1: stok tidak cukup -> ROLLBACK (penolakan BERSIH, bukan error 40001)
TEKNIK 2 -> PASS
```

**TEKNIK 3 — UPDATE bersyarat atomik** → satu `rowcount=1`, satu `rowcount=0`, tanpa retry/deadlock:

```
[kasir-A] UPDATE bersyarat: rowcount=1 -> BERHASIL
[kasir-B] UPDATE bersyarat: rowcount=0 -> DITOLAK (stok tidak cukup)
Stok akhir    : 0  (harap 0, BUKAN -1)
TEKNIK 3 -> PASS
```

Output lengkap: `soal2/2.2_concurrency/output_demo_race.txt`.

## Checklist Kesesuaian

### 2.1a — otomasi mutasi
- [x] INSERT `inventory_transactions` otomatis memperbarui `stock_qty` (PURCHASE +, SALE −, ADJUSTMENT bertanda ±) — terbukti Tahap 2–4
- [x] Validasi dasar: PURCHASE/SALE wajib qty > 0; ADJUSTMENT boleh negatif, tidak boleh 0

### 2.1b — anti-negative
- [x] Hasil akhir `stock_qty < 0` → `RAISE EXCEPTION` informatif (item_id, stok tersedia, qty diminta, stok akhir) + `ERRCODE 'check_violation'`; transaksi ROLLBACK, baris tidak tersimpan

### 2.1c — concurrency
- [x] Fungsi mengunci baris item dengan `SELECT ... FROM inventory_items WHERE item_id = NEW.item_id FOR UPDATE` sebelum hitung & update — bukan pola baca-cek-di-aplikasi-tulis (dibuktikan demo Teknik 1)

### 2.1d — item tidak ada
- [x] `SELECT ... FOR UPDATE` tanpa hasil → `RAISE EXCEPTION 'ITEM TIDAK DITEMUKAN: ...'` (dibuktikan Tahap 7b)

### BONUS
- [x] `gl_entries` + perluasan trigger: PURCHASE (D Persediaan/K Kas), SALE (D HPP/K Persediaan), ADJUSTMENT ± (D/K Persediaan vs Selisih Persediaan)
- [x] Total debit = total kredit per transaksi (4/4 SEIMBANG); jurnal ikut ROLLBACK bila stok negatif
- [x] Asumsi biaya (unit_cost statis, tanpa FIFO/average) dinyatakan eksplisit di kode & README

### 2.2 — concurrency
- [x] `penjelasan_concurrency.md` ~500 kata: penyebab race condition, Teknik 1 & 2 lengkap dengan cuplikan, Teknik pelengkap, tabel perbandingan, rekomendasi kasir ritel, catatan deadlock
- [x] `01_select_for_update.sql` & `02_serializable_retry.sql` (cuplikan)
- [x] `demo_race.py`: 2 thread/koneksi, `pg_sleep` memaksa tumpang tindih, hasil: tepat SATU berhasil, SATU ditolak, stok akhir 0 (bukan −1) untuk kedua teknik — output asli tersimpan

### Aturan Kerja
- [x] Identifier `snake_case`; penjelasan Bahasa Indonesia; DDL inti **persis** soal
- [x] Semua SQL dijalankan nyata di PostgreSQL 16.2; output asli disalin, tidak dikarang
- [x] Commit git per sub-soal

