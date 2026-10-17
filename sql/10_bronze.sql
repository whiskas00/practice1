-- =====================================================================
-- BRONZE: сырые таблицы Q16 «как есть» + служебные поля загрузки.
-- Масштаб sf10 (один на всех слоях).
-- Формат PARQUET, кодек ZSTD, партиционирование по дню загрузки.
-- Строковые колонки беру как varchar без длины: Bronze не должен падать,
-- если в источнике придёт строка длиннее, чем в справочнике типов.
-- =====================================================================
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE SCHEMA IF NOT EXISTS bronze.lakehouse;

DROP TABLE IF EXISTS bronze.lakehouse.part;
DROP TABLE IF EXISTS bronze.lakehouse.partsupp;
DROP TABLE IF EXISTS bronze.lakehouse.supplier;

-- ---------- batch 1: полная выгрузка из источника (tpch.sf10) ----------
CREATE TABLE bronze.lakehouse.part
WITH (format = 'PARQUET', partitioning = ARRAY['day(_loaded_at)'])
AS SELECT
  partkey,
  CAST(name AS varchar)      AS name,
  CAST(mfgr AS varchar)      AS mfgr,
  CAST(brand AS varchar)     AS brand,
  CAST(type AS varchar)      AS type,
  size,
  CAST(container AS varchar) AS container,
  retailprice,
  CAST(comment AS varchar)   AS comment,
  1                          AS _batch_id,
  'tpch.sf10.part'           AS _source,
  current_timestamp          AS _loaded_at
FROM tpch.sf10.part;

CREATE TABLE bronze.lakehouse.partsupp
WITH (format = 'PARQUET', partitioning = ARRAY['day(_loaded_at)'])
AS SELECT
  partkey,
  suppkey,
  availqty,
  supplycost,
  CAST(comment AS varchar)   AS comment,
  1                          AS _batch_id,
  'tpch.sf10.partsupp'       AS _source,
  current_timestamp          AS _loaded_at
FROM tpch.sf10.partsupp;

CREATE TABLE bronze.lakehouse.supplier
WITH (format = 'PARQUET', partitioning = ARRAY['day(_loaded_at)'])
AS SELECT
  suppkey,
  CAST(name AS varchar)      AS name,
  CAST(address AS varchar)   AS address,
  nationkey,
  CAST(phone AS varchar)     AS phone,
  acctbal,
  CAST(comment AS varchar)   AS comment,
  1                          AS _batch_id,
  'tpch.sf10.supplier'       AS _source,
  current_timestamp          AS _loaded_at
FROM tpch.sf10.supplier;
