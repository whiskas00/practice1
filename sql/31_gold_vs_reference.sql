-- Сверка Gold с эталонным SQL варианта 4 по tpch.sf10: EXCEPT в обе стороны должен дать 0.
WITH ref AS (
  SELECT p.brand, CAST(p.type AS varchar) AS type, p.size, count(DISTINCT ps.suppkey) AS supplier_cnt
  FROM tpch.sf10.partsupp AS ps
  JOIN tpch.sf10.part AS p ON p.partkey = ps.partkey
  WHERE p.brand <> 'Brand#45'
    AND p.type NOT LIKE 'MEDIUM POLISHED%'
    AND p.size IN (49, 14, 23, 45, 19, 3, 36, 9)
    AND ps.suppkey NOT IN (SELECT suppkey FROM tpch.sf10.supplier WHERE comment LIKE '%Customer%Complaints%')
  GROUP BY p.brand, p.type, p.size
),
gold AS (SELECT brand, type, size, supplier_cnt FROM gold.lakehouse.q16_parts_supplier)
SELECT
  (SELECT count(*) FROM ref)                                        AS ref_rows,
  (SELECT count(*) FROM gold)                                       AS gold_rows,
  (SELECT count(*) FROM (SELECT * FROM gold EXCEPT SELECT * FROM ref)) AS gold_minus_ref,
  (SELECT count(*) FROM (SELECT * FROM ref EXCEPT SELECT * FROM gold)) AS ref_minus_gold,
  (SELECT sum(supplier_cnt) FROM ref)                               AS ref_sum_cnt,
  (SELECT sum(supplier_cnt) FROM gold)                              AS gold_sum_cnt;
