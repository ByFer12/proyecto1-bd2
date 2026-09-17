# Nodo 3 (Carlos - Réplica / Contingencia)

Este directorio contiene la configuración y definición del contenedor MySQL del **Nodo 3** para el clúster de Group Replication sobre Tailscale.

---

## 1. Identificación y Red

- **Rol en el clúster:** Réplica de contingencia / Lector (Multi-Primary habilitado)
- **IP Tailscale asignada:** `100.107.61.57`
- **Puertos expuestos:**
  - `3306`: Tráfico estándar de cliente MySQL, ProxySQL y monitoreo.
  - `33061`: Canal interno del protocolo Group Replication (Paxos / XCom).

---

## 2. Preparación y Despliegue Local

1. Copiar `.env.example` como `.env` (si aún no existe):
   ```bash
   cp .env.example .env
   ```
2. Iniciar el servicio con Docker Compose:
   ```bash
   docker compose up -d
   ```
3. Comprobar el estado del contenedor y su healthcheck:
   ```bash
   docker compose ps
   ```

---

## 3. Configuración de Replicación

### 3.1. Configuración del Usuario de Recuperación (Ejecutar una sola vez)
```sql
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED BY 'replpass123';
GRANT REPLICATION SLAVE, REPLICATION_APPLIER, BACKUP_ADMIN ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;

CHANGE REPLICATION SOURCE TO
  SOURCE_USER='repl_user',
  SOURCE_PASSWORD='replpass123'
  FOR CHANNEL 'group_replication_recovery';
```

### 3.2. Unión al Clúster
> **Nota:** El Nodo 1 (Byron) debe haber ejecutado el bootstrap inicial antes de que este nodo pueda unirse.

```sql
START GROUP_REPLICATION;
```

---

## 4. Consultas de Verificación y Monitoreo

- **Ver estado y miembros del grupo:**
  ```sql
  SELECT member_id, member_host, member_port, member_state, member_role
  FROM performance_schema.replication_group_members;
  ```
  *(El estado esperado es `ONLINE`)*.

- **Ver transacciones ejecutadas (GTID):**
  ```sql
  SELECT @@global.gtid_executed;
  ```

- **Ver estadísticas de sincronización:**
  ```sql
  SELECT * FROM performance_schema.replication_group_member_stats\G
  ```