-- =====================================================================
-- GOLD: витрина Q16 «Parts/Supplier Relationship».
-- Сколько разных поставщиков (без жалоб) у деталей по brand / type / size.
-- Источник — silver.lakehouse.part_supplier (джойн и очистка уже сделаны в Silver).
-- PARQUET + ZSTD, без партиционирования: ~28 тыс. строк, это один маленький файл.
-- =====================================================================
SET SESSION gold.compression_codec = 'ZSTD';

CREATE SCHEMA IF NOT EXISTS gold.lakehouse;
DROP TABLE IF EXISTS gold.lakehouse.q16_parts_supplier;

CREATE TABLE gold.lakehouse.q16_parts_supplier
WITH (format = 'PARQUET')
AS
SELECT
  brand,
  part_type                     AS type,
  part_size                     AS size,
  count(DISTINCT supplier_key)  AS supplier_cnt
FROM silver.lakehouse.part_supplier
WHERE brand <> 'Brand#45'
  AND NOT (type_class = 'MEDIUM' AND type_finish = 'POLISHED')  -- = type NOT LIKE 'MEDIUM POLISHED%'
  AND part_size IN (49, 14, 23, 45, 19, 3, 36, 9)               -- partition pruning: 8 партиций из 50
  AND NOT supplier_has_complaints                               -- = suppkey NOT IN (поставщики с жалобами)
GROUP BY brand, part_type, part_size;
