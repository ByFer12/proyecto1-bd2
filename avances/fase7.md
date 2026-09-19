# Fase 7 — Monitoreo y observabilidad

## Objetivo oficial

Visualizar en tiempo real los tres servidores, MySQL Group Replication y el
comportamiento de la carga en estados normal, fallo, recuperación y
contingencia.

## Diseño seleccionado

| Componente | Ubicación | Función |
|---|---|---|
| `mysqld_exporter` | Uno junto a cada MySQL | Publica estado y métricas de MySQL en `9104` |
| `node_exporter` | Uno junto a cada servidor | Publica CPU y memoria en `9100` |
| Prometheus | Equipo de Carlos | Recolecta y conserva las métricas |
| Grafana | Equipo de Carlos | Presenta el dashboard en `3000` |
| Script de carga SQL | Equipo de Byron | Ejecuta `database/tests/load_phase6.sh` según Fase 6 |

No se instala ningún paquete en Debian, Ubuntu o Windows: se utilizan imágenes
Docker. La carpeta base ya existe en `nodes/node3/monitoreo/`, pero esta fase
no se considera terminada hasta que Prometheus muestre los seis targets
esperados como `UP`.

## Responsables iniciales

- Byron: exporter de nodo1, generación de carga y apoyo en Grafana.
- Michael: exporters de nodo2 y observación durante su caída.
- Carlos: exporter de nodo3, Prometheus, Grafana y capturas.

Todos deben comprender los paneles. Solo el dueño de cada equipo ejecuta sus
comandos Docker locales.

## Reglas previas

- No mostrar ni versionar contraseñas de MySQL o Grafana.
- No reutilizar la contraseña de `root` para el exporter.
- No usar `docker compose down -v`.
- Nodo3 continúa con `read_only=1` y `super_read_only=1`.
- En nodo2 y nodo3 Docker Desktop, `node_exporter` mide la máquina Linux de
  Docker, no todo el host Windows/Debian exterior. Se registra como limitación.

---

## 1. Seleccionar e instalar una herramienta de monitoreo

### 1.1 Crear una cuenta de mínimo privilegio — ejecuta Byron una sola vez

Con los tres nodos `ONLINE`, Byron abre MySQL en nodo1:

```bash
docker exec -it mysql-node1 mysql -uroot -p
```

Dentro de MySQL, reemplaza el marcador por una contraseña privada nueva:

```sql
CREATE USER IF NOT EXISTS 'exporter'@'%'
  IDENTIFIED BY 'CLAVE_PRIVADA_EXPORTER'
  WITH MAX_USER_CONNECTIONS 3;

GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.*
  TO 'exporter'@'%';

SHOW GRANTS FOR 'exporter'@'%';
```

Sirve para: permitir lectura de métricas sin utilizar `root`. El usuario y sus
permisos se replican; la contraseña se guarda en el gestor privado del grupo,
nunca en una captura.

Resultado esperado: aparecen `PROCESS`, `REPLICATION CLIENT` y `SELECT`.

### 1.2 Preparar el archivo privado en cada equipo

Cada integrante crea dentro de su carpeta de monitoreo un archivo `.my.cnf`:

```ini
[client]
user=exporter
password=CLAVE_PRIVADA_EXPORTER
```

En Linux, protegerlo:

```bash
chmod 600 conf/.my.cnf
git check-ignore -v conf/.my.cnf
```

Resultado esperado: `git check-ignore` indica la regla `**/.my.cnf`. Si no la
muestra, no continuar ni hacer commit.

### 1.3 Levantar exporters en nodo1 — ejecuta Byron

Desde `nodes/node1/`, crear `monitoreo/conf/.my.cnf` como en el punto anterior
y ejecutar:

```bash
mkdir -p monitoreo/conf

docker run -d --name mysqld-exporter-node1 \
  --restart unless-stopped --network host \
  -v "$PWD/monitoreo/conf/.my.cnf:/cfg/.my.cnf:ro" \
  prom/mysqld-exporter:v0.15.1 \
  --config.my-cnf=/cfg/.my.cnf \
  --mysqld.address=127.0.0.1:3306 \
  --collect.perf_schema.replication_group_members \
  --collect.perf_schema.replication_group_member_stats \
  --collect.perf_schema.tableiowaits

docker run -d --name node-exporter-node1 \
  --restart unless-stopped --network host --pid host \
  -v '/:/host:ro,rslave' \
  prom/node-exporter:v1.8.1 --path.rootfs=/host
```

Sirve para: publicar MySQL en `.39:9104` y CPU/memoria en `.39:9100`.

Resultado esperado:

```bash
curl -fsS http://127.0.0.1:9104/metrics | grep '^mysql_up'
curl -fsS http://127.0.0.1:9100/metrics | grep '^node_memory_MemTotal_bytes'
```

Ambos devuelven una métrica; `mysql_up 1` significa que el exporter entra a
MySQL correctamente.

Si Docker dice que el nombre ya existe, no crear otro: usar
`docker start mysqld-exporter-node1 node-exporter-node1` y repetir la prueba.

### 1.4 Levantar exporters en nodo2 — ejecuta Michael

Desde `nodes/node2/`, crear `monitoreo/conf/.my.cnf` y ejecutar:

```bash
mkdir -p monitoreo/conf

docker run -d --name mysqld-exporter-node2 \
  --restart unless-stopped --network container:tailscale-node2 \
  -v "$PWD/monitoreo/conf/.my.cnf:/cfg/.my.cnf:ro" \
  prom/mysqld-exporter:v0.15.1 \
  --config.my-cnf=/cfg/.my.cnf \
  --mysqld.address=127.0.0.1:3306 \
  --collect.perf_schema.replication_group_members \
  --collect.perf_schema.replication_group_member_stats \
  --collect.perf_schema.tableiowaits

docker run -d --name node-exporter-node2 \
  --restart unless-stopped --network container:tailscale-node2 \
  --pid host -v '/:/host:ro,rslave' \
  prom/node-exporter:v1.8.1 --path.rootfs=/host
```

Sirve para: publicar ambas métricas a través de la IP Tailscale del sidecar
`.24`. Si `tailscale-node2` se recrea, estos exporters también deben recrearse
porque comparten su espacio de red.

Michael verifica:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' \
  | grep -E 'mysqld-exporter-node2|node-exporter-node2'
```

Esperado: ambos `Up`.

### 1.5 Levantar el stack central y nodo3 — ejecuta Carlos

Antes de iniciar, Carlos reemplaza en
`nodes/node3/monitoreo/docker-compose.yml` la contraseña predeterminada de
Grafana por una variable privada:

```yaml
- GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
```

En `nodes/node3/monitoreo/.env` guarda una contraseña nueva:

```dotenv
GRAFANA_ADMIN_PASSWORD=CLAVE_PRIVADA_GRAFANA
```

También confirma que `conf/.my.cnf` contiene la cuenta `exporter`. Luego:

En el servicio `mysqld-exporter-nodo3`, Carlos agrega al bloque `command`:

```yaml
- "--collect.perf_schema.replication_group_members"
- "--collect.perf_schema.replication_group_member_stats"
- "--collect.perf_schema.tableiowaits"
```

Sirve para: exponer membresía, estadísticas del grupo y tiempos de I/O además
de las métricas básicas.

Luego inicia el stack:

```powershell
cd .\nodes\node3\monitoreo
docker compose up -d
docker compose ps
```

Sirve para: iniciar exporter de nodo3, Prometheus y Grafana.

Resultado esperado: `mysqld-exporter-nodo3`, `node-exporter`, `prometheus` y
`grafana` aparecen `Up`.

> **CAPTURA F7-01:** herramientas seleccionadas y contenedores activos, sin
> secretos visibles.

---

## 2. Configurar la recolección de métricas de los tres nodos

La configuración existente
`nodes/node3/monitoreo/prometheus/prometheus.yml` debe contener:

- MySQL: `.39:9104`, `.24:9104` y exporter local de nodo3.
- Sistema: `.39:9100`, `.24:9100` y exporter local de nodo3.
- Etiquetas `nodo` e `integrante` distintas para cada target.

Carlos reinicia únicamente Prometheus después de revisar el archivo:

```powershell
docker compose restart prometheus
docker logs prometheus --tail 30
```

Luego abre:

```text
http://localhost:9090/targets
```

Sirve para: comprobar que Prometheus puede alcanzar todos los endpoints.

Resultado obligatorio: tres targets del trabajo `mysql-nodes` y tres del
trabajo `node-system` en estado `UP`. Si alguno está `DOWN`, no se crea todavía
el dashboard; se revisa primero IP, puerto, contenedor y logs de ese exporter.

> **CAPTURA F7-02:** página Targets con los seis targets `UP`.

---

## 3. Crear un dashboard del estado general

### Ejecuta: Carlos. Apoyan: Byron y Michael

Carlos abre `http://localhost:3000`, entra con la cuenta privada y agrega un
dashboard llamado `Data Bugs - Cluster MySQL`.

Paneles mínimos y consultas PromQL:

| Panel | Consulta | Interpretación |
|---|---|---|
| MySQL disponible | `mysql_up` | `1` disponible; `0` no disponible |
| Target disponible | `up{job=~"mysql-nodes|node-system"}` | Conectividad de cada exporter |
| CPU usada % | `100 - (avg by(nodo) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)` | Carga de CPU por nodo |
| Memoria usada % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | Memoria utilizada |
| Consultas por segundo | `rate(mysql_global_status_queries[1m])` | Actividad generada |
| Conexiones | `mysql_global_status_threads_connected` | Sesiones abiertas |

Para replicación, agregar estos paneles exactos:

| Panel | Consulta | Interpretación |
|---|---|---|
| Miembros observados | `mysql_perf_schema_replication_group_member_info` | Serie con etiquetas `member_host`, `member_state` y `member_role` |
| Cola de certificación | `mysql_perf_schema_transactions_in_queue` | Transacciones pendientes de verificar |
| Cola remota | `mysql_perf_schema_transactions_remote_in_applier_queue` | Transacciones recibidas pendientes de aplicar |

Para latencia de consultas, buscar en Explore:

```text
mysql_perf_schema_table_io_waits
```

Si la métrica de latencia no aparece, revisar que el exporter tenga activado
`--collect.perf_schema.tableiowaits`. Los tiempos producidos por
`load_phase6.sh` se conservan además como medición de extremo a extremo.

Resultado esperado: los paneles se separan por etiqueta `nodo` y no mezclan
los tres servidores en una sola serie.

> **CAPTURA F7-03:** dashboard completo en operación normal.

---

## 4. Ejecutar nuevamente las pruebas de carga de la Fase 6

### Ejecuta: Byron

No se inventa otra carga. Reutilizar exactamente `avances/fase6.md`, puntos
1–5, mientras Grafana permanece abierto. Los archivos nuevos se guardan en:

```text
evidencias/fase7/resultados/
```

Sirve para: correlacionar la misma carga con CPU, memoria, consultas, estado y
latencia observados.

> **CAPTURA F7-04:** dashboard durante carga con ambos escritores activos.

---

## 5. Observar nodo1 y nodo2 funcionando normalmente

### Observan: los tres integrantes

Antes de provocar fallos, confirmar simultáneamente:

- `mysql_up=1` para nodo1, nodo2 y nodo3.
- Targets `UP`.
- Tres miembros `ONLINE` en Group Replication.
- Actividad de consultas aumenta durante `load_phase6.sh`.
- CPU/memoria tienen valores y etiquetas por nodo.

Sirve para: guardar una línea base con la cual comparar los fallos.

> **CAPTURA F7-05:** estado normal y carga visible.

---

## 6. Provocar la caída de un nodo durante la carga

### Ejecuta: Byron sobre nodo1

Durante la frontera del 50 % definida en Fase 6:

```bash
date --iso-8601=seconds
docker stop mysql-node1
```

Michael y Carlos no detienen nada; observan la continuidad por nodo2 y el
cambio del dashboard.

Resultado esperado: la carga posterior continúa mediante nodo2.

---

## 7. Ver el cambio de estado en el dashboard

### Observa y captura: Carlos

Esperado después del intervalo de scrape:

- MySQL de nodo1 pasa a `0` o su target deja de responder.
- Nodo2 continúa disponible.
- Se observa el instante aproximado del cambio.
- Las consultas continúan y el resultado de `load_phase6.sh` queda registrado.

> **CAPTURA F7-06:** caída de nodo1 visible durante carga.

---

## 8. Recuperar el nodo y comprobar que vuelve a estar disponible

### Ejecuta: Byron

Reutilizar Fase 3, puntos 7–8: encender nodo1, ejecutar
`START GROUP_REPLICATION`, esperar `ONLINE` y comparar GTID. No hacer
bootstrap porque nodo2/nodo3 mantienen el grupo.

Resultado esperado en Grafana:

- `mysql_up` de nodo1 vuelve a `1`.
- Target vuelve a `UP`.
- La membresía vuelve a tres `ONLINE`.

> **CAPTURA F7-07:** recuperación del nodo visible en el dashboard.

---

## 9. Monitorear contingencia: nodo1 y nodo2 fuera, nodo3 solo lectura

### Ejecutan: Byron y Michael. Observa: Carlos

Reutilizar Fase 5, puntos 1–6, y Fase 6, punto 5:

1. Confirmar tres nodos sincronizados.
2. Detener `mysql-node1`.
3. Detener `mysql-node2`, conservando `tailscale-node2`.
4. Ejecutar carga de solo lectura directamente en nodo3.
5. Confirmar `read_only=1` y `super_read_only=1`.

Resultado esperado:

- Nodo1 y nodo2 no disponibles.
- Nodo3 continúa mostrando CPU, memoria y lecturas.
- Las escrituras permanecen bloqueadas.
- La carga de lectura termina y su tiempo queda registrado.

Después recuperar el clúster con Fase 5, puntos 7–10.

> **CAPTURA F7-08:** dashboard de contingencia con solo nodo3 leyendo.

## Registro final

| Escenario | CPU pico N1/N2/N3 | Memoria pico | Latencia | Estado GR | Disponibilidad |
|---|---|---|---|---|---|
| Normal | | | | 3 ONLINE | |
| Carga | | | | 3 ONLINE | |
| Falla nodo1 | | | | N2/N3 ONLINE | |
| Recuperación | | | | 3 ONLINE | |
| Contingencia | | | | solo lectura N3 | |

## Criterio de cierre

- [ ] Prometheus + Grafana están instalados y documentados.
- [ ] Los seis targets aparecen `UP` en estado normal.
- [ ] Dashboard muestra CPU, memoria, MySQL, disponibilidad y replicación.
- [ ] Latencia de carga queda en Grafana o respaldada por `load_phase6.sh`.
- [ ] Se capturaron normalidad, carga, falla, recuperación y contingencia.
- [ ] Se documentó la limitación de Docker Desktop para métricas del host.
- [ ] El clúster terminó con tres miembros `ONLINE` y nodo3 `1/1`.

## Referencias técnicas

- `mysqld_exporter`: https://github.com/prometheus/mysqld_exporter
- `node_exporter` en contenedor: https://github.com/prometheus/node_exporter
- Aprovisionamiento de Grafana: https://grafana.com/docs/grafana/latest/administration/provisioning/
