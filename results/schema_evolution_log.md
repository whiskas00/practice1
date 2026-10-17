# Schema evolution на копии silver.lakehouse.part

### 0. Копия Silver-таблицы (работаю на копии, чтобы не трогать основной слой)

```sql
DROP TABLE IF EXISTS silver.lakehouse.part_evo
```

```

```

### 0.1 CTAS

```sql
CREATE TABLE silver.lakehouse.part_evo WITH (format = 'PARQUET') AS SELECT * FROM silver.lakehouse.part
```

```

```

### 0.2 Запоминаю список файлов данных ДО изменений схемы

```sql
CREATE OR REPLACE TABLE silver.lakehouse.part_evo_files_before AS
            SELECT file_path, file_size_in_bytes FROM silver.lakehouse."part_evo$files"
```

```

```

### 0.3 Файлы и снапшоты до

```sql
SELECT (SELECT count(*) FROM silver.lakehouse."part_evo$files") AS data_files,
       (SELECT count(*) FROM silver.lakehouse."part_evo$snapshots") AS snapshots
```

```
data_files | snapshots 
------------+-----------
          4 |         1 
(1 row)
```

### 1. ADD COLUMN — новая колонка (класс цены)

```sql
ALTER TABLE silver.lakehouse.part_evo ADD COLUMN price_band varchar
```

```

```

### 1.1 Новая строка уже со значением колонки

```sql
INSERT INTO silver.lakehouse.part_evo (part_key, part_name, manufacturer, brand, brand_mfgr_no, brand_no, part_type,
            type_class, type_finish, type_material, part_size, container, retail_price, part_comment,
            _batch_id, _loaded_at, _processed_at, price_band)
            VALUES (9999999, 'demo part', 'Manufacturer#1', 'Brand#11', 1, 1, 'SMALL PLATED TIN',
                    'SMALL', 'PLATED', 'TIN', 7, 'SM BOX', 1234.50, 'demo', 99, current_timestamp, current_timestamp, 'HIGH')
```

```

```

### 1.2 Старые строки видят NULL, новая — 'HIGH'

```sql
SELECT price_band, count(*) AS rows FROM silver.lakehouse.part_evo GROUP BY price_band ORDER BY price_band NULLS FIRST
```

```
price_band |  rows   
------------+---------
 NULL       | 2000000 
 HIGH       |       1 
(2 rows)
```

### 2. RENAME COLUMN part_comment -> comment_text

```sql
ALTER TABLE silver.lakehouse.part_evo RENAME COLUMN part_comment TO comment_text
```

```

```

### 2.1 Старые данные читаются под новым именем

```sql
SELECT part_key, comment_text FROM silver.lakehouse.part_evo WHERE part_key IN (1, 2, 9999999) ORDER BY part_key
```

```
part_key |   comment_text   
----------+------------------
        1 | ly. slyly ironi  
        2 | lar accounts amo 
  9999999 | demo             
(3 rows)
```

### 3. Расширение типа integer -> bigint (brand_no)

```sql
ALTER TABLE silver.lakehouse.part_evo ALTER COLUMN brand_no SET DATA TYPE bigint
```

```

```

### 3.1 Расширение decimal(15,2) -> decimal(18,2) (retail_price)

```sql
ALTER TABLE silver.lakehouse.part_evo ALTER COLUMN retail_price SET DATA TYPE decimal(18, 2)
```

```

```

### 3.2 Сужение bigint -> integer (должно быть запрещено)

```sql
ALTER TABLE silver.lakehouse.part_evo ALTER COLUMN brand_no SET DATA TYPE integer
```

```
ОШИБКА: Query 20261017_111502_00046_fuht4 failed: Failed to set column type: Cannot change column type: brand_no: long -> int
```

### 3.3 Схема после изменений

```sql
DESCRIBE silver.lakehouse.part_evo
```

```
Column     |            Type             | Extra | Comment 
---------------+-----------------------------+-------+---------
 part_key      | bigint                      |       |         
 part_name     | varchar                     |       |         
 manufacturer  | varchar                     |       |         
 brand         | varchar                     |       |         
 brand_mfgr_no | integer                     |       |         
 brand_no      | bigint                      |       |         
 part_type     | varchar                     |       |         
 type_class    | varchar                     |       |         
 type_finish   | varchar                     |       |         
 type_material | varchar                     |       |         
 part_size     | integer                     |       |         
 container     | varchar                     |       |         
 retail_price  | decimal(18,2)               |       |         
 comment_text  | varchar                     |       |         
 _batch_id     | integer                     |       |         
 _loaded_at    | timestamp(6) with time zone |       |         
 _processed_at | timestamp(6) with time zone |       |         
 price_band    | varchar                     |       |         
(18 rows)
```

### 4. Файлы данных: старые на месте, ни один не переписан (новый файл только от INSERT из шага 1.1)

```sql
SELECT
  (SELECT count(*) FROM silver.lakehouse.part_evo_files_before) AS files_before,
  (SELECT count(*) FROM silver.lakehouse."part_evo$files") AS files_now,
  (SELECT count(*) FROM (SELECT file_path FROM silver.lakehouse.part_evo_files_before
                         EXCEPT SELECT file_path FROM silver.lakehouse."part_evo$files")) AS old_files_missing_now
```

```
files_before | files_now | old_files_missing_now 
--------------+-----------+-----------------------
            4 |         5 |                     0 
(1 row)
```

### 4.1 Снапшоты: ALTER не создаёт снапшотов, только INSERT

```sql
SELECT committed_at, snapshot_id, operation, summary['added-data-files'] AS added_files,
       summary['total-records'] AS total_records
FROM silver.lakehouse."part_evo$snapshots" ORDER BY committed_at
```

```
committed_at         |     snapshot_id     | operation | added_files | total_records 
-----------------------------+---------------------+-----------+-------------+---------------
 2026-10-17 11:14:56.092 UTC | 5170531484571134677 | append    | 4           | 2000000       
 2026-10-17 11:14:58.835 UTC | 2645558727609455029 | append    | 1           | 2000001       
(2 rows)
```

### 4.2 История версий метаданных (каждый ALTER = новый metadata.json)

```sql
SELECT timestamp, file FROM silver.lakehouse."part_evo$metadata_log_entries" ORDER BY timestamp
```

```
timestamp          |                                                            file                                                            
-----------------------------+----------------------------------------------------------------------------------------------------------------------------
 2026-10-17 11:14:56.092 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00000-01a14992-7006-7353-bbf9-0a1dde17e5f7.gz.metadata.json 
 2026-10-17 11:14:56.221 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00001-01a14992-705d-7f83-8f34-34f690ca1705.gz.metadata.json 
 2026-10-17 11:14:58.248 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00002-01a14992-7848-7571-b209-2267f5c29c64.gz.metadata.json 
 2026-10-17 11:14:58.835 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00003-01a14992-7a9d-74e2-b352-3485373727bc.gz.metadata.json 
 2026-10-17 11:14:58.880 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00004-01a14992-7ac0-7de0-b310-96a477beb095.gz.metadata.json 
 2026-10-17 11:14:59.991 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00005-01a14992-7f17-7d61-89fc-c07c725b1e95.gz.metadata.json 
 2026-10-17 11:15:01.536 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00006-01a14992-8520-7041-930b-1be40902258b.gz.metadata.json 
 2026-10-17 11:15:02.117 UTC | s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00007-01a14992-8765-7d12-9c6e-67041045b641.gz.metadata.json 
(8 rows)
```

### 5. metadata.json: колонки хранятся по ID

Файл: `s3://silver/part_evo-69d3de9eee1845c19adadfc5b56d1026/metadata/00007-01a14992-8765-7d12-9c6e-67041045b641.gz.metadata.json`

current-schema-id = 4, last-column-id = 18

| schema-id | изменённые/новые поля (id: name type) |
|---|---|
| 0 | 1: part_key long, 2: part_name string, 3: manufacturer string, 4: brand string, 5: brand_mfgr_no int, 6: brand_no int, 7: part_type string, 8: type_class string, 9: type_finish string, 10: type_material string, 11: part_size int, 12: container string, 13: retail_price decimal(15, 2), 14: part_comment string, 15: _batch_id int, 16: _loaded_at timestamptz, 17: _processed_at timestamptz |
| 1 | 18: — — -> price_band string |
| 2 | 14: part_comment string -> comment_text string |
| 3 | 6: brand_no int -> brand_no long |
| 4 | 13: retail_price decimal(15, 2) -> retail_price decimal(18, 2) |

