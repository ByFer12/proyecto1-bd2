# Manual de Integración y Configuración Posterior (instructions.md)

Este documento detalla los pasos operativos y comandos exactos que debes ejecutar en tu Debian 12 (Nodo 2) después de coordinar con Byron (Nodo 1) para activar el clúster y la red privada.

**1. Verificación final de red privada**
* Asegúrate de que todos los integrantes hayan registrado sus direcciones IP de Tailscale (tu IP es `100.73.247.97`).
* Ejecuta pruebas de conectividad bidireccional mediante `ping`:
  ```bash
  ping <IP_Tailscale_Nodo1>
  ping <IP_Tailscale_Nodo3>
  ```
* **Regla:** No avances a la replicación si algún `ping` falla.

**2. Configuración y Activación de Group Replication**
* Ingresa a tu contenedor MySQL desde la terminal:
  ```bash
  docker exec -it mysql-node2 mysql -uroot -proot_password_seguro
  ```
* Inicia Group Replication ejecutando el comando de inicio en tu consola MySQL [cite: 3]:
  ```sql
  START GROUP_REPLICATION;
  ```
* Valida que el estado del nodo sea `ONLINE` [cite: 3, 5]:
  ```sql
  SELECT * FROM performance_schema.replication_group_members;
  ```

**3. Pruebas de Replicación Normal (Fase 2 del Proyecto)**
* Conéctate a tu base de datos e inserta un registro de prueba para verificar la sincronización bidireccional entre nodos [cite: 5]:
  ```sql
  INSERT INTO cliente (nombre) VALUES ('Prueba Replicacion Nodo2');
  SELECT * FROM cliente;
  ```

**4. Configuración de ProxySQL y Enrutamiento**
* Accede a la interfaz de administración de ProxySQL para registrar los servidores en los grupos correspondientes [cite: 5]:
  ```bash
  mysql -u admin -padmin -h 127.0.0.1 -P 6032
  ```
* Verifica el estado de los *health checks* y los nodos activos en el proxy [cite: 3, 5].

**5. Pruebas de Failover y Tolerancia a Fallos**
* Simula una caída controlada del Nodo 1 ejecutando en tu terminal [cite: 4, 5]:
  ```bash
  docker stop mysql-node1
  ```
* Comprueba que ProxySQL redirija las escrituras al Nodo 2 y registra el tiempo de recuperación (RTO) [cite: 4, 5].
* Reintegra el nodo afectado ejecutando [cite: 3, 4, 5]:
  ```bash
  docker start mysql-node1
  ```
