#!/usr/bin/env bash
# Бонус: мой Gold-запрос (SELECT витрины из silver.part_supplier) 1 раз и 10 копий одновременно.
set -euo pipefail
cd "$(dirname "$0")/.."
Q="SELECT brand, part_type, part_size, count(DISTINCT supplier_key) FROM silver.lakehouse.part_supplier
   WHERE brand <> 'Brand#45' AND NOT (type_class = 'MEDIUM' AND type_finish = 'POLISHED')
     AND part_size IN (49, 14, 23, 45, 19, 3, 36, 9) AND NOT supplier_has_complaints
   GROUP BY brand, part_type, part_size"
now() { python3 -c 'import time; print(time.perf_counter())'; }
./scripts/trino.sh "$Q" > /dev/null   # прогрев
echo "mode,streams,run,wall_s"
for r in 1 2 3; do
  t0=$(now); ./scripts/trino.sh "$Q" > /dev/null; t1=$(now)
  echo "single,1,$r,$(python3 -c "print(round($t1-$t0,3))")"
done
for r in 1 2 3; do
  t0=$(now)
  for i in $(seq 1 10); do ./scripts/trino.sh "$Q" > /dev/null & done
  wait
  t1=$(now)
  echo "parallel,10,$r,$(python3 -c "print(round($t1-$t0,3))")"
done
