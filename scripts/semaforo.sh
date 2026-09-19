#!/usr/bin/env bash
# ==============================================================================
# semaforo.sh - Diagnostico rapido del estado del cluster y balanceador
# Proyecto 1 - Bases de Datos 2 (Grupo 4)
# Ejecutar en Nodo 1 (Byron)
# ==============================================================================

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}        DIAGNOSTICO DE SALUD DEL CLUSTER - DATA BUGS            ${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo "Fecha y hora: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. Estado de contenedores locales
echo -e "${YELLOW}[1/4] Contenedores locales en Nodo 1:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E 'NAMES|mysql-node1|proxysql-db2'
echo ""

# 2. Estado de membresia de Group Replication
echo -e "${YELLOW}[2/4] Miembros de Group Replication (performance_schema):${NC}"
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE 
FROM performance_schema.replication_group_members;
"' 2>/dev/null || echo -e "${RED}[ERROR] No se pudo conectar a mysql-node1.${NC}"
echo ""

# 3. Estado de servidores en ProxySQL
echo -e "${YELLOW}[3/4] Estado en runtime de ProxySQL (puerto 6032):${NC}"
docker exec proxysql-db2 mysql -uadmin -padministradordb123 -h127.0.0.1 -P6032 -e "
SELECT hostgroup_id, hostname, port, status, weight 
FROM runtime_mysql_servers;
" 2>/dev/null || echo -e "${RED}[ERROR] No se pudo conectar a ProxySQL Admin.${NC}"
echo ""

# 4. Resumen de metricas de conexion y queries en ProxySQL
echo -e "${YELLOW}[4/4] Estadisticas de trafico por backend (ProxySQL):${NC}"
docker exec proxysql-db2 mysql -uadmin -padministradordb123 -h127.0.0.1 -P6032 -e "
SELECT hostgroup, srv_host, status, ConnUsed, Queries, Bytes_data_sent 
FROM stats_mysql_connection_pool;
" 2>/dev/null || echo -e "${RED}[ERROR] No se pudieron leer stats de conexion.${NC}"
echo ""

echo -e "${BLUE}==================================================================${NC}"
echo -e "${GREEN}[FIN DEL REPORTE]${NC}"
echo -e "${BLUE}==================================================================${NC}"

