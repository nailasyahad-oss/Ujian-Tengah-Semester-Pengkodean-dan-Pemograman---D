# Penjelasan ERD dan Relasi

## Entitas dan Atribut

### 1. chart_of_accounts (Master Akun)
Tabel master untuk menyimpan daftar akun akuntansi.

| Atribut | Tipe | Constraint | Penjelasan |
|---------|------|------------|------------|
| id | BIGINT | PK, GENERATED ALWAYS AS IDENTITY | Surrogate key, auto-increment |
| kode_akun | VARCHAR(20) | UNIQUE, NOT NULL | Kode akun alami (mis. 1101, 4101), unik untuk lookup cepat |
| nama_akun | VARCHAR(200) | NOT NULL | Nama deskriptif akun |
| normal_balance | VARCHAR(10) | CHECK IN ('DEBIT','CREDIT'), NOT NULL | Tipe saldo normal akun: DEBIT untuk Aset/Beban, CREDIT untuk Liabilitas/Ekuitas/Pendapatan |
| classification | VARCHAR(20) | CHECK IN ('ASET','LIABILITAS','EKUITAS','PENDAPATAN','BEBAN'), NOT NULL | Klasifikasi laporan keuangan untuk Neraca/Laba Rugi |
| created_at | TIMESTAMP | DEFAULT now() | Audit trail pembuatan record |

### 2. journal_headers (Header Jurnal)
Tabel header transaksi jurnal - mewakili satu transaksi atomik.

| Atribut | Tipe | Constraint | Penjelasan |
|---------|------|------------|------------|
| id | BIGINT | PK, GENERATED ALWAYS AS IDENTITY | Surrogate key |
| tanggal_transaksi | DATE | NOT NULL | Tanggal transaksi (bukan timestamp agar konsisten dengan periode akuntansi) |
| nomor_referensi | VARCHAR(50) | UNIQUE, NOT NULL | Nomor bukti/bukti transaksi (mis. JV-2024-001), unik untuk audit trail |
| deskripsi | TEXT | - | Keterangan transaksi |
| status_posting | VARCHAR(20) | CHECK IN ('DRAFT','POSTED','REVERSED'), DEFAULT 'DRAFT' | Status: DRAFT (draft), POSTED (diposting, immutable), REVERSED (dibalik) |
| created_at | TIMESTAMP | DEFAULT now() | Waktu pembuatan record |
| posted_at | TIMESTAMP | - | Waktu posting (NULL jika DRAFT/REVERSED) |

### 3. journal_lines (Baris Jurnal / Detail Transaksi)
Tabel detail baris jurnal - setiap baris mewakili satu entri debit atau kredit.

| Atribut | Tipe | Constraint | Penjelasan |
|---------|------|------------|------------|
| id | BIGINT | PK, GENERATED ALWAYS AS IDENTITY | Surrogate key |
| header_id | BIGINT | FK → journal_headers(id), NOT NULL, ON DELETE RESTRICT | Referensi ke header jurnal |
| account_id | BIGINT | FK → chart_of_accounts(id), NOT NULL, ON DELETE RESTRICT | Referensi ke master akun |
| debit | NUMERIC(18,2) | NOT NULL DEFAULT 0, CHECK (debit >= 0) | Nominal debit, tidak boleh negatif |
| credit | NUMERIC(18,2) | NOT NULL DEFAULT 0, CHECK (credit >= 0) | Nominal kredit, tidak boleh negatif |
| (CHECK) | - | NOT (debit = 0 AND credit = 0) | Setiap baris harus punya nilai: DEBIT atau KREDIT, tidak boleh keduanya nol |
| (CHECK bonus) | - | NOT (debit > 0 AND credit > 0) | Opsional: mencegah baris dengan DEBIT & KREDIT bersamaan (satu baris = satu sisi) |
| created_at | TIMESTAMP | DEFAULT now() | Audit trail |

---

## Relasi dan Kardinalitas

### 1. chart_of_accounts (1) ─── (0..*) journal_lines
- **Jenis**: One-to-Many (Master → Detail)
- **FK**: `journal_lines.account_id` → `chart_of_accounts.id`
- **ON DELETE RESTRICT**: Mencegah penghapusan akun yang sudah memiliki transaksi (menjaga integritas histori & audit trail)
- **Alasan desain**: Satu akun (mis. Kas 1101) bisa dipakai di banyak baris jurnal berbeda. Memisahkan master akun dari transaksi memungkinkan:
  - Perubahan nama akun tidak merusak histori transaksi lama
  - Validasi saldo normal konsisten di level database
  - Rekonsiliasi per akun mudah dilakukan

### 2. journal_headers (1) ─── (1..*) journal_lines
- **Jenis**: One-to-Many (Header → Lines), minimal 1 line per header
- **FK**: `journal_lines.header_id` → `journal_headers.id`
- **ON DELETE RESTRICT**: Mencegah penghapusan header yang masih punya line (transaksi atomik utuh)
- **Alasan desain**: Satu transaksi (header) terdiri dari minimal 2 baris (double-entry). Pemisahan header-line memungkinkan:
  - Metadata transaksi (tanggal, bukti, status) disimpan sekali saja → no redundancy
  - Validasi keseimbangan SUM(debit) = SUM(credit) **per header** (via trigger DEFERRABLE)
  - Atomicity: POST/REVERSE berlaku untuk seluruh transaksi sekaligus
  - Audit trail: created_by, hash, digital signature bisa ditambahkan di header saja

---

## Catatan Desain Penting

1. **CHECK per-baris TIDAK bisa memeriksa keseimbangan antar baris**: Constraint `CHECK` di PostgreSQL hanya melihat satu baris per satu baris. Keseimbangan `SUM(debit) = SUM(credit)` melibatkan agregasi multi-baris dalam satu transaksi (header), sehingga memerlukan **trigger DEFERRABLE INITIALLY DEFERRED** yang dievaluasi saat `COMMIT`.

2. **NUMERIC(18,2) bukan FLOAT**: Menggunakan tipe exact numeric untuk menghindari kesalahan pembulatan floating-point pada nilai uang.

3. **Surrogate Key (BIGINT IDENTITY)**: Dipakai sebagai PK untuk performa join & stabilitas FK. Natural key (`kode_akun`, `nomor_referensi`) diberi UNIQUE constraint.

4. **Status Posting**: Mendukung workflow DRAFT → POSTED → REVERSED. Hanya POSTED yang immutable; REVERSED dibuat dengan jurnal pembalikan baru (bukan update data lama).