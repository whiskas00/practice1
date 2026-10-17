#!/usr/bin/env python3
"""Сводка бенчмарка по сырым замерам results/bench_*.csv -> results/bench_summary.csv (+ печать Markdown).
Для времени беру медиану и показываю разброс min–max, чтобы было видно, где разница тонет в шуме."""
import csv, os, statistics
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "results")
COMBOS = [(f, c) for f in ["PARQUET", "ORC"] for c in ["NONE", "SNAPPY", "GZIP", "ZSTD"]]


def read(name):
    with open(os.path.join(RES, name)) as f:
        return list(csv.DictReader(f))


size = defaultdict(int)
files = defaultdict(int)
size_by_table = defaultdict(dict)
for r in read("bench_size.csv"):
    k = (r["format"], r["codec"])
    size[k] += int(r["size_bytes"])
    files[k] += int(r["data_files"])
    size_by_table[k][r["table"]] = int(r["size_bytes"])

# время записи: сумма по 3 таблицам в каждом раунде записи
write_rounds = defaultdict(lambda: defaultdict(float))
seen = defaultdict(int)
for r in read("bench_write.csv"):
    k = (r["format"], r["codec"])
    seen[(k, r["table"])] += 1
    write_rounds[k][seen[(k, r["table"])]] += float(r["write_s"])

runs = defaultdict(list)
for r in read("bench_query_runs.csv"):
    ms = r["trino_exec_ms"]
    runs[(r["format"], r["codec"], r["mode"])].append(int(ms) / 1000 if ms else float(r["wall_s"]))

base = size[("PARQUET", "NONE")]
out = []
for k in COMBOS:
    w = list(write_rounds[k].values())
    cold = runs[k + ("cold",)]
    warm = runs[k + ("warm",)]
    out.append({
        "variant": f"{k[0].lower()}_{k[1].lower()}",
        "size_mb": f"{size[k] / 1024 / 1024:.1f}",
        "partsupp_mb": f"{size_by_table[k].get('partsupp', 0) / 1024 / 1024:.1f}",
        "vs_parquet_none_pct": f"{(size[k] / base - 1) * 100:+.1f}",
        "data_files": files[k],
        "write_s_median": f"{statistics.median(w):.1f}" if w else "",
        "write_s_min_max": f"{min(w):.1f}–{max(w):.1f}" if w else "",
        "cold_s_median": f"{statistics.median(cold):.2f}" if cold else "",
        "cold_s_min_max": f"{min(cold):.2f}–{max(cold):.2f}" if cold else "",
        "warm_s_median": f"{statistics.median(warm):.2f}" if warm else "",
        "warm_s_min_max": f"{min(warm):.2f}–{max(warm):.2f}" if warm else "",
        "n_cold": len(cold), "n_warm": len(warm),
    })

with open(os.path.join(RES, "bench_summary.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
    w.writeheader()
    w.writerows(out)

print("| Вариант | Размер, МБ | partsupp, МБ | vs parquet_none | Файлов | Запись, с (медиана; min–max) | Q16 cold, с (медиана; min–max) | Q16 warm, с (медиана; min–max) |")
print("|---|---|---|---|---|---|---|---|")
for o in out:
    print(f"| {o['variant']} | {o['size_mb']} | {o['partsupp_mb']} | {o['vs_parquet_none_pct']}% | {o['data_files']} | "
          f"{o['write_s_median']} ({o['write_s_min_max']}) | {o['cold_s_median']} ({o['cold_s_min_max']}) | "
          f"{o['warm_s_median']} ({o['warm_s_min_max']}) |")
