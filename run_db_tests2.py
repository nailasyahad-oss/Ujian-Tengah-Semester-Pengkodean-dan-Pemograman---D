"""
SOAL 2 UTS - Runner pengujian lengkap.
Menjalankan (urut): 00_schema.sql -> 01_trigger.sql -> 02_test_trigger.sql
-> 03_bonus_journal.sql (psql), lalu demo_race.py (3 teknik concurrency)
dengan PG* env menunjuk server yang sama. Output asli disimpan per berkas.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

import pgserver

WORKSPACE = r"D:\Ujian-Tengah-Semester-Pengkodean-dan-Pemograman---D\soal2"
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
        f.write(f"# SOAL 2 UTS - {label}\n# PostgreSQL 16.2 (pgserver sandbox)\n\n{out}")
    return out


def main():
    data_dir = os.path.join(TMP, f"pgdata_soal2_{int(time.time())}")
    print(f">>> Start PostgreSQL 16.2 (data: {data_dir}) ...")
    db = pgserver.get_server(data_dir, cleanup_mode=None)
    uri = db.get_uri()
    print(f">>> {uri}")
    import re
    m = re.match(r"postgresql://([^:]+):([^@]*)@([^:]+):(\d+)/(.+)", uri)
    user, password, host, port, database = m.groups()
    params = {"host": host, "port": int(port), "user": user or "postgres",
              "password": password, "database": database}

    t = os.path.join(WORKSPACE, "2.1_trigger")
    run_psql(params, os.path.join(t, "00_schema.sql"), "00_schema.sql",
             os.path.join(t, "output_00_schema.txt"))
    run_psql(params, os.path.join(t, "01_trigger.sql"), "01_trigger.sql",
             os.path.join(t, "output_01_trigger.txt"))
    run_psql(params, os.path.join(t, "02_test_trigger.sql"), "02_test_trigger.sql",
             os.path.join(t, "output_02_test.txt"))
    run_psql(params, os.path.join(t, "03_bonus_journal.sql"), "03_bonus_journal.sql",
             os.path.join(t, "output_03_bonus.txt"))

    # demo concurrency dengan PG* env menunjuk server yang sama
    env = dict(os.environ)
    env.update({
        "PGHOST": params["host"], "PGPORT": str(params["port"]),
        "PGUSER": params["user"], "PGPASSWORD": params["password"],
        "PGDATABASE": params["database"],
    })
    print("\n>>> demo_race.py (3 teknik concurrency)")
    r = subprocess.run([sys.executable,
                        os.path.join(WORKSPACE, "2.2_concurrency", "demo_race.py")],
                       capture_output=True, text=True, encoding="utf-8", env=env)
    demo_out = r.stdout + r.stderr
    print(demo_out)
    with open(os.path.join(WORKSPACE, "2.2_concurrency", "output_demo_race.txt"),
              "w", encoding="utf-8") as f:
        f.write("# SOAL 2 UTS - demo_race.py\n# PostgreSQL 16.2 (pgserver sandbox)\n\n")
        f.write(demo_out)

    print(">>> Selesai. Output disimpan di soal2/**/output_*.txt")


if __name__ == "__main__":
    main()
