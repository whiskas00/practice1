-- =====================================================================
-- SILVER, шаг 2: очистка, нормализация типов и имён, обогащение.
-- Правила:
--   * забракованные строки не теряю, а складываю в dq_rejects с причиной;
--   * строки: trim везде, upper только для type и container (у них канон в верхнем регистре);
--   * деньги: double -> decimal(15,2) (точная арифметика);
--   * дубли по ключу: оставляю самую свежую загрузку (_batch_id, _loaded_at);
--   * partsupp пропускаю только если деталь и поставщик есть в Silver;
--   * type разбираю на 3 части, поставщиков с жалобами НЕ удаляю, а помечаю флагом.
-- PARQUET + ZSTD. part_supplier партиционирую по part_size (см. отчёт).
-- =====================================================================
SET SESSION silver.compression_codec = 'ZSTD';

CREATE SCHEMA IF NOT EXISTS silver.lakehouse;

DROP TABLE IF EXISTS silver.lakehouse.dq_rejects;
DROP TABLE IF EXISTS silver.lakehouse.part;
DROP TABLE IF EXISTS silver.lakehouse.supplier;
DROP TABLE IF EXISTS silver.lakehouse.partsupp;
DROP TABLE IF EXISTS silver.lakehouse.part_supplier;

-- ---------- карантин: что и почему отбраковано ----------
CREATE TABLE silver.lakehouse.dq_rejects
WITH (format = 'PARQUET')
AS
SELECT 'part' AS source_table, reason, CAST(partkey AS varchar) AS record_key, _batch_id, _loaded_at
FROM (
  SELECT *, CASE
      WHEN partkey IS NULL THEN 'null_partkey'
      WHEN brand IS NULL THEN 'null_brand'
      WHEN size NOT BETWEEN 1 AND 50 THEN 'size_out_of_1_50'
    END AS reason
  FROM bronze.lakehouse.part
) WHERE reason IS NOT NULL
UNION ALL
SELECT 'supplier', 'null_suppkey', NULL, _batch_id, _loaded_at
FROM bronze.lakehouse.supplier WHERE suppkey IS NULL;

-- ---------- part ----------
CREATE TABLE silver.lakehouse.part
WITH (format = 'PARQUET')
AS
WITH cleaned AS (
  SELECT
    partkey                                      AS part_key,
    trim(name)                                   AS part_name,
    trim(mfgr)                                   AS manufacturer,
    trim(brand)                                  AS brand,         -- канон: Brand#MN, регистр не трогаю
    upper(trim(type))                            AS part_type,
    size                                         AS part_size,
    upper(trim(container))                       AS container,
    CAST(retailprice AS decimal(15, 2))          AS retail_price,
    trim(comment)                                AS part_comment,
    _batch_id, _loaded_at,
    row_number() OVER (PARTITION BY partkey ORDER BY _batch_id DESC, _loaded_at DESC) AS rn
  FROM bronze.lakehouse.part
  WHERE partkey IS NOT NULL AND brand IS NOT NULL AND size BETWEEN 1 AND 50
)
SELECT
  part_key, part_name, manufacturer, brand,
  CAST(substr(brand, 7, 1) AS integer)          AS brand_mfgr_no,   -- Brand#MN -> M
  CAST(substr(brand, 8, 1) AS integer)          AS brand_no,        -- Brand#MN -> N
  part_type,
  split_part(part_type, ' ', 1)                 AS type_class,      -- STANDARD / SMALL / MEDIUM ...
  split_part(part_type, ' ', 2)                 AS type_finish,     -- ANODIZED / POLISHED ...
  split_part(part_type, ' ', 3)                 AS type_material,   -- TIN / NICKEL / BRASS ...
  part_size, container, retail_price, part_comment,
  _batch_id, _loaded_at,
  current_timestamp                             AS _processed_at
FROM cleaned
WHERE rn = 1;

-- ---------- supplier ----------
CREATE TABLE silver.lakehouse.supplier
WITH (format = 'PARQUET')
AS
WITH cleaned AS (
  SELECT
    suppkey                                      AS supplier_key,
    trim(name)                                   AS supplier_name,
    trim(address)                                AS address,
    nationkey                                    AS nation_key,
    trim(phone)                                  AS phone,
    CAST(acctbal AS decimal(15, 2))              AS account_balance,
    trim(comment)                                AS supplier_comment,
    _batch_id, _loaded_at,
    row_number() OVER (PARTITION BY suppkey ORDER BY _batch_id DESC, _loaded_at DESC) AS rn
  FROM bronze.lakehouse.supplier
  WHERE suppkey IS NOT NULL
)
SELECT
  supplier_key, supplier_name, address, nation_key, phone, account_balance, supplier_comment,
  supplier_comment LIKE '%Customer%Complaints%' AS has_complaints,  -- флаг для Gold
  _batch_id, _loaded_at,
  current_timestamp                             AS _processed_at
FROM cleaned
WHERE rn = 1;

-- ---------- partsupp: невалидные значения и «сироты» в карантин ----------
INSERT INTO silver.lakehouse.dq_rejects
SELECT 'partsupp', reason, CAST(partkey AS varchar) || '|' || CAST(suppkey AS varchar), _batch_id, _loaded_at
FROM (
  SELECT ps.*, CASE
      WHEN ps.partkey IS NULL OR ps.suppkey IS NULL THEN 'null_keys'
      WHEN ps.availqty < 0 THEN 'availqty_negative'
      WHEN ps.supplycost IS NULL OR ps.supplycost <= 0 THEN 'supplycost_null_le_0'
      WHEN p.part_key IS NULL THEN 'orphan_partkey'
      WHEN s.supplier_key IS NULL THEN 'orphan_suppkey'
    END AS reason
  FROM bronze.lakehouse.partsupp ps
  LEFT JOIN silver.lakehouse.part p ON p.part_key = ps.partkey
  LEFT JOIN silver.lakehouse.supplier s ON s.supplier_key = ps.suppkey
) WHERE reason IS NOT NULL;

CREATE TABLE silver.lakehouse.partsupp
WITH (format = 'PARQUET')
AS
WITH cleaned AS (
  SELECT
    ps.partkey                                   AS part_key,
    ps.suppkey                                   AS supplier_key,
    ps.availqty                                  AS available_qty,
    CAST(ps.supplycost AS decimal(15, 2))        AS supply_cost,
    trim(ps.comment)                             AS partsupp_comment,
    ps._batch_id, ps._loaded_at,
    row_number() OVER (PARTITION BY ps.partkey, ps.suppkey ORDER BY ps._batch_id DESC, ps._loaded_at DESC) AS rn
  FROM bronze.lakehouse.partsupp ps
  WHERE ps.partkey IS NOT NULL AND ps.suppkey IS NOT NULL
    AND ps.availqty >= 0 AND ps.supplycost > 0
    AND ps.partkey IN (SELECT part_key FROM silver.lakehouse.part)          -- ссылочная целостность
    AND ps.suppkey IN (SELECT supplier_key FROM silver.lakehouse.supplier)
)
SELECT part_key, supplier_key, available_qty, supply_cost, partsupp_comment,
       _batch_id, _loaded_at, current_timestamp AS _processed_at
FROM cleaned
WHERE rn = 1;

-- ---------- part_supplier: связь «деталь <-> поставщик» (джойн из подсказки к варианту) ----------
-- Одна строка = одна пара (деталь, поставщик) со всеми атрибутами, которые нужны аналитике.
-- Партиционирую по part_size: Q16 оставляет только 8 размеров из 50,
-- и Trino читает только эти партиции (partition pruning).
CREATE TABLE silver.lakehouse.part_supplier
WITH (format = 'PARQUET', partitioning = ARRAY['part_size'])
AS
SELECT
  ps.part_key,
  ps.supplier_key,
  p.brand,
  p.part_type,
  p.type_class,
  p.type_finish,
  p.type_material,
  p.part_size,
  p.container,
  ps.available_qty,
  ps.supply_cost,
  s.has_complaints AS supplier_has_complaints,
  current_timestamp AS _processed_at
FROM silver.lakehouse.partsupp ps
JOIN silver.lakehouse.part p     ON p.part_key = ps.part_key
JOIN silver.lakehouse.supplier s ON s.supplier_key = ps.supplier_key;
