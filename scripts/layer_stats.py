#!/usr/bin/env python3
"""Характеристики таблиц: строки, файлы, МБ (по "$files"), формат, кодек, партиционирование.
Использование: scripts/layer_stats.py catalog.schema.table [...] > results/xxx.csv"""
import csv, re, subprocess, sys, os

TRINO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "trino.sh")

def q(sql):
    out = subprocess.run([TRINO, sql, "--output-format", "TSV"], capture_output=True, text=True, check=True).stdout
    return [line.split("\t") for line in out.strip().splitlines()]

w = csv.writer(sys.stdout)
w.writerow(["table", "rows", "data_files", "size_bytes", "size_mb", "format", "codec", "partitioning"])
for fq in sys.argv[1:]:
    cat, sch, tbl = fq.split(".")
    rows = q(f"SELECT count(*) FROM {fq}")[0][0]
    files, size = q(f'SELECT count(*), coalesce(sum(file_size_in_bytes), 0) FROM {cat}.{sch}."{tbl}$files"')[0]
    props = dict(q(f'SELECT key, value FROM {cat}.{sch}."{tbl}$properties"'))
    fmt = props.get("write.format.default", "PARQUET").upper()
    codec = props.get(f"write.{fmt.lower()}.compression-codec", "?").upper()
    ddl = "\n".join(r[0] for r in q(f"SHOW CREATE TABLE {fq}"))
    m = re.search(r"partitioning = ARRAY\[(.*?)\]", ddl)
    part = m.group(1).replace("'", "") if m else "нет"
    w.writerow([fq, rows, files, size, f"{int(size)/1024/1024:.2f}", fmt, codec, part])
    sys.stdout.flush()
