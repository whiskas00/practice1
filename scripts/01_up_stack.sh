#!/usr/bin/env bash
# Поднимает мой стек: MinIO (silo) -> Postgres -> Lakekeeper -> Trino.
# Имена контейнеров и томов с префиксом vk-, чтобы не пересекаться с чужими контейнерами на машине.
# Postgres проброшен на 5433, потому что 5432 занят локальным Postgres.
set -euo pipefail
cd "$(dirname "$0")/.."

PG_PORT=5433
PG_URL="postgresql://postgres:postgres@host.docker.internal:${PG_PORT}/postgres"
LK_KEY='This-is-NOT-Secure!'

# 1. MinIO: S3-хранилище, сюда физически падают parquet/orc-файлы
docker run -d --name vk-minio \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  -v vk-minio-data:/data \
  pgsty/silo:latest server /data --console-address ":9001"

# 2. Postgres: тут Lakekeeper хранит метаданные каталога
docker run -d --name vk-pg \
  -e POSTGRES_PASSWORD=postgres \
  -p ${PG_PORT}:5432 \
  -v vk-pg-data:/var/lib/postgresql/data \
  postgres:17

echo "жду Postgres..."
until docker exec vk-pg pg_isready -q; do sleep 1; done
sleep 2

# 3. Миграции БД Lakekeeper (один раз) и сам Lakekeeper (Iceberg REST Catalog на 8181)
docker run --rm \
  -e "LAKEKEEPER__PG_ENCRYPTION_KEY=${LK_KEY}" \
  -e "LAKEKEEPER__PG_DATABASE_URL_READ=${PG_URL}" \
  -e "LAKEKEEPER__PG_DATABASE_URL_WRITE=${PG_URL}" \
  quay.io/lakekeeper/catalog:latest-main migrate

docker run -d --name vk-lakekeeper \
  -e "LAKEKEEPER__PG_ENCRYPTION_KEY=${LK_KEY}" \
  -e "LAKEKEEPER__PG_DATABASE_URL_READ=${PG_URL}" \
  -e "LAKEKEEPER__PG_DATABASE_URL_WRITE=${PG_URL}" \
  -p 8181:8181 \
  quay.io/lakekeeper/catalog:latest-main serve

# 4. Trino: монтирую папку catalog/ целиком (bronze/silver/gold/bench/tpch)
#    и свой config.properties (поднят лимит памяти на запрос до 4GB)
docker run -d --name vk-trino \
  -p 8080:8080 \
  -v "$(pwd)/catalog:/etc/trino/catalog" \
  -v "$(pwd)/trino/config.properties:/etc/trino/config.properties" \
  trinodb/trino:476

docker ps --filter name=vk- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
