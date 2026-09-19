#!/usr/bin/env bash
# ==============================================================================
# backup_gtid.sh - Snapshot de consistencia y registro de GTID en caliente
# Proyecto 1 - Bases de Datos 2 (Grupo 4)
# Ejecutar en Nodo 1 (Byron)
# ==============================================================================

set -u

OUTPUT_DIR="evidencias/snapshots"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUT_FILE="${OUTPUT_DIR}/snapshot_${TIMESTAMP}.txt"

echo "Generando snapshot de consistencia..."
echo "Archivo de salida: $OUT_FILE"

{
  echo "=================================================================="
  echo "SNAPSHOT DE CONSISTENCIA Y ESTADO - DATA BUGS"
  echo "Fecha y hora: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=================================================================="
  echo ""
  
  echo "--- 1. GTID EJECUTADO (Nodo 1) ---"
  docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT @@global.gtid_executed AS gtid_executed;"' 2>/dev/null
  echo ""

  echo "--- 2. CONTEO EXACTO DE FILAS (data_bugs) ---"
  docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT '\''cliente'\'' AS tabla, COUNT(*) AS filas FROM data_bugs.cliente
  UNION ALL SELECT '\''producto'\'', COUNT(*) FROM data_bugs.producto
  UNION ALL SELECT '\''pedido'\'', COUNT(*) FROM data_bugs.pedido
  UNION ALL SELECT '\''detalle_pedido'\'', COUNT(*) FROM data_bugs.detalle_pedido
  UNION ALL SELECT '\''pago'\'', COUNT(*) FROM data_bugs.pago;
  "' 2>/dev/null
  echo ""

  echo "--- 3. MUESTRA DE ESTADO DE PRODUCTO (Stock actual) ---"
  docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT producto_id, nombre, stock, precio FROM data_bugs.producto WHERE producto_id = 1;
  "' 2>/dev/null
  echo ""

  echo "--- 4. ESTADO DE MEMBRESIA ---"
  docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;
  "' 2>/dev/null
  echo ""

  echo "=================================================================="
} | tee "$OUT_FILE"

echo "Snapshot guardado exitosamente en: $OUT_FILE"

