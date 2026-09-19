#!/bin/sh

# Generador de carga SQL controlada para la Fase 6.
# Se ejecuta dentro de una imagen/contenedor MySQL que ya incluya `mysql`.

set -u

DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-6033}
DB_USER=${DB_USER:-app_user}
DB_SCHEMA=${DB_SCHEMA:-data_bugs}
LOAD_TOTAL=${LOAD_TOTAL:-100}
LOAD_CONCURRENCY=${LOAD_CONCURRENCY:-10}
LOAD_MODE=${LOAD_MODE:-mixed}
LOAD_LABEL=${LOAD_LABEL:-sin-etiqueta}

if [ -z "${MYSQL_PWD:-}" ] && [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
  MYSQL_PWD=$MYSQL_ROOT_PASSWORD
  export MYSQL_PWD
fi

if [ -z "${MYSQL_PWD:-}" ]; then
  echo 'ERROR: MYSQL_PWD no está definida' >&2
  exit 2
fi

case "$LOAD_TOTAL:$LOAD_CONCURRENCY" in
  *[!0-9:]*|0:*|*:0)
    echo 'ERROR: LOAD_TOTAL y LOAD_CONCURRENCY deben ser enteros positivos' >&2
    exit 2
    ;;
esac

case "$LOAD_MODE" in
  mixed|read) ;;
  *)
    echo 'ERROR: LOAD_MODE debe ser mixed o read' >&2
    exit 2
    ;;
esac

load_tmp=$(mktemp -d)
trap 'rm -rf "$load_tmp"' EXIT HUP INT TERM

base=$((LOAD_TOTAL / LOAD_CONCURRENCY))
remainder=$((LOAD_TOTAL % LOAD_CONCURRENCY))
load_start=$(date +%s%N)

run_worker() {
  worker=$1
  operations=$base
  if [ "$worker" -le "$remainder" ]; then
    operations=$((operations + 1))
  fi

  success_file="$load_tmp/success.$worker"
  failure_file="$load_tmp/failure.$worker"
  latency_file="$load_tmp/latency.$worker"
  error_file="$load_tmp/errors.$worker"
  : > "$success_file"
  : > "$failure_file"
  : > "$latency_file"
  : > "$error_file"

  operation=1
  while [ "$operation" -le "$operations" ]; do
    sequence=$((worker + operation))
    if [ "$LOAD_MODE" = read ] || [ $((sequence % 2)) -eq 0 ]; then
      sql='SELECT nombre,stock FROM producto WHERE producto_id=1;'
    else
      sql='UPDATE producto SET stock=stock WHERE producto_id=1;'
    fi

    operation_start=$(date +%s%N)
    if mysql --protocol=TCP --connect-timeout=5 \
      -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" "$DB_SCHEMA" \
      -e "$sql" >/dev/null 2>>"$error_file"; then
      echo 1 >> "$success_file"
    else
      echo 1 >> "$failure_file"
    fi
    operation_end=$(date +%s%N)
    echo $(((operation_end - operation_start) / 1000000)) >> "$latency_file"
    operation=$((operation + 1))
  done
}

worker=1
while [ "$worker" -le "$LOAD_CONCURRENCY" ]; do
  run_worker "$worker" &
  worker=$((worker + 1))
done
wait

load_end=$(date +%s%N)
duration_ms=$(((load_end - load_start) / 1000000))
successes=$(cat "$load_tmp"/success.* | wc -l | tr -d ' ')
failures=$(cat "$load_tmp"/failure.* | wc -l | tr -d ' ')

set -- $(cat "$load_tmp"/latency.* | awk '
  NR == 1 { min=$1; max=$1 }
  { sum+=$1; if ($1<min) min=$1; if ($1>max) max=$1 }
  END { if (NR==0) print "0 0 0"; else printf "%.2f %d %d\n", sum/NR, min, max }
')
average_ms=$1
minimum_ms=$2
maximum_ms=$3
availability=$(awk -v ok="$successes" -v total="$LOAD_TOTAL" \
  'BEGIN { printf "%.2f", (ok/total)*100 }')

printf '%s\n' 'RESULTADO_CARGA_FASE6'
printf 'escenario=%s\n' "$LOAD_LABEL"
printf 'modo=%s\n' "$LOAD_MODE"
printf 'clientes_concurrentes=%s\n' "$LOAD_CONCURRENCY"
printf 'operaciones_intentadas=%s\n' "$LOAD_TOTAL"
printf 'operaciones_exitosas=%s\n' "$successes"
printf 'operaciones_fallidas=%s\n' "$failures"
printf 'duracion_total_ms=%s\n' "$duration_ms"
printf 'latencia_promedio_ms=%s\n' "$average_ms"
printf 'latencia_minima_ms=%s\n' "$minimum_ms"
printf 'latencia_maxima_ms=%s\n' "$maximum_ms"
printf 'disponibilidad_porcentaje=%s\n' "$availability"

if [ "$failures" -gt 0 ]; then
  echo 'ERRORES_OBSERVADOS'
  cat "$load_tmp"/errors.*
fi
