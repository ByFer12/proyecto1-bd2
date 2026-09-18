# ProxySQL

ProxySQL se ejecuta en nodo1 con red del host:

- Administración local: `127.0.0.1:6032`.
- Entrada para clientes: `100.113.38.39:6033`.
- Datos persistentes: volumen Docker `proxy_proxysql_data`.

## Preparación

1. Copiar `conf/proxysql.cnf.example` como `conf/proxysql.cnf`.
2. Sustituir `CAMBIAR_PASSWORD_ADMIN` por una contraseña privada alfanumérica.
3. No agregar `conf/proxysql.cnf` a Git.
4. Validar con `docker compose config` antes de iniciar.

La configuración de backends, usuarios y reglas se realizará por la interfaz
administrativa y se guardará tanto en runtime como en disco.

## Usuarios MySQL

`sql/mysql-users.sql.example` contiene la plantilla para crear:

- `proxysql_monitor`: `USAGE` y `REPLICATION CLIENT` para health checks.
- `app_user`: `SELECT`, `INSERT`, `UPDATE` y `DELETE` únicamente en
  `data_bugs`.

La copia `sql/mysql-users.sql` contiene contraseñas privadas y está ignorada
por Git.

## Hostgroups planificados

| Hostgroup | Función |
|---:|---|
| 10 | Escritores activos: nodo1 y nodo2 |
| 20 | Escritores de respaldo administrados por ProxySQL |
| 30 | Lecturas: nodo3 y escritores habilitados como lectores |
| 40 | Miembros no viables u offline |

`sql/proxysql-admin.sql.example` configura estos grupos, registra los tres
servidores, activa el monitor de Group Replication y dirige `SELECT` normales
al hostgroup 30. Las demás operaciones usan por defecto el hostgroup 10.
