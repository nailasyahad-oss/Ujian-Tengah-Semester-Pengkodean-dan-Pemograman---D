# PROGRESS.md — SOAL 3 UTS

Checkpoint per file. Diperbarui setelah tiap file selesai.

## Status per file

| File | Status | Catatan |
|---|---|---|
| db/01_schema_additions.sql | [~] SEBAGIAN | Ada bug: `verify_journal_hash` didefinisikan BOOLEAN di sini tapi TABLE di 03 (CREATE OR REPLACE tidak bisa ubah return type → error). `compute_journal_hash` pakai `ORDER BY jl.id` di dalam UNION (kolom tidak di output → error). Hash menyertakan status_posting (masalah saat reversal). Perlu diperbaiki. |
| db/02_immutability.sql | [~] SEBAGIAN | Bug: header trigger menolak perubahan `reversed_by_header_id` & `hash_checksum` saat reversal (padahal harus diizinkan). DELETE header POSTED dengan flag allow_reversal masih diizinkan (harusnya selalu ditolak). Lines trigger menolak UPDATE/DELETE dengan flag on (harusnya selalu ditolak). |
| db/03_hash_checksum.sql | [~] SEBAGIAN | Bug: `verify_hash_chain` pakai `DECLARE ... := ...;` inline di dalam LOOP (sintaks PL/pgSQL tidak valid). `compute_journal_hash` menyertakan status_posting + ORDER BY di UNION. |
| db/04_rpc_post_and_reverse.sql | [~] SEBAGIAN | `current_setting('request.jwt.claim.sub', TRUE)` bisa NULL di lokal (perlu COALESCE current_user). Logika OK. |
| db/05_tests.sql | [~] SEBAGIAN | Bug: JSONB berisi subquery SQL mentah di dalam string (tidak valid — harus pakai jsonb_build_object/array). TES 14 (storno tanpa alasan) tidak menguji validasi alasan karena status sudah REVERSED. TES 18 pakai IN dengan pattern LIKE (salah). |
| frontend/index.html | [ ] BELUM ADA | Form voucher kas keluar (React + Tailwind CDN, satu file). |
| frontend/.env.example | [ ] BELUM ADA | SUPABASE_URL, SUPABASE_ANON_KEY. |
| docs/3.1a_gemini_canvas_prompt.md | [ ] BELUM ADA | Template (kerangka saja, [ISI MANUAL]). |
| docs/3.1b_notebooklm_verifikasi.md | [ ] BELUM ADA | Template (kerangka saja, [ISI DARI NOTEBOOKLM]). |
| docs/3.2_spesifikasi_audit_trail.md | [ ] BELUM ADA | Spesifikasi fungsi + diagram Mermaid. |
| README.md | [ ] BELUM ADA | Ringkasan + cara menjalankan + output asli. |
| prompt_log.md | [ ] BELUM ADA | Log prompt. |

## Rencana perbaikan (urut)
1. fix(soal3): 01_schema_additions.sql — hapus fungsi hash (pindah ke 03), perbaiki typo
2. fix(soal3): 02_immutability.sql — izinkan reversed_by_header_id/hash_checksum saat reversal; DELETE selalu ditolak
3. fix(soal3): 03_hash_checksum.sql — canonical form tanpa status_posting; perbaiki ORDER BY & verify_hash_chain
4. fix(soal3): 04_rpc_post_and_reverse.sql — COALESCE actor
5. fix(soal3): 05_tests.sql — JSONB valid via jsonb_build_object/array; perbaiki TES 14/18
6. feat(soal3): jalankan 01→05 di PostgreSQL 16.2, simpan output asli
7. feat(soal3): frontend/index.html + .env.example
8. feat(soal3): docs/3.2_spesifikasi_audit_trail.md
9. feat(soal3): docs/3.1a + 3.1b (kerangka template)
10. feat(soal3): README.md + prompt_log.md

## Lingkungan uji
PostgreSQL 16.2 via pgserver (sandbox), driver pg8000. Basis: reuse skema soal1 (chart_of_accounts, journal_headers, journal_lines).

LANJUT DARI: fix 01_schema_additions.sql
