#!/usr/bin/env bash
# Бакеты в MinIO + warehouse в Lakekeeper под каждый слой медальона и отдельный под бенчмарк.
set -euo pipefail
cd "$(dirname "$0")/.."

LAYERS="bronze silver gold bench"

# бакеты (через клиент mc, это то же самое, что кнопка Create Bucket в консоли)
docker run --rm --entrypoint /bin/sh --add-host host.docker.internal:host-gateway \
  pgsty/mc:latest -c "mc alias set m http://host.docker.internal:9000 minioadmin minioadmin >/dev/null && \
    for b in $LAYERS; do mc mb --ignore-existing m/\$b; done && mc ls m"

until curl -sf http://localhost:8181/health >/dev/null; do sleep 1; done

# принять Terms of Use (если уже принято, Lakekeeper ответит ошибкой, это нормально)
curl -s -o /dev/null -w "bootstrap: %{http_code}\n" -X POST http://localhost:8181/management/v1/bootstrap \
  -H "Content-Type: application/json" -d '{"accept-terms-of-use": true}'

for wh in $LAYERS; do
  sed "s/__NAME__/$wh/g" lakekeeper/warehouse.json.tpl | \
    curl -s -w "  -> warehouse $wh: %{http_code}\n" -X POST http://localhost:8181/management/v1/warehouse \
      -H "Content-Type: application/json" -d @-
done
