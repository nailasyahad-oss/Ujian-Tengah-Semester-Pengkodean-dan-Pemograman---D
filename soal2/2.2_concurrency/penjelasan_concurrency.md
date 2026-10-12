# Penanganan Concurrency (Race Condition) pada Kasir Persediaan

## Mengapa Terjadi Race Condition

Skenario khas: stok tersisa **1 unit** dan dua kasir menyelesaikan penjualan item yang sama pada waktu bersamaan. Pola aplikasi naif adalah *read–check–write*: `SELECT stock_qty` (membaca 1) → aplikasi memeriksa `1 >= 1` (lolos) → `INSERT` transaksi `SALE` → *commit*. Di tingkat isolasi default PostgreSQL, **READ COMMITTED**, setiap *statement* melihat *snapshot* pernyataan sendiri. Karena pembacaan stok oleh kedua kasir terjadi sebelum salah satu menulis, **kedua transaksi membaca nilai stok yang sama (1)**, keduanya lulus pemeriksaan, dan keduanya masuk. Hasil akhir: stok menjadi **−1** (*overselling*). Celahnya bukan pada urutan langkah, melainkan pada **tidak adanya kunci** antara membaca dan menulis.

## Teknik 1: Pessimistic Locking — `SELECT ... FOR UPDATE`

Kasir mengunci baris item sebelum memeriksa:

```sql
BEGIN;
SELECT stock_qty FROM inventory_items WHERE item_id = 'BRG001' FOR UPDATE;
-- transaksi kedua (brg sama) BERHENTI di sini sampai yang pertama COMMIT
-- setelah menunggu, ia membaca stok TERBARU (row version baru)
-- mis. stok = 0 -> aplikasi menolak, ROLLBACK
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('BRG001','SALE',1);
COMMIT;
```

Urutan eksekusi: transaksi A mengunci baris, menghitung, dan menulis; transaksi B menunggu kunci; begitu A *commit*, B melanjutkan dan **membaca stok terbaru (0)**, bukan snapshot lama, sehingga B ditolak sebelum menulis — tidak ada *overselling*. Kunci ini juga dipakai di dalam fungsi trigger `trg_update_stock_and_journal()` (SOAL 2.1c), sehingga proteksi berlaku walau transaksi datang lewat API.

## Teknik 2: Isolation Level SERIALIZABLE

Buka transaksi dengan `BEGIN ISOLATION LEVEL SERIALIZABLE`. PostgreSQL kemudian mendeteksi pola konflik: jika ada transaksi lain yang mengubah baris yang sudah dibaca, ia menolak dengan **SQLSTATE `40001 serialization_failure`** (kadang pada *commit*). Konsekuensinya, aplikasi **wajib menyiapkan retry**: tangkap `40001`, ulangi dari `BEGIN` (bacaan baru), batasi jumlah percobaan agar tidak berputar terus. Cuplikan kode ada di `02_serializable_retry.sql`.

## Teknik Pelengkap

1. **UPDATE bersyarat atomik**: `UPDATE inventory_items SET stock_qty = stock_qty - :qty WHERE item_id = :id AND stock_qty >= :qty`, lalu periksa jumlah baris terdampak (`rowcount = 0` → tolak). Satu pernyataan, satu rencana eksekusi, tidak ada jendela antara cek dan tulis.
2. **CHECK (`stock_qty >= 0`)** sebagai jaring terakhir. Karena DDL soal tidak boleh diubah di bagian inti, alter ini hanya opsional di luar bagian inti.

## Tabel Perbandingan

| Kriteria | FOR UPDATE | SERIALIZABLE | UPDATE bersyarat |
|---|---|---|---|
| Throughput | Sedang (antrean kunci) | Rendah-sedang (banyak abort) | **Tinggi** |
| Kompleksitas | Rendah | Sedang (wajib retry) | **Sangat rendah** |
| Perlu retry? | Tidak (antre) | **Ya** (SQLSTATE 40001) | Tidak |
| Risiko deadlock | Ada bila urutan kunci beda | Ada | Rendah (satu pernyataan/baris) |
| Pesan error | Kontrol penuh | 40001 generik | Periksa rowcount |

**Rekomendasi kasir ritel**: **UPDATE bersyarat atomik** untuk operasi satuan (satu transaksi–satu item), ditambah **FOR UPDATE dalam trigger** untuk perlindungan menyeluruh dan **CHECK `stock_qty >= 0`** sebagai penjaga karang. SERIALIZABLE dipakai bila aturan bisnis perlu validasi antar-baris kompleks, dengan mekanisme *retry* wajib di aplikasi.

## Catatan Deadlock

Jika satu transaksi menyentuh banyak item, kuncilah baris dalam urutan konsisten (`ORDER BY item_id`). Kunci yang diperlintahkan dalam urutan berbeda oleh dua transaksi adalah resep *deadlock* — PostgreSQL mendeteksinya (SQLSTATE `40P01`), tetapi *retry* tetap sebaiknya dilakukan oleh aplikasi.
