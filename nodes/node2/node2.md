# Documentación del Nodo 2 - Configuración (MySQL 8.4)

## 1. Archivo de Configuración (`conf/my.cnf`)
```ini
[mysqld]
server-id = 2
gtid_mode = ON
enforce_gtid_consistency = ON
log_bin = mysql-bin
```

## Definición del Contenedor `docker-compose.yml`
```ini
services:
  mysql-node2:
    image: mysql:8.4
    container_name: mysql-node2
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: root_password_seguro
    ports:
      - "3306:3306"
      - "33061:33061"
    volumes:
      - ./data:/var/lib/mysql
      - ./conf/my.cnf:/etc/mysql/conf.d/my.cnf
    networks:
      - red-proyecto

networks:
  red-proyecto:
    driver: bridge
```
## Instrucciones de Inicialización y Limpiez
```bash
docker compose down -v
sudo rm -rf data conf
mkdir conf data
```

# (Asegúrate de colocar el contenido en conf/my.cnf y docker-compose.yml)
```bash
docker compose up -d
```

## Comprobación de Funcionamiento
```bash
sleep 10
docker exec -it mysql-node2 mysql -uroot -proot_password_seguro
```

Ejecutar las consultas de validación dentro de la base de datos:
```bash
SELECT @@server_id;
SHOW VARIABLES LIKE 'gtid_mode';
```


# Guía de Trabajo (Nodo 2, Red, Proxy y Failover)

Este documento detalla el proceso paso a paso correspondiente a las responsabilidades de **Michael** en el Grupo 4 para el Proyecto 1 de Bases de Datos 2 (MySQL).

---

## 1. Preparación del Entorno (Nodo 2)

### 1.1. Herramientas mínimas requeridas
Asegúrate de tener instalado en tu equipo:
- Docker
- Docker Compose
- Git
- Tailscale
- MySQL Shell

Verifica las versiones con los siguientes comandos:
```bash
docker --version
docker compose version
git --version
tailscale version
mysqlsh --version
```

### 1.2. Configuración base de MySQL (Docker)
Configura el contenedor del Nodo 2 asegurando los siguientes parámetros obligatorios para Group Replication:
- `server_id = 2`
- `hostname = mysql-node2`
- Binary logs habilitados (`log_bin`)
- GTID habilitado (`gtid_mode=ON`)

---

## 2. Red Privada (Tailscale)

### 2.1. Conexión a la red
1. Instala y autentícate en Tailscale en tu equipo.
2. Conéctate a la red privada compartida con Byron (Nodo 1) y Carlos (Nodo 3).
3. Obtén tu dirección IP de Tailscale y regístrala con el equipo. 100.73.247.97

### 2.2. Pruebas de conectividad obligatorias
Valida la comunicación bidireccional antes de continuar:
```bash
ping <IP_Tailscale_Nodo1>
ping <IP_Tailscale_Nodo3>
```
> **Regla:** No avanzar a la replicación hasta que `Nodo1 ↔ Nodo2`, `Nodo1 ↔ Nodo3` y `Nodo2 ↔ Nodo3` estén completamente operativos.

---

## 3. Configuración de ProxySQL y Enrutamiento

### 3.1. Objetivo
Evitar que el cliente deba decidir manualmente a qué nodo conectarse, centralizando el tráfico a través de un único punto de entrada mediante ProxySQL.

### 3.2. Registro de servidores en el Proxy
- **Grupo de Escritura (WRITE):**
  - Nodo 1
  - Nodo 2
- **Grupo de Lectura (READ):**
  - Nodo 1
  - Nodo 2
  - Nodo 3 (orientado a contingencia / lectura exclusiva)

### 3.3. Health Checks
Configurar verificaciones periódicas para asegurar que:
1. El servidor sea accesible a nivel de red.
2. El servicio MySQL responda peticiones.
3. El miembro sea válido dentro del clúster de Group Replication.

---

## 4. Pruebas de Failover y Recuperación

### 4.1. Escenario de caída (Nodo 1 o Nodo 2)
1. Simular la caída de un nodo deteniendo su contenedor.
2. Comprobar que las escrituras se redirigen al nodo disponible y las lecturas siguen respondiendo.
3. Registrar métricas para el cálculo del **RTO** ($T_1 - T_0$).

### 4.2. Recuperación e reintegración
1. Encender el nodo afectado.
2. Esperar su sincronización automática mediante Group Replication.
3. Validar que retorne al estado `ONLINE`.

---

## 5. Automatización de Pruebas

Michael participa en la creación y mantenimiento de los scripts de control ubicados en la carpeta `scripts/`:
- `fail-node1.sh` / `fail-node2.sh`: Interrupción controlada de nodos.
- `recover-node1.sh` / `recover-node2.sh`: Reinicio y reincorporación al clúster.
- Pruebas de validación de tráfico a través de ProxySQL.
