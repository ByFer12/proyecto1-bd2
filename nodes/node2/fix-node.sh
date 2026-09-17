#!/bin/bash

set -euo pipefail

echo "=== Recreando nodo2 sin borrar sus datos ==="
docker compose up -d --force-recreate

echo "=== Esperando el healthcheck de MySQL ==="
for intento in $(seq 1 60); do
    estado=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' mysql-node2)

    if [ "$estado" = "healthy" ]; then
        echo "mysql-node2 esta healthy"
        docker compose ps
        exit 0
    fi

    if [ "$estado" = "exited" ] || [ "$estado" = "dead" ]; then
        echo "mysql-node2 termino inesperadamente"
        docker logs mysql-node2 --tail 50
        exit 1
    fi

    echo "Intento $intento/60: estado=$estado"
    sleep 2
done

echo "mysql-node2 no llego a healthy dentro del tiempo esperado"
docker logs mysql-node2 --tail 50
exit 1
