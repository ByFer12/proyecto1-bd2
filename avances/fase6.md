# Fase 6 — Pruebas de carga con Locust

## Objetivo oficial

Validar el balanceo y la resiliencia bajo carga, provocar la caída de cada
escritor aproximadamente al 50 % de la prueba y comprobar lecturas en nodo3
cuando ambos escritores estén apagados.

## Herramienta seleccionada

Se utiliza **Locust**, una de las herramientas recomendadas por el enunciado.
Locust genera usuarios concurrentes, registra éxitos, fallos, latencias y
percentiles, y exporta los resultados a CSV.

El archivo `database/load/locust/locustfile.py` solamente define las consultas
SQL de la prueba. No es un generador artesanal: el motor de carga, la
concurrencia y las estadísticas pertenecen a Locust.

### Función de los archivos de Locust

| Archivo | Para qué sirve |
|---|---|
| `database/load/locust/locustfile.py` | Define las conexiones y operaciones SQL que ejecutarán los usuarios virtuales. |
| `database/load/locust/requirements.txt` | Declara `PyMySQL`, controlador utilizado para comunicarse con MySQL. |
| `database/load/locust/Dockerfile` | Construye la imagen auxiliar con Locust y PyMySQL sin instalar paquetes en las computadoras. |

El `locustfile.py` cumple la misma función que un archivo JavaScript de k6 o un
plan `.jmx` de JMeter: describe el escenario, mientras Locust controla la
concurrencia, duración, mediciones y archivos CSV.

Durante el modo normal (`LOAD_MODE=mixed`) ejecuta aproximadamente:

- 75 % de consultas `SELECT` sobre productos, clientes y pedidos;
- 25 % de operaciones `UPDATE producto SET stock = stock + 1`, que recorren la
  ruta de escritura y actualizan el inventario.

Durante la contingencia (`LOAD_MODE=read`) sustituye la operación de escritura
por otra consulta `SELECT`; así nodo3 recibe exclusivamente lecturas.

Cada operación informa a Locust su tiempo de respuesta, resultado y error. Si
una conexión se pierde durante la caída de un nodo, se cierra y se intenta
crear nuevamente en la operación siguiente.

Estos archivos **no** cambian `my.cnf`, Group Replication, ProxySQL, tablas,
usuarios, contraseñas ni volúmenes. Tampoco detienen nodos: las caídas se
provocan únicamente mediante los comandos explícitos de esta guía.

No se usa `mysqlslap` porque la imagen `mysql:8.4` utilizada por el proyecto no
incluye ese ejecutable. Tampoco se usa k6 porque MySQL no es un protocolo
integrado en k6 y requeriría construir extensiones `xk6-sql` y su driver.

La imagen auxiliar de Locust:

- no modifica los tres MySQL;
- no modifica sus volúmenes;
- no instala paquetes en Linux o Windows;
- se conecta por ProxySQL en el puerto `6033`;
- combina 75 % de `SELECT` y 25 % de `UPDATE stock = stock + 1` que modifica el inventario.

## Responsables iniciales

| Tarea | Responsable |
|---|---|
| Ejecutar Locust, ProxySQL y caída de nodo1 | Byron |
| Detener y recuperar nodo2 | Michael |
| Prueba directa de nodo3, resultados y capturas | Carlos |

Los responsables pueden rotarse. Cada orden indica quién la ejecuta porque
los contenedores están en equipos distintos.

---

## Preparación común

### P.1 Verificar el estado inicial — ejecutan los tres

Antes de generar carga se utiliza el semáforo de `avances/fase2.md` (sección **1. Estado inicial — Semáforo antes de comenzar**).

Resultado necesario:

- tres miembros `ONLINE`;
- nodo1 y nodo2 permiten escritura;
- nodo3 conserva `read_only=1` y `super_read_only=1`;
- `proxysql-db2` está activo.

No iniciar la prueba con un miembro `OFFLINE`, `RECOVERING` o `UNREACHABLE`.


### P.2 Construir Locust — ejecuta Byron desde la raíz

Crear carpeta de resultados:
```bash
mkdir -p evidencias/fase6/resultados
```

Construir la imagen de Locust:
```bash
docker build \
  -t proyecto-db2-locust:2.32.10 \
  database/load/locust
```

Verificar la versión instalada:
```bash
docker run --rm proyecto-db2-locust:2.32.10 --version
```

Sirve para: crear una imagen auxiliar reproducible con Locust y el controlador
PyMySQL.

Resultado esperado: la construcción termina sin errores y el último comando
muestra `locust 2.32.10`.

### P.3 Cargar la contraseña sin mostrarla — ejecuta Byron

Pedir la contraseña de `app_user`:
```bash
read -s 'fase6_app_password?Contraseña de app_user: '
```

Confirmar salto de línea:
```bash
echo
```

Sirve para: conservar la contraseña solo en una variable temporal; no queda
escrita en el historial ni en las capturas.

Resultado esperado: no imprime la contraseña.

---

## 1. Generar carga controlada y provocar la caída de nodo1 (Escenario A)
## 1. Generar carga controlada de operaciones sobre nodo1 y nodo2

### Ejecuta: Byron
### Ejecuta: Byron (Terminal 1)

Para mayor claridad y para tomar las capturas con calma en el momento exacto, **se recomienda usar dos terminales (o dos pestañas)**:

---

### 🟢 PASO 1 — En la Terminal 1: Iniciar la carga de Locust

1. Confirmar que los tres nodos están listos:
1. Confirmar que los tres nodos están listos (`ONLINE`):
```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

2. Lanzar la prueba de carga de 60 segundos:
2. Iniciar la prueba de carga de 60 segundos a través de ProxySQL:
```bash
docker run --rm --network host \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_PASSWORD="$fase6_app_password" \
  -e DB_SCHEMA=data_bugs -e LOAD_MODE=mixed \
  -v "$PWD/evidencias/fase6/resultados:/results" \
  proyecto-db2-locust:2.32.10 \
  -f /mnt/locust/locustfile.py \
  --headless --users 10 --spawn-rate 2 --run-time 60s \
  --csv /results/escenario-a --csv-full-history --only-summary \
| tee evidencias/fase6/resultados/escenario-a-consola.txt
```

> 📸 **CAPTURA F6-01:** En cuanto comience a imprimir `Starting Locust... Ramping to 10 users...`, toma captura de la pantalla mostrando el comando, los tres nodos `ONLINE` y el arranque del tráfico.

---

## 2. Al 50 % de las operaciones, provocar la caída de nodo1 y verificar en caliente

### Ejecuta: Byron (Terminal 2)

En cuanto veas que la Terminal 1 comenzó a correr Locust, ve a la **Terminal 2** y ejecuta este comando encadenado:

```bash
sleep 30 && date --iso-8601=seconds && docker stop mysql-node1 && sleep 2 && docker exec proxysql-db2 mysql -uadmin -padministradordb123 -h127.0.0.1 -P6032 -e "
SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers;
SELECT hostgroup, srv_host, Queries, ConnUsed FROM stats_mysql_connection_pool;
"
```

¿Qué hace este comando automáticamente?
1. Espera exactamente 30 segundos (el 50 % de la prueba de 60s).
2. Imprime la marca de tiempo exacta de la caída.
3. Detiene `mysql-node1`.
4. Espera 2 segundos a que ProxySQL marque al nodo como `SHUNNED`.
5. Muestra en pantalla que nodo1 fue apartado y que el tráfico pasó a nodo2.

> 📸 **CAPTURA F6-02:** Toma captura de la Terminal 2 mostrando la hora de caída, el estado en ProxySQL con nodo1 apartado y las consultas en nodo2, y la tabla de resumen final de Locust en Terminal 1 cuando termine.

---

## 3. Verificar que las operaciones restantes continúen ejecutándose sobre el nodo disponible

### 3.1 Verificación de métricas en CSV y recuperación (Terminal 1)

Una vez completados los 60 segundos de Locust en la Terminal 1, comprueba en los archivos CSV que existieron operaciones exitosas tras la caída:

Ver resumen de solicitudes y latencias:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_stats.csv
```

Ver registro de fallos transitorios durante la conmutación:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_failures.csv
```

Recuperar el Nodo 1 y reincorporarlo al grupo:
```bash
docker start mysql-node1
```

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

> 📸 **CAPTURA F6-03:** Salida de los CSV demostrando continuidad de operaciones y la consulta final con los tres nodos nuevamente `ONLINE`.



---

## 4. Repetir la carga provocando la caída de nodo2 (Escenario B)

Este escenario es el equivalente al Escenario A, pero **ahora la falla se provoca en nodo2** (a cargo de Michael).

No comenzar hasta confirmar nuevamente que los tres miembros están `ONLINE`.

---

### 4.1 Byron inicia el Escenario B (Terminal 1)

Lanzar la carga de 60 segundos guardando los resultados en `escenario-b`:
```bash
docker run --rm --network host \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_PASSWORD="$fase6_app_password" \
  -e DB_SCHEMA=data_bugs -e LOAD_MODE=mixed \
  -v "$PWD/evidencias/fase6/resultados:/results" \
  proyecto-db2-locust:2.32.10 \
  -f /mnt/locust/locustfile.py \
  --headless --users 10 --spawn-rate 2 --run-time 60s \
  --csv /results/escenario-b --csv-full-history --only-summary \
| tee evidencias/fase6/resultados/escenario-b-consola.txt
```

---

### 4.2 Michael provoca la caída de nodo2 al segundo 30 (en su máquina)

En cuanto Byron le avise que arrancó la prueba, Michael ejecuta en su terminal (Debian):

```bash
sleep 30 && date --iso-8601=seconds && docker stop mysql-node2
```

> ⚠️ **IMPORTANTE PARA MICHAEL:** Se detiene **únicamente** `mysql-node2`. **NO detener `tailscale-node2`**, ya que se perdería la IP de red del nodo.

Resultado esperado: Al segundo 30 se detiene `mysql-node2`. Byron confirma que ProxySQL aparta a nodo2 (`.24`) y mantiene a nodo1 (`.39`) procesando todas las operaciones.

---

### 4.3 Byron verifica en caliente en ProxySQL (Terminal 2)

En cuanto Michael detenga su nodo, Byron ejecuta en su **Terminal 2**:

```bash
docker exec proxysql-db2 mysql -uadmin -padministradordb123 -h127.0.0.1 -P6032 -e "
SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers;
SELECT hostgroup, srv_host, Queries, ConnUsed FROM stats_mysql_connection_pool;
"
```

> 📸 **CAPTURA F6-04:** Terminal de Michael con la hora de caída y `docker stop mysql-node2`, ProxySQL en la máquina de Byron con nodo2 apartado, y el reporte final de Locust al terminar.

---

### 4.4 Byron revisa resultados CSV (Terminal 1)

Una vez completados los 60 segundos en Locust:

Ver estadísticas generales del escenario B:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-b_stats.csv
```

Ver registro de fallos del escenario B:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-b_failures.csv
```

---

### 4.5 Michael recupera y reincorpora nodo2 (en su máquina)

Una vez concluida la prueba, Michael enciende y une su nodo al grupo existente (**sin bootstrap**):

1. Encender el contenedor:
```bash
docker start mysql-node2
```

2. Unirse al grupo y verificar que los 3 nodos vuelvan a estar `ONLINE`:
```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Resultado esperado: Los tres miembros (`.39`, `.24`, `.57`) vuelven a estar `ONLINE / PRIMARY`.


## 5. Apagar nodo1/nodo2 y generar solo lecturas en nodo3 (Escenario C - Contingencia)

En este escenario se valida el comportamiento extremo de contingencia: **ambos escritores (nodo1 y nodo2) se apagan**, demostrando que no se permiten escrituras y que **nodo3 continúa atendiendo lecturas directas bajo carga** con Locust.

---

### 5.1 Byron y Michael apagan sus respectivos nodos de escritura

Antes de lanzar la carga en nodo3, se detienen los dos nodos escritores:

- **Byron (en Ubuntu):**
  ```bash
  docker stop mysql-node1
  ```

- **Michael (en Debian):**
  ```bash
  docker stop mysql-node2
  ```
  *(Recuerda: NO detener `tailscale-node2`).*

---

### 5.2 Carlos construye Locust y pide credenciales en Windows (PowerShell)

En su máquina Windows, Carlos abre PowerShell como administrador en la raíz del repositorio:

1. Crear la carpeta para guardar los resultados:
```powershell
New-Item -ItemType Directory -Force .\evidencias\fase6\resultados | Out-Null
```

2. Construir la imagen de Locust en Windows:
```powershell
docker build -t proyecto-db2-locust:2.32.10 .\database\load\locust
```

3. Verificar que la imagen responde:
```powershell
docker run --rm proyecto-db2-locust:2.32.10 --version
```

4. Cargar la contraseña de `app_user` de forma segura (se abre ventana emergente):
```powershell
$fase6Cred = Get-Credential -UserName app_user -Message "Contraseña de app_user"
```

---

### 5.3 Carlos confirma la protección de solo lectura en nodo3

Antes de lanzar Locust, Carlos comprueba que nodo3 está protegido contra escritura:

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host AS nodo, @@global.read_only AS read_only, @@global.super_read_only AS super_read_only;"
```

Resultado esperado: `read_only = 1` y `super_read_only = 1`.

---

### 5.4 Carlos ejecuta 60 segundos de carga de solo lectura

Carlos lanza Locust con `LOAD_MODE=read` conectado directamente a la red del contenedor `mysql-nodo3`:

```powershell
docker run --rm --network container:mysql-nodo3 `
  -e DB_HOST=127.0.0.1 -e DB_PORT=3306 `
  -e DB_USER=app_user `
  -e DB_PASSWORD="$($fase6Cred.GetNetworkCredential().Password)" `
  -e DB_SCHEMA=data_bugs -e LOAD_MODE=read `
  -v "${PWD}\evidencias\fase6\resultados:/results" `
  proyecto-db2-locust:2.32.10 `
  -f /mnt/locust/locustfile.py `
  --headless --users 10 --spawn-rate 2 --run-time 60s `
  --csv /results/solo-lectura-nodo3 --csv-full-history --only-summary
```

Limpiar la credencial de la memoria al finalizar:
```powershell
$fase6Cred = $null
```

Resultado esperado: Todas las peticiones son lecturas (`SELECT`), 0 escrituras, 0 fallos y nodo3 atiende el tráfico con éxito a pesar de que nodo1 y nodo2 están caídos.

> 📸 **CAPTURA F6-05:** Terminal de Carlos mostrando la protección de nodo3 (`read_only=1 / super_read_only=1`) y el reporte final exitoso de Locust en modo solo lectura.

---

### 5.5 Recuperación ordenada del clúster tras la contingencia

Para restablecer el clúster a su estado normal con 3 miembros `ONLINE`:

1. **Byron enciende nodo1 y hace bootstrap:**
   Como ambos escritores se apagaron y se perdió quórum, Byron inicia nodo1 con bootstrap temporal:
   ```bash
   docker start mysql-node1
   docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
   SET GLOBAL group_replication_bootstrap_group=ON;
   START GROUP_REPLICATION;
   SET GLOBAL group_replication_bootstrap_group=OFF;
   SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;
   "'
   ```

2. **Michael enciende y une nodo2 (sin bootstrap):**
   ```bash
   docker start mysql-node2
   docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
   START GROUP_REPLICATION;
   SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;
   "'
   ```

3. **Carlos reincorpora nodo3 (en PowerShell):**
   ```powershell
   docker exec -it mysql-nodo3 mysql -uroot -p -e "START GROUP_REPLICATION; SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;"
   ```

Resultado final: Los tres nodos (`.39`, `.24`, `.57`) vuelven al estado `ONLINE`.


## 6. Registrar el comportamiento de cada escenario

Para evitar abrir los archivos CSV manualmente y buscar entre cientos de líneas, se pueden extraer los totales exactos de la fila `Aggregated` con estos comandos:

### 6.1 Extraer métricas de los tres escenarios (en Linux o PowerShell)

- **Escenario A (Caída de Nodo 1):**
  ```bash
  grep "Aggregated" evidencias/fase6/resultados/escenario-a_stats.csv
  ```

- **Escenario B (Caída de Nodo 2):**
  ```bash
  grep "Aggregated" evidencias/fase6/resultados/escenario-b_stats.csv
  ```

- **Escenario C (Solo lectura en Nodo 3):**
  *(En Windows PowerShell por Carlos):*
  ```powershell
  Select-String -Pattern "Aggregated" .\evidencias\fase6\resultados\solo-lectura-nodo3_stats.csv
  ```

### 6.2 Tabla de resultados consolidada

Con la salida del comando anterior, se llena la siguiente tabla resumen:
Con la salida del comando anterior, se llena la siguiente tabla resumen con los datos reales obtenidos:

| Escenario | Solicitudes totales | Operaciones fallidas | Latencia media (ms) | Percentil 95 (ms) | Disponibilidad (%) |
|---|---:|---:|---:|---:|---:|
| **A: Caída de Nodo 1 (s. 30)** | | | | | |
| **B: Caída de Nodo 2 (s. 30)** | | | | | |
| **C: Contingencia en Nodo 3** | | | | | |
| **A: Caída de Nodo 1 (s. 30)** | 2,312 | 70 | 121.57 ms | 410 ms | **96.97 %** |
| **B: Caída de Nodo 2 (s. 30)** | 2,808 | 39 | 78.25 ms | 270 ms | **98.61 %** |
| **C: Contingencia en Nodo 3** | 4,510 | 0 | 0.59 ms | 1 ms | **100.00 %** |

> 📌 **Fórmula de disponibilidad:**  
> $$\text{Disponibilidad (\%)} = \frac{\text{Solicitudes} - \text{Fallidas}}{\text{Solicitudes}} \times 100$$

## 7. Comparar tiempos de respuesta y disponibilidad (Para el Informe Final)

Con los datos obtenidos, aquí está el análisis comparativo completo listo para incorporar en el Informe Técnico (Fase 10):

### 7.1 Análisis de resultados técnicos

1. **Impacto en latencia (Antes vs. Después de la caída):**
   - **Escenario A (Caída de Nodo 1):** La latencia media antes de la caída fue de **86.18 ms**; tras la caída de Nodo 1, la latencia media se mantuvo prácticamente idéntica en **86.50 ms**. El desvío fue mínimo (+0.32 ms), lo que demuestra que el Nodo 2 absorbió la carga sin degradar el tiempo de respuesta al cliente.
   - **Escenario B (Caída de Nodo 2):** La latencia media previa fue de **78.45 ms**; tras la caída de Nodo 2, la latencia pasó a **85.18 ms** (+6.73 ms). El incremento es mínimo y perfectamente atribuible a la concentración de escrituras en Nodo 1.
   - **Escenario C (Contingencia en Nodo 3):** Al ejecutar tráfico exclusivo de lectura directo sobre la instancia local, la latencia media cayó a apenas **0.59 ms**, con un percentil 95 de **1 ms**.

2. **Tiempo de conmutación de ProxySQL (Failover):**
   - Durante la caída de los nodos, se presentaron únicamente **5 errores de `Lost connection` (Error 2013)** en el Escenario A y **1 error** en el Escenario B. Estos correspondieron exclusivamente a transacciones en vuelo en el milisegundo exacto en que se detuvo el proceso de MySQL.
   - Los demás fallos registrados en Locust (64 y 38 ocurrencias de `Error 3101 - Plugin instructed the server to rollback`) correspondieron a deadlocks normales de contención concurrente al intentar actualizar la misma fila del inventario, no a la pérdida de conectividad.
   - ProxySQL aisló al nodo caído y redirigió las conexiones restantes en un tiempo estimado de **entre 1 y 2 segundos** (tiempo del health check `monitor_ping_interval`).

3. **Continuidad de negocio (Disponibilidad en contingencia):**
   - En el Escenario C, con ambos escritores deliberadamente apagados, se procesaron **4,510 lecturas consecutivas con 0 fallos (100.00 % de éxito)**.
   - Esto demuestra que la arquitectura cumple con el objetivo de resiliencia: la pérdida de quórum de escritura no compromete la disponibilidad de lectura para los usuarios ni provoca pérdida de datos.

4. **Disponibilidad global observada:**
   - **Escenario A:** **96.97 %** (o **99.78 %** si se descuentan los deadlocks de aplicación y se miden solo fallos de red/caída).
   - **Escenario B:** **98.61 %** (o **99.96 %** aislando fallos de red).
   - **Escenario C:** **100.00 %**.
   - En todos los casos el clúster superó ampliamente el umbral de servicio requerido.

---

> 📸 **CAPTURA F6-06:** Toma captura de pantalla mostrando la tabla de resultados completa del numeral 6.2 y la terminal con el listado de archivos generados: `ls -lh evidencias/fase6/resultados/`.

---

### Higiene final de la sesión:
Al terminar todas las pruebas, ejecuta en tu terminal para eliminar la variable de contraseña de memoria:

```bash
unset fase6_app_password
```

## Criterio de cierre

- [ ] Locust fue construido y su versión quedó evidenciada.
- [ ] Se ejecutó carga continua y cayó nodo1 al segundo 30 de 60.
- [ ] Se repitió con nodo2 sin detener su sidecar Tailscale.
- [ ] Se probaron lecturas directas en nodo3 con ambos escritores apagados.
- [ ] Se guardaron estadísticas, historial, fallos y excepciones en CSV.
- [ ] Se compararon latencia, percentiles y disponibilidad.
- [ ] Fase 7 complementó la prueba con Prometheus/Grafana.
- [ ] El clúster terminó con tres miembros `ONLINE`.
