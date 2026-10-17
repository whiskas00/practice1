#!/usr/bin/env bash
# Spark 3.5.3 в Docker, подключённый к моему lakehouse (Lakekeeper + MinIO).
#   spark/run_spark.sh                      -- интерактивный spark-sql
#   spark/run_spark.sh -f spark/xxx.sql     -- выполнить файл
# Перед запуском скачай jar'ы (см. README) в spark/jars/.
set -euo pipefail
cd "$(dirname "$0")/.."
TTY=""; [ $# -eq 0 ] && TTY="-it"
docker run --rm $TTY --name vk-spark \
  --add-host host.docker.internal:host-gateway \
  -v "$(pwd)/spark/conf:/opt/spark/conf" \
  -v "$(pwd)/spark/jars:/opt/spark/iceberg-jars" \
  -v "$(pwd)/spark:/opt/spark/work" \
  apache/spark:3.5.3 \
  /opt/spark/bin/spark-sql "${@/#spark\//\/opt\/spark\/work\/}"
