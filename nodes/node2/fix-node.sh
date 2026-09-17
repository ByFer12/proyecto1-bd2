#!/bin/bash

# Asegurar que el script se detenga si ocurre un error
set -e

echo "=== 1. Deteniendo y eliminando contenedores ==="
docker compose down

echo "=== 2. Restaurando permisos de la carpeta data ==="
sudo chown -R $USER:$USER data/
sudo chmod -R 777 data/

echo "=== 3. Limpieza profunda del volumen de datos ==="
rm -rf data/*

echo "=== 4. Volviendo a levantar el entorno ==="
docker compose up -d

echo "=== 5. Esperando a que MySQL esté listo para recibir conexiones ==="
#until docker exec mysql-node2 mysqladmin ping -h"localhost" -uroot -pnodo2 --silent; do
#    echo "Esperando a que MySQL arranque..."
#    sleep 3
#done

echo "=== 6. ¡Proceso finalizado con éxito! Mostrando logs recientes ==="
docker logs mysql-node2 --tail 15

#echo "=== 7. Configurando el usuario de replicación y el canal de recuperación ==="
#docker exec mysql-node2 mysql -u root -pnodo2 -e "
#CREATE USER 'repl'@'%' IDENTIFIED BY 'nodo2';
#GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
#FLUSH PRIVILEGES;
#CHANGE REPLICATION SOURCE TO SOURCE_USER='repl', SOURCE_PASSWORD='nodo2' FOR CHANNEL 'group_replication_recovery';
#"