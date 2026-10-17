#!/usr/bin/env python3
"""Schema evolution на копии Silver-таблицы silver.lakehouse.part.
Показываю: ADD COLUMN, RENAME COLUMN, расширение типа (integer->bigint, decimal(15,2)->decimal(18,2)),
что файлы данных не переписывались, старые строки = NULL, и что колонки в metadata.json идут по ID."""
import json, os, subprocess
from demo_lib import Log, q, val, ROOT

T = "silver.lakehouse.part_evo"
log = Log(os.path.join(ROOT, "results", "schema_evolution_log.md"), "Schema evolution на копии silver.lakehouse.part")

log.run("0. Копия Silver-таблицы (работаю на копии, чтобы не трогать основной слой)",
        f"DROP TABLE IF EXISTS {T}")
log.run("0.1 CTAS", f"CREATE TABLE {T} WITH (format = 'PARQUET') AS SELECT * FROM silver.lakehouse.part")
log.run("0.2 Запоминаю список файлов данных ДО изменений схемы",
        f"""CREATE OR REPLACE TABLE silver.lakehouse.part_evo_files_before AS
            SELECT file_path, file_size_in_bytes FROM silver.lakehouse."part_evo$files" """)
log.run("0.3 Файлы и снапшоты до", f"""SELECT (SELECT count(*) FROM silver.lakehouse."part_evo$files") AS data_files,
       (SELECT count(*) FROM silver.lakehouse."part_evo$snapshots") AS snapshots""")

log.run("1. ADD COLUMN — новая колонка (класс цены)", f"ALTER TABLE {T} ADD COLUMN price_band varchar")
log.run("1.1 Новая строка уже со значением колонки",
        f"""INSERT INTO {T} (part_key, part_name, manufacturer, brand, brand_mfgr_no, brand_no, part_type,
            type_class, type_finish, type_material, part_size, container, retail_price, part_comment,
            _batch_id, _loaded_at, _processed_at, price_band)
            VALUES (9999999, 'demo part', 'Manufacturer#1', 'Brand#11', 1, 1, 'SMALL PLATED TIN',
                    'SMALL', 'PLATED', 'TIN', 7, 'SM BOX', 1234.50, 'demo', 99, current_timestamp, current_timestamp, 'HIGH')""")
log.run("1.2 Старые строки видят NULL, новая — 'HIGH'",
        f"""SELECT price_band, count(*) AS rows FROM {T} GROUP BY price_band ORDER BY price_band NULLS FIRST""")

log.run("2. RENAME COLUMN part_comment -> comment_text", f"ALTER TABLE {T} RENAME COLUMN part_comment TO comment_text")
log.run("2.1 Старые данные читаются под новым именем",
        f"SELECT part_key, comment_text FROM {T} WHERE part_key IN (1, 2, 9999999) ORDER BY part_key")

log.run("3. Расширение типа integer -> bigint (brand_no)", f"ALTER TABLE {T} ALTER COLUMN brand_no SET DATA TYPE bigint")
log.run("3.1 Расширение decimal(15,2) -> decimal(18,2) (retail_price)",
        f"ALTER TABLE {T} ALTER COLUMN retail_price SET DATA TYPE decimal(18, 2)", allow_fail=True)
log.run("3.2 Сужение bigint -> integer (должно быть запрещено)",
        f"ALTER TABLE {T} ALTER COLUMN brand_no SET DATA TYPE integer", allow_fail=True)
log.run("3.3 Схема после изменений", f"DESCRIBE {T}")

log.run("4. Файлы данных: старые на месте, ни один не переписан (новый файл только от INSERT из шага 1.1)",
        f"""SELECT
  (SELECT count(*) FROM silver.lakehouse.part_evo_files_before) AS files_before,
  (SELECT count(*) FROM silver.lakehouse."part_evo$files") AS files_now,
  (SELECT count(*) FROM (SELECT file_path FROM silver.lakehouse.part_evo_files_before
                         EXCEPT SELECT file_path FROM silver.lakehouse."part_evo$files")) AS old_files_missing_now""")
log.run("4.1 Снапшоты: ALTER не создаёт снапшотов, только INSERT",
        f"""SELECT committed_at, snapshot_id, operation, summary['added-data-files'] AS added_files,
       summary['total-records'] AS total_records
FROM silver.lakehouse."part_evo$snapshots" ORDER BY committed_at""")
log.run("4.2 История версий метаданных (каждый ALTER = новый metadata.json)",
        f"""SELECT timestamp, file FROM silver.lakehouse."part_evo$metadata_log_entries" ORDER BY timestamp""")

# 5. Читаю текущий metadata.json прямо из MinIO и показываю схемы с ID колонок
meta_path = val(f"""SELECT file FROM silver.lakehouse."part_evo$metadata_log_entries" ORDER BY timestamp DESC LIMIT 1""")
key = meta_path.replace("s3://", "")
raw = subprocess.run(["docker", "run", "--rm", "--entrypoint", "/bin/sh", "--add-host", "host.docker.internal:host-gateway",
                      "pgsty/mc:latest", "-c",
                      f"mc alias set m http://host.docker.internal:9000 minioadmin minioadmin >/dev/null && mc cat m/{key}"],
                     capture_output=True, text=True, check=True).stdout
meta = json.loads(raw)
with open(os.path.join(ROOT, "results", "schema_evolution_metadata.json"), "w") as f:
    json.dump({"metadata_file": meta_path,
               "current-schema-id": meta["current-schema-id"],
               "last-column-id": meta["last-column-id"],
               "schemas": meta["schemas"]}, f, indent=2, ensure_ascii=False)

lines = [f"Файл: `{meta_path}`", "", f"current-schema-id = {meta['current-schema-id']}, last-column-id = {meta['last-column-id']}", "",
         "| schema-id | изменённые/новые поля (id: name type) |", "|---|---|"]
prev = {}
for sch in meta["schemas"]:
    cur = {fld["id"]: (fld["name"], fld["type"]) for fld in sch["fields"]}
    if not prev:
        diff = ", ".join(f"{i}: {n} {t}" for i, (n, t) in cur.items())
    else:
        diff = ", ".join(f"{i}: {prev.get(i, ('—', ''))[0]} {prev.get(i, ('', '—'))[1]} -> {n} {t}"
                         for i, (n, t) in cur.items() if prev.get(i) != (n, t)) or "без изменений"
    lines.append(f"| {sch['schema-id']} | {diff} |")
    prev = cur
log.text("### 5. metadata.json: колонки хранятся по ID\n\n" + "\n".join(lines))
log.close()
