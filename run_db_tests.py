"""
Runner: start fresh PostgreSQL 16 server (via pgserver bundled binaries)
dan jalankan schema.sql -> seed_test.sql -> test_constraints.sql
menggunakan psql. Output lengkap disimpan ke golive_run_output.txt.
"""
import subprocess
import sys
import os
import pgserver

PGINSTALL = os.path.join(os.path.dirname(pgserver.__file__), "pginstall")
PSQL = os.path.join(PGINSTALL, "bin", "psql.exe")
DATA_DIR = r"C:\Users\WIN11~1\AppData\Local\Temp\kilo\pgdata_soal1"
OUTPUT_FILE = r"C:\Users\WIN11~1\AppData\Local\Temp\kilo\run_output.txt"

def run_psql(db, script_path, label):
    print(f"\n{'='*60}\n>>> MENJALANKAN: {label} ({script_path})\n{'='*60}")
    cmd = [
        PSQL,
        "-d", db.get_uri(),     # connection string via -d (explicit dbname)
        "-v", "ON_ERROR_STOP=0",  # tetap jalan meski ada error (tes negatif)
        "-f", script_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    output = result.stdout + result.stderr
    print(output)
    return output

def main():
    # Bersihkan data dir lama agar fresh
    import shutil
    import time
    data_dir = DATA_DIR
    for i in range(5):
        try:
            if os.path.exists(data_dir):
                shutil.rmtree(data_dir)
            break
        except PermissionError:
            time.sleep(2)
    else:
        print(f"WARNING: tidak bisa menghapus {data_dir}, gunakan dir baru dengan suffix")
        data_dir = data_dir + f"_{int(time.time())}"

    print(">>> Menyalakan server PostgreSQL 16 (pgserver sandbox)...")
    db = pgserver.get_server(data_dir, cleanup_mode=None)
    print(f">>> Server aktif. URI: {db.get_uri()}")

    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(os.path.dirname(base), "workspace", "soal1")  # fallback
    # Tentukan base dir kerja: current workspace
    workspace = r"D:\Ujian-Tengah-Semester-Pengkodean-dan-Pemograman---D\soal1"
    schema = os.path.join(workspace, "1.2_ddl", "schema.sql")
    seed = os.path.join(workspace, "1.2_ddl", "seed_test.sql")
    test = os.path.join(workspace, "1.2_ddl", "test_constraints.sql")

    all_output = []
    all_output.append(f"# Output Eksekusi PostgreSQL - SOAL 1 UTS\n")
    all_output.append(f"PostgreSQL version: 16.2 (pgserver sandbox)\n")

    out_schema = run_psql(db, schema, "schema.sql (DDL)")
    all_output.append("\n\n## 1. schema.sql\n```\n" + out_schema + "```\n")

    out_seed = run_psql(db, seed, "seed_test.sql (data positif)")
    all_output.append("\n\n## 2. seed_test.sql\n```\n" + out_seed + "```\n")

    out_test = run_psql(db, test, "test_constraints.sql (positif & negatif)")
    all_output.append("\n\n## 3. test_constraints.sql\n```\n" + out_test + "```\n")

    # Verifikasi final keseimbangan
    verify_sql = r"""SELECT 'FINAL' AS info;
SELECT jh.nomor_referensi, SUM(jl.debit) AS total_debit, SUM(jl.credit) AS total_credit,
       CASE WHEN SUM(jl.debit) = SUM(jl.credit) THEN 'SEIMBANG' ELSE 'TIDAK SEIMBANG' END AS status
FROM journal_headers jh JOIN journal_lines jl ON jh.id = jl.header_id
GROUP BY jh.id, jh.nomor_referensi ORDER BY jh.id;"""
    print(">>> Verifikasi keseimbangan akhir...")
    cmd = [PSQL, "-d", db.get_uri(), "-c", verify_sql]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    print(result.stdout + result.stderr)
    all_output.append("\n\n## 4. Verifikasi Keseimbangan Akhir\n```\n" + result.stdout + result.stderr + "```\n")

    # Tulis output lengkap
    final = "".join(all_output)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(final)
    print(f"\n>>> Output lengkap tersimpan: {OUTPUT_FILE}")

    db.cleanup()
    print(">>> Server dimatikan & dibersihkan.")

if __name__ == "__main__":
    main()
