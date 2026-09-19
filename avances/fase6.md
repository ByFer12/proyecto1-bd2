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

### Ejecuta: Byron

Para mayor claridad y para tomar las capturas con calma en el momento exacto, **se recomienda usar dos terminales (o dos pestañas)**:

---

### 🟢 PASO 1 — En la Terminal 1: Iniciar la carga de Locust

1. Confirmar que los tres nodos están listos:
```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

2. Lanzar la prueba de carga de 60 segundos:
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

> 📸 **CAPTURA F6-01:** En cuanto comience a imprimir `Starting Locust... Ramping to 10 users...`, toma captura de la pantalla mostrando el comando ejecutado, los tres nodos `ONLINE` y el arranque de Locust.

---

### 🟡 PASO 2 — En la Terminal 2: Provocar la caída exacta al segundo 30 (50 % de la prueba)

En cuanto veas que la Terminal 1 empezó a correr, ve a la **Terminal 2** y ejecuta este comando con `sleep 30` (espera exactamente 30 segundos, imprime la hora y detiene el contenedor):

```bash
sleep 30 && date --iso-8601=seconds && docker stop mysql-node1
```

Inmediatamente verifica en ProxySQL que nodo1 pasó a estar apartado:
```bash
docker exec proxysql-db2 mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "
SELECT hostgroup, hostname, port, status FROM runtime_mysql_servers;
"
```

Regresa a la **Terminal 1** y espera a que Locust termine sus 60 segundos y muestre el reporte final.

> 📸 **CAPTURA F6-02:** Toma captura mostrando la hora de caída en la Terminal 2 con `docker stop mysql-node1` (o ProxySQL con nodo1 apartado) y la tabla de resumen final de Locust en la Terminal 1.

---

## 2. Comprobar resultados y recuperar nodo1

### Ejecuta: Byron en la Terminal 1

1. Leer estadísticas y fallos registrados en los archivos CSV:

Ver métricas generales y percentiles:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_stats.csv
```

Ver fallos transitorios durante la conmutación:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_failures.csv
```

2. Recuperar el Nodo 1 (encender y reincorporar al grupo sin bootstrap):
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

Resultado esperado: Existen operaciones procesadas tras la caída en nodo2 y el clúster vuelve a tener los tres nodos `ONLINE`.

> 📸 **CAPTURA F6-03:** Salida de los CSV demostrando continuidad de operaciones y la consulta final con los tres nodos nuevamente `ONLINE`.


---

## 4. Repetir la carga provocando la caída de nodo2

No comenzar hasta confirmar nuevamente tres miembros `ONLINE`.

### 4.1 Byron inicia el escenario B

Iniciar la carga en segundo plano:
```bash
(
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
) &
fase6_pid=$!
```

Esperar 30 segundos (50 % de la prueba):
```bash
sleep 30
```

Avisar a Michael para detener nodo2:
```bash
echo "MICHAEL: detener mysql-node2 ahora"
```

Registrar la marca de tiempo de la caída:
```bash
date --iso-8601=seconds
```

Sirve para: repetir exactamente la carga y señalar el instante del 50 %.

### 4.2 Michael detiene únicamente MySQL nodo2

Detener MySQL en nodo2:
```bash
docker stop mysql-node2
```

No debe detener `tailscale-node2`, porque se perdería también la ruta de red.

Resultado esperado: devuelve `mysql-node2` y nodo1 continúa como escritor.

### 4.3 Byron espera y consulta resultados

Esperar que termine el proceso de Locust:
```bash
wait "$fase6_pid"
```

Ver estadísticas generales del escenario B:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-b_stats.csv
```

Ver registro de fallos del escenario B:
```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-b_failures.csv
```

Resultado esperado: Locust completa la prueba y ProxySQL dirige las
operaciones restantes a nodo1. Los fallos transitorios, si existen, quedan en
el CSV.

Michael recupera nodo2 siguiendo Fase 4, puntos 6–7: inicia `mysql-node2`,
ejecuta `START GROUP_REPLICATION` sin bootstrap y espera `ONLINE`.

> **CAPTURA F6-04:** nodo2 detenido, nodo1 escritor, resumen y recuperación.

---

## 5. Apagar nodo1/nodo2 y generar solo lecturas en nodo3

Primero se reutiliza Fase 5, puntos 1–6: confirmar sincronización, detener
nodo1 y nodo2, demostrar que no hay escritura y mantener nodo3 protegido `1/1`.

### 5.1 Carlos construye Locust desde la raíz de su copia

Crear carpeta de resultados en Windows:
```powershell
New-Item -ItemType Directory -Force .\evidencias\fase6\resultados | Out-Null
```

Construir la imagen de Locust:
```powershell
docker build -t proyecto-db2-locust:2.32.10 .\database\load\locust
```

Verificar la versión instalada:
```powershell
docker run --rm proyecto-db2-locust:2.32.10 --version
```

Resultado esperado: muestra `locust 2.32.10`.

### 5.2 Carlos carga la contraseña de `app_user`

Pedir credencial de forma segura:
```powershell
$fase6Cred = Get-Credential -UserName app_user -Message "Contraseña de app_user"
```

Sirve para: pedir el secreto sin escribirlo en el comando.

### 5.3 Carlos ejecuta 60 segundos de lectura directa en nodo3

Ejecutar carga de solo lectura contra nodo3:
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

Limpiar la variable de credencial de memoria:
```powershell
$fase6Cred = $null
```

Sirve para: demostrar disponibilidad de lectura directa cuando no existe
quórum de escritura. `LOAD_MODE=read` impide que Locust ejecute `UPDATE`.

Resultado esperado: lecturas exitosas, cero escrituras y nodo3 continúa con
`read_only=1`, `super_read_only=1`.

Después se recupera el clúster siguiendo Fase 5, puntos 7–10.

> **CAPTURA F6-05:** resumen de Locust y nodo3 protegido `1/1`.

---

## 6. Registrar el comportamiento de cada escenario

### Ejecuta: Carlos

Completar con los CSV generados por Locust:

| Escenario | Solicitudes | Fallidas | Latencia media | p95 | Disponibilidad |
|---|---:|---:|---:|---:|---:|
| Nodo1 cae al segundo 30 | | | | | |
| Nodo2 cae al segundo 30 | | | | | |
| Solo lectura en nodo3 | | | | | |

La fila `Aggregated` de cada archivo `_stats.csv` contiene el total. La
disponibilidad se calcula así:

```text
(solicitudes - fallidas) / solicitudes × 100
```

La serie `_stats_history.csv` permite comparar la primera mitad con la segunda.

---

## 7. Comparar tiempos y disponibilidad

El equipo responde en el informe:

- ¿Cuánto cambió la latencia tras cada caída?
- ¿Cuántas operaciones fallaron durante la detección de ProxySQL?
- ¿Qué escritor atendió la segunda mitad?
- ¿Continuaron las lecturas con solo nodo3?
- ¿Qué disponibilidad tuvo cada escenario?
- ¿Qué muestran Prometheus y Grafana durante los mismos instantes?

> **CAPTURA F6-06:** tabla final, CSV y paneles de monitoreo de Fase 7.

Al terminar, Byron elimina la variable temporal:

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
