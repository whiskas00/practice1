-- =====================================================================
-- SILVER, шаг 1: проверки качества Bronze (до очистки).
-- Одна строка = одна проверка: таблица, проверка, сколько строк нарушают.
-- Результат сохраняю в results/dq_checks.csv.
-- =====================================================================
WITH
p AS (SELECT * FROM bronze.lakehouse.part),
ps AS (SELECT * FROM bronze.lakehouse.partsupp),
s AS (SELECT * FROM bronze.lakehouse.supplier),
valid_part AS (
  SELECT DISTINCT partkey FROM p
  WHERE partkey IS NOT NULL AND brand IS NOT NULL AND size BETWEEN 1 AND 50
),
valid_supp AS (SELECT DISTINCT suppkey FROM s WHERE suppkey IS NOT NULL)
SELECT * FROM (
  -- part
  SELECT 'part' AS tbl, 'rows_total'               AS check_name, count(*) AS bad_rows FROM p
  UNION ALL SELECT 'part', 'null_partkey',           count_if(partkey IS NULL) FROM p
  UNION ALL SELECT 'part', 'duplicate_partkey',      count(partkey) - count(DISTINCT partkey) FROM p
  UNION ALL SELECT 'part', 'null_brand',             count_if(brand IS NULL) FROM p
  UNION ALL SELECT 'part', 'size_out_of_1_50',       count_if(size NOT BETWEEN 1 AND 50) FROM p
  UNION ALL SELECT 'part', 'brand_bad_format',       count_if(NOT regexp_like(trim(brand), '^Brand#[1-5][1-5]$')) FROM p
  UNION ALL SELECT 'part', 'untrimmed_strings',      count_if(brand <> trim(brand) OR type <> trim(type) OR name <> trim(name) OR container <> trim(container)) FROM p
  UNION ALL SELECT 'part', 'type_not_upper',         count_if(type <> upper(type)) FROM p
  UNION ALL SELECT 'part', 'type_not_3_words',       count_if(cardinality(split(trim(type), ' ')) <> 3) FROM p
  UNION ALL SELECT 'part', 'retailprice_le_0',       count_if(retailprice <= 0 OR retailprice IS NULL) FROM p
  -- partsupp
  UNION ALL SELECT 'partsupp', 'rows_total',         count(*) FROM ps
  UNION ALL SELECT 'partsupp', 'null_keys',          count_if(partkey IS NULL OR suppkey IS NULL) FROM ps
  UNION ALL SELECT 'partsupp', 'duplicate_pair',     count(*) - count(DISTINCT (partkey, suppkey)) FROM ps
  UNION ALL SELECT 'partsupp', 'availqty_negative',  count_if(availqty < 0) FROM ps
  UNION ALL SELECT 'partsupp', 'supplycost_null_le_0', count_if(supplycost IS NULL OR supplycost <= 0) FROM ps
  UNION ALL SELECT 'partsupp', 'orphan_partkey',     count_if(partkey NOT IN (SELECT partkey FROM valid_part)) FROM ps
  UNION ALL SELECT 'partsupp', 'orphan_suppkey',     count_if(suppkey NOT IN (SELECT suppkey FROM valid_supp)) FROM ps
  -- supplier
  UNION ALL SELECT 'supplier', 'rows_total',         count(*) FROM s
  UNION ALL SELECT 'supplier', 'null_suppkey',       count_if(suppkey IS NULL) FROM s
  UNION ALL SELECT 'supplier', 'duplicate_suppkey',  count(suppkey) - count(DISTINCT suppkey) FROM s
  UNION ALL SELECT 'supplier', 'untrimmed_strings',  count_if(name <> trim(name) OR phone <> trim(phone) OR address <> trim(address)) FROM s
  UNION ALL SELECT 'supplier', 'phone_bad_format',   count_if(NOT regexp_like(trim(phone), '^\d{2}-\d{3}-\d{3}-\d{4}$')) FROM s
  UNION ALL SELECT 'supplier', 'info_customer_complaints', count_if(comment LIKE '%Customer%Complaints%') FROM s
) t
ORDER BY tbl, check_name;
