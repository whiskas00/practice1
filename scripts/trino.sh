#!/usr/bin/env bash
# Обёртка над CLI Trino внутри контейнера.
#   scripts/trino.sh "SELECT 1"          -- выполнить запрос
#   scripts/trino.sh -f sql/10_bronze.sql -- выполнить файл
set -euo pipefail
# предупреждение jline про "dumb terminal" убираю, оно мешает читать вывод
exec 2> >(grep -v -e "org.jline" -e "dumb terminal" >&2)
if [ "${1:-}" = "-f" ]; then
  shift; f="$1"; shift
  docker exec -i -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 vk-trino trino --progress=false "$@" < "$f"
else
  sql="$1"; shift
  docker exec -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 vk-trino trino --progress=false --execute "$sql" "$@"
fi
