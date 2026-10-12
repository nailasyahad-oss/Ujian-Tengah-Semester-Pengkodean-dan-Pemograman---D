"""
SOAL 3 UTS - Runner pengujian lengkap.
Menjalankan (urut):
  soal1/1.2_ddl/schema.sql        (base schema: chart_of_accounts,
                                   journal_headers, journal_lines)
  -> soal3/db/01_schema_additions.sql   (audit columns, audit_log, audit trigger)
  -> soal3/db/02_immutability.sql       (immutability triggers)
  -> soal3/db/03_hash_checksum.sql    (SHA-256 hash & verifikasi)
  -> soal3/db/04_rpc_post_and_reverse.sql (post_journal / reverse_journal)
  -> soal3/db/05_tests.sql            (19 uji positif/negatif)
dengan PostgreSQL 16.2 (pgserver sandbox). Output asli disimpan per berkas.
"""
import os
import re
import subprocess
import tempfile
import time

import pgserver

WORKSPACE = r"D:\Ujian-Tengah-Semester-Pengkodean-dan-Pemograman---D"
SOAL1 = os.path.join(WORKSPACE, "soal1", "1.2_ddl")
SOAL3 = os.path.join(WORKSPACE, "soal3")
HERE = os.path.dirname(os.path.abspath(__file__))
PSQL = os.path.join(os.path.dirname(pgserver.__file__), "pginstall", "bin", "psql.exe")
TMP = tempfile.gettempdir()


def run_psql(params, script, label, log):
    print(f"\n>>> {label}")
    dsn = (f"host={params['host']} port={params['port']} user={params['user']} "
           f"dbname={params['database']}")
    r = subprocess.run([PSQL, "-d", dsn, "-f", script],
                       capture_output=True, text=True, encoding="utf-8")
    out = r.stdout + r.stderr
    print(out)
    with open(log, "w", encoding="utf-8") as f:
        f.write(f"# SOAL 3 UTS - {label}\n# PostgreSQL 16.2 (pgserver sandbox)\n\n{out}")
    return out


def main():
    data_dir = os.path.join(TMP, f"pgdata_soal3_{int(time.time())}")
    print(f">>> Start PostgreSQL 16.2 (data: {data_dir}) ...")
    db = pgserver.get_server(data_dir, cleanup_mode=None)
    uri = db.get_uri()
    print(f">>> {uri}")
    m = re.match(r"postgresql://([^:]+):([^@]*)@([^:]+):(\d+)/(.+)", uri)
    user, password, host, port, database = m.groups()
    params = {"host": host, "port": int(port), "user": user or "postgres",
              "password": password, "database": database}

    # Base schema dari SOAL 1 (dipakai ulang oleh SOAL 3)
    run_psql(params, os.path.join(SOAL1, "schema.sql"),
             "soal1/1.2_ddl/schema.sql (base)",
             os.path.join(SOAL3, "output_00_base_schema.txt"))

    db_dir = os.path.join(SOAL3, "db")
    run_psql(params, os.path.join(db_dir, "01_schema_additions.sql"),
             "01_schema_additions.sql",
             os.path.join(SOAL3, "output_01_schema_additions.txt"))
    run_psql(params, os.path.join(db_dir, "02_immutability.sql"),
             "02_immutability.sql",
             os.path.join(SOAL3, "output_02_immutability.txt"))
    run_psql(params, os.path.join(db_dir, "03_hash_checksum.sql"),
             "03_hash_checksum.sql",
             os.path.join(SOAL3, "output_03_hash_checksum.txt"))
    run_psql(params, os.path.join(db_dir, "04_rpc_post_and_reverse.sql"),
             "04_rpc_post_and_reverse.sql",
             os.path.join(SOAL3, "output_04_rpc.txt"))
    run_psql(params, os.path.join(db_dir, "05_tests.sql"),
             "05_tests.sql",
             os.path.join(SOAL3, "output_05_tests.txt"))

    print(">>> Selesai. Output disimpan di soal3/output_*.txt")


if __name__ == "__main__":
    main()
