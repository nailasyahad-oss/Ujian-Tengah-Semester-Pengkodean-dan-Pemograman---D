#!/usr/bin/env python3
"""
SOAL 2 UTS - demo_race.py
Simulasi RACE CONDITION: dua kasir memperebutkan item terakhir (stok 1 unit).

Tiga teknik diuji dengan dua koneksi & thread TERPISAH (transaksi berbeda):

  TEKNIK 1: SELECT ... FOR UPDATE di dalam trigger (pessimistic locking)
            -> transaksi kedua MENUNGGU kunci, lalu membaca stok terbaru = 0
               dan DITOLAK oleh trigger (stok tidak boleh negatif).
  TEKNIK 2: BEGIN ISOLATION LEVEL SERIALIZABLE
            -> transaksi kedua gagal dengan SQLSTATE 40001
               (serialization_failure) dan WAJIB retry; setelah retry,
               bacaan baru melihat stok = 0 sehingga ditolak dengan bersih.
  TEKNIK 3: UPDATE bersyarat atomik (stock_qty >= qty) + cek rowcount
            -> tepat satu UPDATE berhasil (rowcount=1), satu gagal
               (rowcount=0), tanpa jendela baca-tulis.

Koneksi: set PG* env (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)
untuk memakai server yang sudah berisi skema; jika tidak di-set, skrip
mem-start sandbox PostgreSQL 16 (pgserver) sendiri dan menjalankan
00_schema.sql + 01_trigger.sql lebih dulu.

Driver: pg8000 (murni Python). Jalankan:  python demo_race.py
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

TARGET_ITEM = "BRG001"

try:
    import pg8000
except ImportError:
    sys.exit("pg8000 belum terpasang. Jalankan: pip install pg8000")


# ----------------------------------------------------------------------
# Koneksi & utilitas
# ----------------------------------------------------------------------
def get_server():
    """Parameter koneksi dari env; jika kosong, start sandbox pgserver."""
    if os.environ.get("PGHOST"):
        params = {
            "host": os.environ.get("PGHOST", "127.0.0.1"),
            "port": int(os.environ.get("PGPORT", 5432)),
            "user": os.environ.get("PGUSER", "postgres"),
            "password": os.environ.get("PGPASSWORD", ""),
            "database": os.environ.get("PGDATABASE", "postgres"),
        }
        return params, None

    import pgserver

    here = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(tempfile.gettempdir(), "pgdata_demo_race")
    for _ in range(5):
        try:
            if os.path.exists(data_dir):
                shutil.rmtree(data_dir)
            break
        except PermissionError:
            time.sleep(2)

    print(f">>> Memulai sandbox PostgreSQL (pgserver) di {data_dir} ...")
    db = pgserver.get_server(data_dir, cleanup_mode=None)
    uri = db.get_uri()
    m = re.match(r"postgresql://([^:]+):([^@]*)@([^:]+):(\d+)/(.+)", uri)
    user, password, host, port, database = m.groups()
    params = {
        "host": host, "port": int(port),
        "user": user or "postgres", "password": password,
        "database": database,
    }

    # Pasang skema (butuh psql dari bundel pgserver)
    psql = os.path.join(os.path.dirname(pgserver.__file__), "pginstall", "bin", "psql.exe")
    if not os.path.exists(psql):
        psql = "psql"
    dsn = (f"host={params['host']} port={params['port']} user={params['user']} "
           f"dbname={params['database']}")
    for rel in ("../2.1_trigger/00_schema.sql", "../2.1_trigger/01_trigger.sql"):
        path = os.path.join(here, rel)
        print(f">>> Menjalankan {os.path.basename(path)} ...")
        r = subprocess.run([psql, "-d", dsn, "-f", path],
                           capture_output=True, text=True, encoding="utf-8")
        out = (r.stdout + r.stderr).strip()
        print(out if out else "(tanpa output)")
    return params, db


def connect(params):
    conn = pg8000.connect(
        host=params["host"], port=params["port"], user=params["user"],
        password=params["password"], database=params["database"],
    )
    conn.autocommit = True
    return conn


def sheet(title):
    print("\n" + "=" * 70)
    print(title)
    print("=" * 70)


def reset_stock(params, qty=1):
    """Set stok target = qty (koneksi sendiri, langsung commit)."""
    c = connect(params)
    c.cursor().execute("UPDATE inventory_items SET stock_qty = %s WHERE item_id = %s",
                       (qty, TARGET_ITEM))
    c.close()


def get_stock(params):
    c = connect(params)
    cur = c.cursor()
    cur.execute("SELECT stock_qty FROM inventory_items WHERE item_id = %s",
                (TARGET_ITEM,))
    row = cur.fetchone()
    c.close()
    return row[0] if row else None


def trx_count(params):
    c = connect(params)
    cur = c.cursor()
    cur.execute("SELECT COUNT(*) FROM inventory_transactions "
                "WHERE item_id = %s AND trx_type = 'SALE'",
                (TARGET_ITEM,))
    row = cur.fetchone()
    c.close()
    return row[0]


def clear_transactions(params):
    """Bersihkan tabel transaksi (sandbox uji) agar hitungan demo deterministik."""
    c = connect(params)
    try:
        c.cursor().execute("DELETE FROM gl_entries")
    except Exception:
        pass  # gl_entries belum ada (sebelum 03_bonus dijalankan) -> abaikan
    c.cursor().execute("DELETE FROM inventory_transactions")
    c.close()


def sqlerror_code(exc):
    """Ekstrak (SQLSTATE, pesan) dari exception pg8000.

    pg8000 membawa error server sebagai dict pada exc.args[0]
    dengan kunci: C=SQLSTATE, M=pesan.
    """
    code, msg = None, str(exc)
    try:
        err = exc.args[0] if exc.args else None
        if isinstance(err, dict):
            code = err.get("C")
            msg = err.get("M", str(err))
    except Exception:
        pass
    if code is None:
        m = (re.search(r"\(SQLSTATE ([0-9A-Z]{5})\)", str(exc))
             or re.search(r"'C': '([0-9A-Z]{5})'", str(exc)))
        if m:
            code = m.group(1)
    return code, msg


def barrier(t):
    t.join()
    if t.exc:
        raise t.exc


class DemoThread(threading.Thread):
    def __init__(self, name, fn, *args, **kwargs):
        super().__init__(name=name)
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.result = None
        self.exc = None

    def run(self):
        try:
            self.result = self.fn(*self.args, **self.kwargs)
        except Exception as e:  # simpan, laporkan di thread utama
            self.exc = e
            self.result = ("EXCEPTION", str(e))


SALE_SQL = ("INSERT INTO inventory_transactions (item_id, trx_type, qty) "
            "VALUES (%s, 'SALE', 1)")


def report_threads(*threads):
    """Tampilkan exception yang tersimpan di thread (mis. error tak terduga)."""
    for t in threads:
        if getattr(t, "exc", None) is not None:
            print(f"[{t.name}] THREAD EXCEPTION: "
                  f"{type(t.exc).__name__}: {t.exc}")


# ----------------------------------------------------------------------
# TEKNIK 1: SELECT FOR UPDATE (via trigger) - pessimistic locking
# ----------------------------------------------------------------------
def tech1_cashier(params, delay, hold, label):
    conn = connect(params)
    try:
        if delay:
            time.sleep(delay)
        print(f"[{label}] BEGIN")
        conn.cursor().execute("BEGIN")
        print(f"[{label}] INSERT SALE 1  (trigger: SELECT ... FOR UPDATE)")
        conn.cursor().execute(SALE_SQL, (TARGET_ITEM,))
        print(f"[{label}] kunci item didapat, istirahat {hold}s sambil menahan transaksi")
        conn.cursor().execute(f"SELECT pg_sleep({hold})")
        conn.cursor().execute("COMMIT")
        print(f"[{label}] COMMIT sukses")
        return ("OK", "COMMIT sukses")
    except Exception as e:
        code, msg = sqlerror_code(e)
        try:
            conn.cursor().execute("ROLLBACK")
            print(f"[{label}] ROLLBACK (error)")
        except Exception:
            pass
        print(f"[{label}] ERROR (SQLSTATE {code}): {msg}")
        return ("GAGAL", f"SQLSTATE {code}: {msg}")
    finally:
        conn.close()


def demo_for_update(params):
    sheet("TEKNIK 1 - SELECT ... FOR UPDATE (trigger) | stok awal: 1")
    reset_stock(params, 1)
    clear_transactions(params)
    print(f"Stok sebelum demo: {get_stock(params)}")

    t1 = DemoThread("T1", tech1_cashier, params, 0.0, 2, "kasir-A")
    t1.start()
    time.sleep(0.5)                    # pastikan A lebih dulu memegang kunci
    t2 = DemoThread("T2", tech1_cashier, params, 0.0, 0.0, "kasir-B")
    t2.start()
    t1.join()
    t2.join()

    print(f"\nHasil kasir-A : {t1.result[0]}")
    print(f"Hasil kasir-B : {t2.result[0]}  -> {t2.result[1][:110]}")
    print(f"Stok akhir    : {get_stock(params)}  (harap 0, BUKAN -1)")
    print(f"Jumlah trx SALE BRG001: {trx_count(params)}  (harap 1)")
    ok = (t1.result[0] == "OK" and t2.result[0] == "GAGAL"
          and get_stock(params) == 0 and trx_count(params) == 1)
    print(f"TEKNIK 1 -> {'PASS' if ok else 'FAIL'} (tepat SATU berhasil, SATU ditolak)")


# ----------------------------------------------------------------------
# TEKNIK 2: SERIALIZABLE + retry
# ----------------------------------------------------------------------
def tech2_session(params, label, hold, out):
    conn = connect(params)
    try:
        conn.cursor().execute("BEGIN ISOLATION LEVEL SERIALIZABLE")
        cur = conn.cursor().execute(
            "SELECT stock_qty FROM inventory_items WHERE item_id = %s", (TARGET_ITEM,))
        stok = cur.fetchone()[0]
        print(f"[{label}] SERIALIZABLE, baca stok = {stok}")
        time.sleep(hold)
        print(f"[{label}] INSERT SALE 1")
        conn.cursor().execute(SALE_SQL, (TARGET_ITEM,))
        conn.cursor().execute("COMMIT")
        print(f"[{label}] COMMIT sukses")
        out.append((label, "OK", "commit sukses"))
    except Exception as e:
        code, msg = sqlerror_code(e)
        try:
            conn.cursor().execute("ROLLBACK")
        except Exception:
            pass
        print(f"[{label}] ERROR (SQLSTATE {code}): {msg[:160]}")
        out.append((label, "GAGAL", f"SQLSTATE {code}: {msg[:110]}"))
    finally:
        conn.close()


def tech2_retry(params, max_retry=3, label="kasir-B(retry)"):
    """Kewajiban retry setelah 40001: ulangi dari BEGIN dengan bacaan baru."""
    for attempt in range(1, max_retry + 1):
        conn = connect(params)
        try:
            conn.cursor().execute("BEGIN ISOLATION LEVEL SERIALIZABLE")
            cur = conn.cursor().execute(
                "SELECT stock_qty FROM inventory_items WHERE item_id = %s",
                (TARGET_ITEM,))
            stok = cur.fetchone()[0]
            print(f"[{label}] percobaan {attempt}: baca stok = {stok}")
            if stok < 1:
                conn.cursor().execute("ROLLBACK")
                print(f"[{label}] percobaan {attempt}: stok tidak cukup -> "
                      f"ROLLBACK (penolakan BERSIH, bukan error 40001)")
                return ("DITOLAK", f"stok {stok} < 1")
            conn.cursor().execute(SALE_SQL, (TARGET_ITEM,))
            conn.cursor().execute("COMMIT")
            print(f"[{label}] percobaan {attempt}: COMMIT sukses")
            return ("OK", "commit sukses")
        except Exception as e:
            code, txt = sqlerror_code(e)
            try:
                conn.cursor().execute("ROLLBACK")
            except Exception:
                pass
            print(f"[{label}] percobaan {attempt}: ERROR (SQLSTATE {code}) -> retry")
            time.sleep(0.1 * attempt)
        finally:
            conn.close()
    return ("GAGAL", "melebihi max retry")


def demo_serializable(params):
    sheet("TEKNIK 2 - BEGIN ISOLATION LEVEL SERIALIZABLE | stok awal: 1")
    reset_stock(params, 1)
    clear_transactions(params)
    print(f"Stok sebelum demo: {get_stock(params)}")

    out = []
    t1 = DemoThread("T1", tech2_session, params, "kasir-A", 1.5, out)
    t1.start()
    time.sleep(0.3)
    t2 = DemoThread("T2", tech2_session, params, "kasir-B", 0.0, out)
    t2.start()
    t1.join()
    t2.join()
    report_threads(t1, t2)

    print("\n--- Retry wajib untuk kasir-B setelah SQLSTATE 40001 ---")
    retry_result = tech2_retry(params)

    print(f"\nStok akhir    : {get_stock(params)}  (harap 0)")
    print(f"Jumlah trx SALE BRG001: {trx_count(params)}  (harap 1)")
    statuses = sorted([r[1] for r in out])
    detail = "; ".join(f"{r[0]}={r[1]} ({r[2]})" for r in out)
    print(f"Hasil sesi    : {detail}")
    ok = (statuses == ["GAGAL", "OK"]
          and get_stock(params) == 0 and trx_count(params) == 1
          and retry_result[0] == "DITOLAK")
    print(f"TEKNIK 2 -> {'PASS' if ok else 'FAIL'} (tepat satu COMMIT sukses, "
          f"satu SQLSTATE 40001, retry menolak dengan bersih, stok akhir 0)")


# ----------------------------------------------------------------------
# TEKNIK 3: UPDATE bersyarat atomik
# ----------------------------------------------------------------------
def tech3_try_buy(params, label, out):
    conn = connect(params)
    try:
        cur = conn.cursor().execute(
            "UPDATE inventory_items SET stock_qty = stock_qty - 1 "
            "WHERE item_id = %s AND stock_qty >= 1", (TARGET_ITEM,))
        affected = cur.rowcount
        if affected == 1:
            out.append((label, "OK"))
            print(f"[{label}] UPDATE bersyarat: rowcount=1 -> BERHASIL")
        else:
            out.append((label, "DITOLAK"))
            print(f"[{label}] UPDATE bersyarat: rowcount={affected} "
                  f"-> DITOLAK (stok tidak cukup)")
    except Exception as e:
        out.append((label, "ERROR"))
        print(f"[{label}] ERROR: {e}")
    finally:
        conn.close()


def demo_conditional_update(params):
    sheet("TEKNIK 3 - UPDATE BERSYARAT ATOMIK | stok awal: 1")
    reset_stock(params, 1)
    clear_transactions(params)
    print(f"Stok sebelum demo: {get_stock(params)}")

    out = []
    t1 = DemoThread("T1", tech3_try_buy, params, "kasir-A", out)
    t1.start()
    time.sleep(0.3)
    t2 = DemoThread("T2", tech3_try_buy, params, "kasir-B", out)
    t2.start()
    t1.join()
    t2.join()

    print(f"\nHasil: {out}")
    print(f"Stok akhir    : {get_stock(params)}  (harap 0, BUKAN -1)")
    ok = (sorted([r[1] for r in out]) == ["DITOLAK", "OK"]
          and get_stock(params) == 0)
    print(f"TEKNIK 3 -> {'PASS' if ok else 'FAIL'} (tepat satu rowcount=1, "
          f"satu rowcount=0, tanpa retry maupun deadlock)")


# ----------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------
def main():
    params, db = get_server()
    print(f">>> Terhubung ke {params['host']}:{params['port']} "
          f"db={params['database']} user={params['user']}")

    # Validasi tabel inti ada (kasus memakai server eksternal)
    c = connect(params)
    try:
        cur = c.cursor()
        cur.execute("SELECT 1 FROM inventory_items LIMIT 1")
        cur.close()
    except Exception as e:
        c.close()
        sys.exit(f"Tabel inventory tidak ditemukan ({e}). "
                 f"Jalankan 00_schema.sql & 01_trigger.sql lebih dulu, "
                 f"atau biarkan PG* env kosong agar skrip memakai sandbox sendiri.")
    c.close()

    print(f"Stok awal {TARGET_ITEM}: {get_stock(params)}")
    t_start = time.time()

    clear_transactions(params)   # hitungan SALE deterministik dari 0

    demo_for_update(params)
    demo_serializable(params)
    demo_conditional_update(params)

    sheet("RINGKASAN")
    print(f"Stok akhir {TARGET_ITEM}: {get_stock(params)} (harap 0, TIDAK -1)")
    print("Catatan: tabel transaksi di-reset di awal tiap demo, jadi hitungan")
    print("akhir mewakili transaksi demo terakhir (Teknik 3 langsung UPDATE")
    print("inventory_items tanpa menambah baris inventory_transactions).")

    if db is not None:
        print("\n>>> (sandbox lokal dibiarkan berjalan; matikan manual bila perlu)")


if __name__ == "__main__":
    main()
