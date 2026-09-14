# Nodo 3

Este directorio contiene la instancia MySQL local de Carlos 

## Preparación local

1. Copiar `.env.example` como `.env` (si aún no existe).
2. Definir la contraseña en `MYSQL_ROOT_PASSWORD`.
3. Ejecutar `docker compose up -d`.
4. Verificar el estado del contenedor y su healthcheck con `docker compose ps`.
5. Conectarse por el puerto local `3306`.

Ejemplo de conexión local:

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p
```

## Puertos expuestos

- `3306`: Puerto estándar de cliente MySQL para conexiones locales, ProxySQL y monitoreo.
- `33061`: Puerto de comunicación interna para MySQL Group Replication.

Esta configuración prepara el nodo para replicación GTID y carga el módulo `group_replication.so`. La unión formal al clúster se realiza una vez que el Nodo 1 haya inicializado el grupo.
