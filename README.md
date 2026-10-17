# Практическая работа №1 — локальный Lakehouse, ELT и бенчмарк форматов/сжатия

**Студентка:** Карпухина Виктория Сергеевна, МИСИС, группа БИВТ-24-СП-3
**Курс:** «Основы теории информации» (VK Education)
**Вариант:** 4 — TPC-H Q16 «Parts/Supplier Relationship», масштаб **sf10**

Заполненная форма отчёта — в [`отчет.md`](отчет.md). Здесь — как всё устроено и как это повторить.

## Что я сделала коротко

1. Подняла в Docker стек **MinIO (silo) → Postgres → Lakekeeper → Trino** (+ Spark как второй движок).
2. Построила медальон под свой запрос Q16:
   - **Bronze** — сырые `part`, `partsupp`, `supplier` из `tpch.sf10` + специально «грязная» догрузка;
   - **Silver** — проверки качества, карантин брака, очистка, нормализация типов/имён, разбор `type`, флаг жалоб, связь деталь↔поставщик;
   - **Gold** — витрина `brand, type, size, supplier_cnt`, сверена с эталонным SQL (EXCEPT в обе стороны = 0).
3. Сравнила PARQUET/ORC × NONE/SNAPPY/GZIP/ZSTD на Bronze-таблицах своего запроса: размер, запись, Q16 cold/warm.
4. Показала schema evolution и time travel (включая восстановление после «аварии»).
5. Подключила Spark к Bronze через тот же каталог Lakekeeper.

## Ключевые результаты

| Что | Результат |
|---|---|
| Gold vs эталонный Q16 (`tpch.sf10`) | 27 840 = 27 840 строк, EXCEPT в обе стороны = 0, sum(supplier_cnt) = 1 186 339 |
| Проверки качества | в Bronze найдено всё подброшенное + 3 091 настоящий пробел в адресах; в Silver все нарушения = 0, в карантине 129 строк |
| Размер Bronze Q16 | NONE 1234 МБ → SNAPPY 446–466 → ZSTD 314–317 → GZIP 291–301 МБ |
| Время Q16 cold / warm | 4.5–5.7 с / 1.5–2.4 с (медианы), разница между кодеками в пределах шума |
| Выбор | PARQUET + ZSTD на всех слоях |
| Trino vs Spark (Q16) | Trino 1.8–5.6 с, Spark 3.3–13.6 с |

Подробности и обоснования — в [`отчет.md`](отчет.md).

## Архитектура

```
                    SQL                          метаданные (Iceberg REST)
  я (CLI trino) ───────────► Trino 476 ─────────────────────────► Lakekeeper ───► Postgres 17
  Spark 3.5.3   ───────────►    │                                     ▲            (vk-pg, порт 5433)
                                │ читает/пишет parquet/orc            │
                                ▼                                     │
                           MinIO (silo) ◄──────────────────────────────┘
                 бакеты: bronze | silver | gold | bench
```

| Контейнер | Образ | Порты | Том |
|---|---|---|---|
| `vk-minio` | `pgsty/silo:latest` | 9000 (S3), 9001 (консоль) | `vk-minio-data` |
| `vk-pg` | `postgres:17` | **5433**→5432 (5432 на машине занят) | `vk-pg-data` |
| `vk-lakekeeper` | `quay.io/lakekeeper/catalog:latest-main` | 8181 | — |
| `vk-trino` | `trinodb/trino:476` | 8080 | — (монтируется `catalog/`, `trino/config.properties`) |
| `vk-spark` (по запросу) | `apache/spark:3.5.3` | — | — (монтируется `spark/`) |

Один слой = один бакет MinIO = один warehouse Lakekeeper = один каталог Trino. Для бенчмарка — отдельный `bench`,
чтобы 24 тестовые таблицы не смешивались со слоями. Каталог `tpch` — генератор исходных данных.

## Как воспроизвести

Нужен Docker Desktop (у меня 10 CPU, 7.7 ГБ памяти для Docker) и ~10 ГБ свободного диска.

```bash
# 1. стек и хранилище
./scripts/01_up_stack.sh          # 4 контейнера
./scripts/02_init_storage.sh      # бакеты bronze/silver/gold/bench + warehouse в Lakekeeper
./scripts/trino.sh "SHOW CATALOGS"   # bench, bronze, gold, silver, system, tpch

# 2. медальон
./scripts/trino.sh -f sql/10_bronze.sql              # Bronze, batch 1 (tpch.sf10)
./scripts/trino.sh -f sql/11_bronze_dirty_batch.sql  # Bronze, batch 2 (грязная догрузка)
./scripts/trino.sh -f sql/20_silver_dq_checks.sql --output-format CSV_HEADER > results/dq_checks_bronze.csv
./scripts/trino.sh -f sql/21_silver_build.sql        # Silver
./scripts/trino.sh -f sql/22_silver_dq_after.sql --output-format CSV_HEADER > results/dq_checks_silver.csv
./scripts/trino.sh -f sql/30_gold.sql                # Gold
./scripts/trino.sh -f sql/31_gold_vs_reference.sql   # сверка с эталоном: оба EXCEPT = 0
./scripts/layer_stats.py bronze.lakehouse.part ... > results/layer_stats.csv

# 3. бенчмарк (≈ 1 час: 48 CTAS + 24 холодных рестарта)
python3 bench/run_bench.py write write size
python3 bench/run_bench.py query --rounds 3 --warm-runs 3
python3 bench/summarize.py
bench/run_concurrency.sh > results/concurrency_gold_q16.csv   # бонус: 10 потоков

# 4. schema evolution и time travel
python3 scripts/run_schema_evolution.py   # -> results/schema_evolution_log.md
python3 scripts/run_time_travel.py        # -> results/time_travel_log.md

# 5. Spark (jar'ы в git не лежат, качаются один раз)
mkdir -p spark/jars && cd spark/jars
curl -fsSLO https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.7.1/iceberg-spark-runtime-3.5_2.12-1.7.1.jar
curl -fsSLO https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.7.1/iceberg-aws-bundle-1.7.1.jar
cd ../..
spark/run_spark.sh -f spark/bronze_explore.sql      # Spark читает Bronze (на время Spark я останавливаю vk-trino — не хватает памяти)
spark/run_spark.sh -f spark/q16_engine_compare.sql  # бонус: тот же Q16 в Spark
```

Остановить, ничего не удаляя: `docker stop vk-trino vk-lakekeeper vk-pg vk-minio`.
Удалить полностью: `docker rm -f vk-trino vk-lakekeeper vk-pg vk-minio && docker volume rm vk-minio-data vk-pg-data`.

## Структура репозитория

```
README.md                  — этот файл
отчет.md                   — заполненная форма отчёта
.gitignore                 — без данных, jar'ов и логов
catalog/                   — каталоги Trino: bronze/silver/gold/bench (Iceberg REST) и tpch
trino/config.properties    — конфиг Trino (поднят лимит памяти на запрос)
lakekeeper/                — шаблон warehouse для Lakekeeper
scripts/
  01_up_stack.sh           — docker run всех сервисов
  02_init_storage.sh       — бакеты + warehouse
  trino.sh                 — обёртка над CLI Trino
  layer_stats.py           — строки / файлы / МБ / формат / кодек / партиции таблицы
  run_schema_evolution.py  — демо schema evolution (лог в results/)
  run_time_travel.py       — демо time travel и восстановления (лог в results/)
  demo_lib.py              — общий помощник для двух демо
sql/
  10_bronze.sql, 11_bronze_dirty_batch.sql
  20_silver_dq_checks.sql, 21_silver_build.sql, 22_silver_dq_after.sql
  30_gold.sql, 31_gold_vs_reference.sql, 32_control_raw_bronze.sql
  q16_reference.sql        — эталонный Q16 варианта
bench/                     — бенчмарк форматов/кодеков и сводка
spark/                     — конфиг и скрипты Spark (jar'ы не в git)
results/                   — все сырые замеры и логи демо (csv/md/json)
```
