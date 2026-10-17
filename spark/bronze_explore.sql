-- Spark подключается к тому же Lakekeeper и читает Bronze-таблицы, которые записал Trino.
SHOW NAMESPACES IN bronze;
SHOW TABLES IN bronze.lakehouse;
DESCRIBE TABLE bronze.lakehouse.partsupp;
-- строки по партиям загрузки (batch 1 = источник tpch.sf10, batch 2 = грязная догрузка)
SELECT 'part' AS tbl, _batch_id, count(*) AS cnt FROM bronze.lakehouse.part GROUP BY _batch_id
UNION ALL SELECT 'partsupp', _batch_id, count(*) FROM bronze.lakehouse.partsupp GROUP BY _batch_id
UNION ALL SELECT 'supplier', _batch_id, count(*) FROM bronze.lakehouse.supplier GROUP BY _batch_id
ORDER BY tbl, _batch_id;
-- метаданные Iceberg глазами Spark: снапшоты и файлы
SELECT committed_at, snapshot_id, operation, summary['added-records'] AS added_records
FROM bronze.lakehouse.part.snapshots ORDER BY committed_at;
SELECT count(*) AS data_files, round(sum(file_size_in_bytes) / 1024 / 1024, 2) AS mb, max(file_format) AS fmt
FROM bronze.lakehouse.partsupp.files;
-- грязные строки видны и в Spark (Bronze хранит всё как пришло)
SELECT partkey, concat('[', brand, ']') AS brand_raw, type, size
FROM bronze.lakehouse.part WHERE _batch_id = 2 ORDER BY partkey NULLS FIRST LIMIT 8;
-- мой Q16 прямо по сырому Bronze в Spark: должно выйти 27878 групп, как у Trino (control_raw_bronze_vs_reference.csv)
SELECT count(*) AS groups_raw, sum(supplier_cnt) AS sum_cnt FROM (
  SELECT p.brand, p.type, p.size, count(DISTINCT ps.suppkey) AS supplier_cnt
  FROM bronze.lakehouse.partsupp ps JOIN bronze.lakehouse.part p ON p.partkey = ps.partkey
  WHERE p.brand <> 'Brand#45' AND p.type NOT LIKE 'MEDIUM POLISHED%'
    AND p.size IN (49, 14, 23, 45, 19, 3, 36, 9)
    AND ps.suppkey NOT IN (SELECT suppkey FROM bronze.lakehouse.supplier WHERE comment LIKE '%Customer%Complaints%')
  GROUP BY p.brand, p.type, p.size
) t;
