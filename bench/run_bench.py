#!/usr/bin/env python3
"""Бенчмарк Bronze-таблиц Q16: PARQUET/ORC x NONE/SNAPPY/GZIP/ZSTD.

Этапы (можно запускать по отдельности):
  write  - CTAS bench.lakehouse.<table>_<fmt>_<codec> из bronze.lakehouse.<table>, замер времени записи
  size   - размер и число файлов по "$files", кодек по "$properties"
  query  - Q16 cold/warm: перед cold сброс page cache ВМ Docker + рестарт vk-trino и vk-minio

Сырые замеры пишутся в results/bench_*.csv.
"""
import argparse, csv, os, subprocess, time, uuid
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRINO = os.path.join(ROOT, "scripts", "trino.sh")
RES = os.path.join(ROOT, "results")

FORMATS = ["PARQUET", "ORC"]
CODECS = ["NONE", "SNAPPY", "GZIP", "ZSTD"]
TABLES = ["part", "partsupp", "supplier"]
COMBOS = [(f, c) for f in FORMATS for c in CODECS]

Q16 = """
SELECT p.brand, p.type, p.size, count(DISTINCT ps.suppkey) AS supplier_cnt
FROM bench.lakehouse.partsupp_{s} AS ps
JOIN bench.lakehouse.part_{s} AS p ON p.partkey = ps.partkey
WHERE p.brand <> 'Brand#45'
  AND p.type NOT LIKE 'MEDIUM POLISHED%'
  AND p.size IN (49, 14, 23, 45, 19, 3, 36, 9)
  AND ps.suppkey NOT IN (
    SELECT suppkey FROM bench.lakehouse.supplier_{s}
    WHERE comment LIKE '%Customer%Complaints%')
  AND '{tag}' = '{tag}'
GROUP BY p.brand, p.type, p.size
ORDER BY supplier_cnt DESC, p.brand, p.type, p.size
"""


def trino(sql, fmt="TSV"):
    r = subprocess.run([TRINO, sql, "--output-format", fmt], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout


def timed(sql):
    t0 = time.perf_counter()
    out = trino(sql)
    return time.perf_counter() - t0, out


def suffix(fmt, codec):
    return f"{fmt.lower()}_{codec.lower()}"


def wait_trino():
    for _ in range(120):
        try:
            # лёгкий запрос, чтобы Trino поднялся и каталог bench прогрузился (не трогает данные Q16)
            trino("SELECT count(*) FROM bench.information_schema.tables WHERE table_schema = 'lakehouse'")
            return
        except Exception:
            time.sleep(2)
    raise RuntimeError("Trino не поднялся")


def cold_restart():
    subprocess.run(["docker", "run", "--rm", "--privileged", "postgres:17", "sh", "-c",
                    "sync; echo 3 > /proc/sys/vm/drop_caches"], check=True, capture_output=True)
    subprocess.run(["docker", "restart", "vk-minio", "vk-trino"], check=True, capture_output=True)
    for _ in range(60):
        if subprocess.run(["curl", "-sf", "http://localhost:9000/minio/health/live"], capture_output=True).returncode == 0:
            break
        time.sleep(1)
    wait_trino()


def trino_exec_ms(tag):
    out = trino(f"""SELECT date_diff('millisecond', started, "end") FROM system.runtime.queries
                    WHERE query LIKE '%{tag}%' AND query NOT LIKE '%system.runtime.queries%' AND state = 'FINISHED'""")
    return int(out.strip().splitlines()[0]) if out.strip() else ""


def stage_write():
    path = os.path.join(RES, "bench_write.csv")
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["ts", "format", "codec", "table", "rows", "write_s"])
        trino("CREATE SCHEMA IF NOT EXISTS bench.lakehouse")
        for fmt, codec in COMBOS:
            for t in TABLES:
                name = f"bench.lakehouse.{t}_{suffix(fmt, codec)}"
                trino(f"DROP TABLE IF EXISTS {name}")
                sql = (f"SET SESSION bench.compression_codec = '{codec}'; "
                       f"CREATE TABLE {name} WITH (format = '{fmt}', partitioning = ARRAY['day(_loaded_at)']) "
                       f"AS SELECT * FROM bronze.lakehouse.{t}")
                sec, out = timed(sql)
                rows = trino(f"SELECT count(*) FROM {name}").strip()
                w.writerow([datetime.now().isoformat(timespec="seconds"), fmt, codec, t, rows, f"{sec:.3f}"])
                f.flush()
                print(f"write {fmt:7} {codec:6} {t:9} {sec:7.2f} s", flush=True)


def stage_size():
    with open(os.path.join(RES, "bench_size.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["format", "codec", "table", "data_files", "size_bytes", "codec_in_metadata"])
        for fmt, codec in COMBOS:
            for t in TABLES:
                tbl = f"{t}_{suffix(fmt, codec)}"
                files, size = trino(f'SELECT count(*), sum(file_size_in_bytes) FROM bench.lakehouse."{tbl}$files"').split()
                meta = trino(f"""SELECT value FROM bench.lakehouse."{tbl}$properties"
                                 WHERE key = 'write.{fmt.lower()}.compression-codec'""").strip()
                w.writerow([fmt, codec, t, files, size, meta])
                print(f"size  {fmt:7} {codec:6} {t:9} {int(size)/1024/1024:9.2f} MB  files={files} meta={meta}", flush=True)


def stage_query(rounds, warm_runs):
    path = os.path.join(RES, "bench_query_runs.csv")
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["ts", "round", "format", "codec", "mode", "run", "wall_s", "trino_exec_ms", "result_rows"])
        for r in range(1, rounds + 1):
            for fmt, codec in COMBOS:
                s = suffix(fmt, codec)
                cold_restart()
                for mode, n in [("cold", 1), ("warm", warm_runs)]:
                    for i in range(1, n + 1):
                        tag = "q16_" + uuid.uuid4().hex[:10]
                        sec, out = timed(Q16.format(s=s, tag=tag))
                        rows = len(out.strip().splitlines())
                        ms = trino_exec_ms(tag)
                        w.writerow([datetime.now().isoformat(timespec="seconds"), r, fmt, codec, mode, i,
                                    f"{sec:.3f}", ms, rows])
                        f.flush()
                        print(f"round {r} {fmt:7} {codec:6} {mode} #{i}: wall {sec:6.2f} s, trino {ms} ms, rows {rows}", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("stages", nargs="+", choices=["write", "size", "query"])
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--warm-runs", type=int, default=3)
    a = ap.parse_args()
    for st in a.stages:
        if st == "write":
            stage_write()
        elif st == "size":
            stage_size()
        else:
            stage_query(a.rounds, a.warm_runs)
