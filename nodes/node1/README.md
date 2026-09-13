# Nodo 1

Este directorio contiene la instancia MySQL local de Byron.

## Preparacion local

1. Copiar `.env.example` como `.env`.
2. Cambiar la contrasena de `MYSQL_ROOT_PASSWORD`.
3. Ejecutar `docker compose up -d`.
4. Verificar el estado con `docker compose ps`.
5. Conectarse por el puerto local `3307`.

Ejemplo de conexion:

```bash
mysql -h 127.0.0.1 -P 3307 -u root -p
```

Esta configuracion prepara el nodo para replicacion, pero no activa Group Replication todavia. Las direcciones Tailscale y los miembros del grupo se agregaran cuando Michael y Carlos entreguen sus IP.
