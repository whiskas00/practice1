# Time travel и восстановление на копии silver.lakehouse.supplier

### 0. Копия таблицы

```sql
DROP TABLE IF EXISTS silver.lakehouse.supplier_tt
```

```

```

### 0.1 CTAS (снапшот v1 — эталонное состояние)

```sql
CREATE TABLE silver.lakehouse.supplier_tt WITH (format = 'PARQUET') AS SELECT * FROM silver.lakehouse.supplier
```

```

```

v1 = `2499175251857534081`, отметка времени «всё хорошо» = `2026-10-17 11:15:55.660 UTC`

### 1. АВАРИЯ 1: по ошибке удалили всех поставщиков из страны nation_key = 7

```sql
DELETE FROM silver.lakehouse.supplier_tt WHERE nation_key = 7
```

```

```

### 1.1 Сейчас в таблице

```sql
SELECT count(*) AS rows_now, count_if(nation_key = 7) AS nation7 FROM silver.lakehouse.supplier_tt
```

```
rows_now | nation7 
----------+---------
    95951 |       0 
(1 row)
```

### 2. $snapshots — все версии таблицы

```sql
SELECT committed_at, snapshot_id, parent_id, operation,
       element_at(summary, 'total-records') AS total_records,
       element_at(summary, 'added-position-deletes') AS added_pos_deletes,
       element_at(summary, 'added-data-files') AS added_data_files
FROM silver.lakehouse."supplier_tt$snapshots" ORDER BY committed_at
```

```
committed_at         |     snapshot_id     |      parent_id      | operation | total_records | added_pos_deletes | added_data_files 
-----------------------------+---------------------+---------------------+-----------+---------------+-------------------+------------------
 2026-10-17 11:15:51.442 UTC | 2499175251857534081 |                NULL | append    | 100000        | NULL              | 1                
 2026-10-17 11:16:00.042 UTC | 8234508127315332984 | 2499175251857534081 | delete    | 100000        | 4049              | NULL             
(2 rows)
```

### 2.1 $history — какая версия была текущей и когда

```sql
SELECT made_current_at, snapshot_id, parent_id, is_current_ancestor
FROM silver.lakehouse."supplier_tt$history" ORDER BY made_current_at
```

```
made_current_at       |     snapshot_id     |      parent_id      | is_current_ancestor 
-----------------------------+---------------------+---------------------+---------------------
 2026-10-17 11:15:51.442 UTC | 2499175251857534081 |                NULL | true                
 2026-10-17 11:16:00.042 UTC | 8234508127315332984 | 2499175251857534081 | true                
(2 rows)
```

### 3. FOR VERSION AS OF v1 — таблица до аварии

```sql
SELECT count(*) AS rows_v1, count_if(nation_key = 7) AS nation7 FROM silver.lakehouse.supplier_tt FOR VERSION AS OF 2499175251857534081
```

```
rows_v1 | nation7 
---------+---------
  100000 |    4049 
(1 row)
```

### 3.1 FOR TIMESTAMP AS OF — то же самое по времени

```sql
SELECT count(*) AS rows_at_ts, count_if(nation_key = 7) AS nation7
FROM silver.lakehouse.supplier_tt FOR TIMESTAMP AS OF TIMESTAMP '2026-10-17 11:15:55.660 UTC'
```

```
rows_at_ts | nation7 
------------+---------
     100000 |    4049 
(1 row)
```

### 4. ВОССТАНОВЛЕНИЕ точечно: вставляю обратно только удалённые строки из версии v1

```sql
INSERT INTO silver.lakehouse.supplier_tt
SELECT * FROM silver.lakehouse.supplier_tt FOR VERSION AS OF 2499175251857534081
WHERE nation_key = 7
```

```

```

### 4.1 Проверка: совпадает с v1 в обе стороны

```sql
SELECT
  (SELECT count(*) FROM silver.lakehouse.supplier_tt) AS rows_now,
  (SELECT count(*) FROM (SELECT * FROM silver.lakehouse.supplier_tt EXCEPT SELECT * FROM silver.lakehouse.supplier_tt FOR VERSION AS OF 2499175251857534081)) AS now_minus_v1,
  (SELECT count(*) FROM (SELECT * FROM silver.lakehouse.supplier_tt FOR VERSION AS OF 2499175251857534081 EXCEPT SELECT * FROM silver.lakehouse.supplier_tt)) AS v1_minus_now
```

```
rows_now | now_minus_v1 | v1_minus_now 
----------+--------------+--------------
   100000 |            0 |            0 
(1 row)
```

### 5. АВАРИЯ 2: кривой UPDATE без WHERE — всем поставщикам проставили «жалобы»

```sql
UPDATE silver.lakehouse.supplier_tt SET has_complaints = true
```

```

```

### 5.1 Сейчас

```sql
SELECT count_if(has_complaints) AS with_complaints FROM silver.lakehouse.supplier_tt
```

```
with_complaints 
-----------------
          100000 
(1 row)
```

### 6. ВОССТАНОВЛЕНИЕ целиком: откат на снапшот v3 (после точечного восстановления)

```sql
ALTER TABLE silver.lakehouse.supplier_tt EXECUTE rollback_to_snapshot(6496036606520100153)
```

```

```

### 6.1 Проверка после отката

```sql
SELECT count(*) AS rows_now, count_if(has_complaints) AS with_complaints,
  (SELECT count(*) FROM (SELECT * FROM silver.lakehouse.supplier_tt EXCEPT SELECT * FROM silver.lakehouse.supplier)) AS diff_vs_silver,
  (SELECT count(*) FROM (SELECT * FROM silver.lakehouse.supplier EXCEPT SELECT * FROM silver.lakehouse.supplier_tt)) AS diff_silver_vs_now
FROM silver.lakehouse.supplier_tt
```

```
rows_now | with_complaints | diff_vs_silver | diff_silver_vs_now 
----------+-----------------+----------------+--------------------
   100000 |              56 |              0 |                  0 
(1 row)
```

### 6.2 $history после отката: текущей снова стала v3, снапшот с UPDATE остался в истории, но не предок текущей

```sql
SELECT made_current_at, snapshot_id, parent_id, is_current_ancestor
FROM silver.lakehouse."supplier_tt$history" ORDER BY made_current_at
```

```
made_current_at       |     snapshot_id     |      parent_id      | is_current_ancestor 
-----------------------------+---------------------+---------------------+---------------------
 2026-10-17 11:15:51.442 UTC | 2499175251857534081 |                NULL | true                
 2026-10-17 11:16:00.042 UTC | 8234508127315332984 | 2499175251857534081 | true                
 2026-10-17 11:16:05.845 UTC | 6496036606520100153 | 8234508127315332984 | true                
 2026-10-17 11:16:11.631 UTC | 5622998409114012256 | 6496036606520100153 | false               
(4 rows)
```

v1 = `2499175251857534081` (CTAS), v2 = `8234508127315332984` (DELETE), v3 = `6496036606520100153` (INSERT восстановление)

