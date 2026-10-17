#!/usr/bin/env python3
"""Time travel на копии silver.lakehouse.supplier:
$snapshots / $history, FOR VERSION AS OF, FOR TIMESTAMP AS OF,
авария 1 (удалили часть строк) -> точечное восстановление INSERT ... SELECT из старой версии,
авария 2 (испортили всю колонку) -> откат целиком ALTER TABLE ... EXECUTE rollback_to_snapshot."""
import os, time
from demo_lib import Log, q, val, ROOT

T = "silver.lakehouse.supplier_tt"
S = 'silver.lakehouse."supplier_tt$snapshots"'
log = Log(os.path.join(ROOT, "results", "time_travel_log.md"), "Time travel и восстановление на копии silver.lakehouse.supplier")

log.run("0. Копия таблицы", f"DROP TABLE IF EXISTS {T}")
log.run("0.1 CTAS (снапшот v1 — эталонное состояние)", f"CREATE TABLE {T} WITH (format = 'PARQUET') AS SELECT * FROM silver.lakehouse.supplier")
v1 = val(f"SELECT snapshot_id FROM {S} ORDER BY committed_at DESC LIMIT 1")
time.sleep(2)
ts_good = val("SELECT CAST(current_timestamp AS varchar)")   # момент, когда таблица точно ещё целая
log.text(f"v1 = `{v1}`, отметка времени «всё хорошо» = `{ts_good}`")
time.sleep(2)

log.run("1. АВАРИЯ 1: по ошибке удалили всех поставщиков из страны nation_key = 7",
        f"DELETE FROM {T} WHERE nation_key = 7")
v2 = val(f"SELECT snapshot_id FROM {S} ORDER BY committed_at DESC LIMIT 1")
log.run("1.1 Сейчас в таблице", f"SELECT count(*) AS rows_now, count_if(nation_key = 7) AS nation7 FROM {T}")

log.run("2. $snapshots — все версии таблицы",
        f"""SELECT committed_at, snapshot_id, parent_id, operation,
       element_at(summary, 'total-records') AS total_records,
       element_at(summary, 'added-position-deletes') AS added_pos_deletes,
       element_at(summary, 'added-data-files') AS added_data_files
FROM {S} ORDER BY committed_at""")
log.run("2.1 $history — какая версия была текущей и когда",
        f"""SELECT made_current_at, snapshot_id, parent_id, is_current_ancestor
FROM silver.lakehouse."supplier_tt$history" ORDER BY made_current_at""")

log.run("3. FOR VERSION AS OF v1 — таблица до аварии",
        f"SELECT count(*) AS rows_v1, count_if(nation_key = 7) AS nation7 FROM {T} FOR VERSION AS OF {v1}")
log.run("3.1 FOR TIMESTAMP AS OF — то же самое по времени",
        f"""SELECT count(*) AS rows_at_ts, count_if(nation_key = 7) AS nation7
FROM {T} FOR TIMESTAMP AS OF TIMESTAMP '{ts_good}'""")

log.run("4. ВОССТАНОВЛЕНИЕ точечно: вставляю обратно только удалённые строки из версии v1",
        f"""INSERT INTO {T}
SELECT * FROM {T} FOR VERSION AS OF {v1}
WHERE nation_key = 7""")
log.run("4.1 Проверка: совпадает с v1 в обе стороны",
        f"""SELECT
  (SELECT count(*) FROM {T}) AS rows_now,
  (SELECT count(*) FROM (SELECT * FROM {T} EXCEPT SELECT * FROM {T} FOR VERSION AS OF {v1})) AS now_minus_v1,
  (SELECT count(*) FROM (SELECT * FROM {T} FOR VERSION AS OF {v1} EXCEPT SELECT * FROM {T})) AS v1_minus_now""")
v3 = val(f"SELECT snapshot_id FROM {S} ORDER BY committed_at DESC LIMIT 1")

log.run("5. АВАРИЯ 2: кривой UPDATE без WHERE — всем поставщикам проставили «жалобы»",
        f"UPDATE {T} SET has_complaints = true")
log.run("5.1 Сейчас", f"SELECT count_if(has_complaints) AS with_complaints FROM {T}")

log.run("6. ВОССТАНОВЛЕНИЕ целиком: откат на снапшот v3 (после точечного восстановления)",
        f"ALTER TABLE {T} EXECUTE rollback_to_snapshot({v3})")
log.run("6.1 Проверка после отката",
        f"""SELECT count(*) AS rows_now, count_if(has_complaints) AS with_complaints,
  (SELECT count(*) FROM (SELECT * FROM {T} EXCEPT SELECT * FROM silver.lakehouse.supplier)) AS diff_vs_silver,
  (SELECT count(*) FROM (SELECT * FROM silver.lakehouse.supplier EXCEPT SELECT * FROM {T})) AS diff_silver_vs_now
FROM {T}""")
log.run("6.2 $history после отката: текущей снова стала v3, снапшот с UPDATE остался в истории, но не предок текущей",
        f"""SELECT made_current_at, snapshot_id, parent_id, is_current_ancestor
FROM silver.lakehouse."supplier_tt$history" ORDER BY made_current_at""")
log.text(f"v1 = `{v1}` (CTAS), v2 = `{v2}` (DELETE), v3 = `{v3}` (INSERT восстановление)")
log.close()
