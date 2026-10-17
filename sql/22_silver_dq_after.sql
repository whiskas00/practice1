-- SILVER, шаг 3: те же проверки уже по Silver — все нарушения должны быть 0.
SELECT * FROM (
  SELECT 'part' AS tbl, 'rows_total' AS check_name, count(*) AS bad_rows FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'null_key',            count_if(part_key IS NULL) FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'duplicate_key',       count(*) - count(DISTINCT part_key) FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'size_out_of_1_50',    count_if(part_size NOT BETWEEN 1 AND 50) FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'brand_bad_format',    count_if(NOT regexp_like(brand, '^Brand#[1-5][1-5]$')) FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'untrimmed_or_lower',  count_if(brand <> trim(brand) OR part_type <> upper(trim(part_type))) FROM silver.lakehouse.part
  UNION ALL SELECT 'part', 'type_parts_empty',    count_if(type_class = '' OR type_finish = '' OR type_material = '') FROM silver.lakehouse.part
  UNION ALL SELECT 'partsupp', 'rows_total',      count(*) FROM silver.lakehouse.partsupp
  UNION ALL SELECT 'partsupp', 'duplicate_pair',  count(*) - count(DISTINCT (part_key, supplier_key)) FROM silver.lakehouse.partsupp
  UNION ALL SELECT 'partsupp', 'invalid_values',  count_if(available_qty < 0 OR supply_cost <= 0 OR supply_cost IS NULL) FROM silver.lakehouse.partsupp
  UNION ALL SELECT 'partsupp', 'orphan_part',     count_if(part_key NOT IN (SELECT part_key FROM silver.lakehouse.part)) FROM silver.lakehouse.partsupp
  UNION ALL SELECT 'partsupp', 'orphan_supplier', count_if(supplier_key NOT IN (SELECT supplier_key FROM silver.lakehouse.supplier)) FROM silver.lakehouse.partsupp
  UNION ALL SELECT 'supplier', 'rows_total',      count(*) FROM silver.lakehouse.supplier
  UNION ALL SELECT 'supplier', 'duplicate_key',   count(*) - count(DISTINCT supplier_key) FROM silver.lakehouse.supplier
  UNION ALL SELECT 'supplier', 'untrimmed',       count_if(supplier_name <> trim(supplier_name) OR phone <> trim(phone) OR address <> trim(address)) FROM silver.lakehouse.supplier
  UNION ALL SELECT 'supplier', 'info_has_complaints', count_if(has_complaints) FROM silver.lakehouse.supplier
) t ORDER BY tbl, check_name;
