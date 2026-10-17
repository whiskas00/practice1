-- Контроль: эталонный Q16 прямо по сырому Bronze (с грязной партией, без очистки).
-- Показывает, зачем нужен Silver: результат расходится с эталоном.
WITH ref AS (
  SELECT p.brand, CAST(p.type AS varchar) AS type, p.size, count(DISTINCT ps.suppkey) AS supplier_cnt
  FROM tpch.sf10.partsupp ps JOIN tpch.sf10.part p ON p.partkey = ps.partkey
  WHERE p.brand <> 'Brand#45' AND p.type NOT LIKE 'MEDIUM POLISHED%'
    AND p.size IN (49, 14, 23, 45, 19, 3, 36, 9)
    AND ps.suppkey NOT IN (SELECT suppkey FROM tpch.sf10.supplier WHERE comment LIKE '%Customer%Complaints%')
  GROUP BY p.brand, p.type, p.size
),
raw AS (
  SELECT p.brand, p.type, p.size, count(DISTINCT ps.suppkey) AS supplier_cnt
  FROM bronze.lakehouse.partsupp ps JOIN bronze.lakehouse.part p ON p.partkey = ps.partkey
  WHERE p.brand <> 'Brand#45' AND p.type NOT LIKE 'MEDIUM POLISHED%'
    AND p.size IN (49, 14, 23, 45, 19, 3, 36, 9)
    AND ps.suppkey NOT IN (SELECT suppkey FROM bronze.lakehouse.supplier WHERE comment LIKE '%Customer%Complaints%')
  GROUP BY p.brand, p.type, p.size
)
SELECT
  (SELECT count(*) FROM raw) AS raw_rows,
  (SELECT count(*) FROM (SELECT * FROM raw EXCEPT SELECT * FROM ref)) AS raw_minus_ref,
  (SELECT count(*) FROM (SELECT * FROM ref EXCEPT SELECT * FROM raw)) AS ref_minus_raw;
