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

No se usa `mysqlslap` porque la imagen `mysql:8.4` utilizada por el proyecto no
incluye ese ejecutable. Tampoco se usa k6 porque MySQL no es un protocolo
integrado en k6 y requeriría construir extensiones `xk6-sql` y su driver.

La imagen auxiliar de Locust:

- no modifica los tres MySQL;
- no modifica sus volúmenes;
- no instala paquetes en Linux o Windows;
- se conecta por ProxySQL en el puerto `6033`;
- combina 75 % de `SELECT` y 25 % de `UPDATE stock=stock` sin alterar datos.

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

Antes de generar carga se utiliza el semáforo de `avances/fase2.md`.

Resultado necesario:

- tres miembros `ONLINE`;
- nodo1 y nodo2 permiten escritura;
- nodo3 conserva `read_only=1` y `super_read_only=1`;
- `proxysql-db2` está activo.

No iniciar la prueba con un miembro `OFFLINE`, `RECOVERING` o `UNREACHABLE`.

### P.2 Construir Locust — ejecuta Byron desde la raíz

```bash
mkdir -p evidencias/fase6/resultados

docker build \
  -t proyecto-db2-locust:2.32.10 \
  database/load/locust

docker run --rm proyecto-db2-locust:2.32.10 --version
```

Sirve para: crear una imagen auxiliar reproducible con Locust y el controlador
PyMySQL.

Resultado esperado: la construcción termina sin errores y el último comando
muestra `locust 2.32.10`.

### P.3 Cargar la contraseña sin mostrarla — ejecuta Byron

```bash
read -s 'fase6_app_password?Contraseña de app_user: '
echo
```

Sirve para: conservar la contraseña solo en una variable temporal; no queda
escrita en el historial ni en las capturas.

Resultado esperado: no imprime la contraseña.

---

## 1. Generar carga controlada sobre nodo1 y nodo2

### Ejecuta: Byron

La prueba dura 60 segundos con 10 usuarios virtuales. Se deja trabajando en
segundo plano para provocar la falla mientras la misma ejecución continúa:

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
    --csv /results/escenario-a --csv-full-history --only-summary \
  | tee evidencias/fase6/resultados/escenario-a-consola.txt
) &
fase6_pid=$!
```

Sirve para: iniciar una sola carga continua a través de ProxySQL. Locust crea
los archivos `escenario-a_stats.csv`, `escenario-a_stats_history.csv`,
`escenario-a_failures.csv` y `escenario-a_exceptions.csv`.

Resultado esperado: el proceso queda activo y la terminal muestra un número
de trabajo/PID. No cerrar esa terminal.

> **CAPTURA F6-01:** inicio de Locust y tres nodos `ONLINE`.

---

## 2. Aproximadamente al 50 %, provocar la caída de nodo1

### Ejecuta: Byron en la misma terminal

```bash
sleep 30
date --iso-8601=seconds
docker stop mysql-node1
wait "$fase6_pid"
```

Sirve para: detener nodo1 a los 30 de 60 segundos. Con una tasa de carga
estable, ese instante representa aproximadamente el 50 % de las operaciones.
La prueba no se reinicia; continúa mediante nodo2.

Resultado esperado:

- `docker stop` devuelve `mysql-node1`;
- Locust completa los 60 segundos;
- el resumen muestra solicitudes, fallos, latencia media y percentiles.

Después se reutiliza la consulta de hostgroups de Fase 3, punto 4. Nodo1 `.39`
debe estar en HG40/`SHUNNED`, mientras nodo2 `.24` permanece escritor.

> **CAPTURA F6-02:** hora de caída, ProxySQL con nodo1 apartado y resumen de
> Locust.

---

## 3. Comprobar que las operaciones continuaron sobre nodo2

### Ejecuta: Byron

```bash
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_stats.csv
sed -n '1,12p' evidencias/fase6/resultados/escenario-a_failures.csv
```

Sirve para: leer el total real de operaciones, fallos y tiempos medidos. El
archivo de historial permite observar valores antes y después del segundo 30.

Resultado esperado: existen operaciones después de la caída. Puede haber
fallos breves mientras ProxySQL detecta el cambio; se registran, no se ocultan.

Luego Byron recupera nodo1 siguiendo Fase 3, puntos 7–8: inicia el contenedor,
ejecuta `START GROUP_REPLICATION` **sin bootstrap** y espera tres `ONLINE`.

> **CAPTURA F6-03:** nodo2 disponible, resultados CSV y clúster recuperado.

---

## 4. Repetir la carga provocando la caída de nodo2

No comenzar hasta confirmar nuevamente tres miembros `ONLINE`.

### 4.1 Byron inicia el escenario B

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

sleep 30
echo "MICHAEL: detener mysql-node2 ahora"
date --iso-8601=seconds
```

Sirve para: repetir exactamente la carga y señalar el instante del 50 %.

### 4.2 Michael detiene únicamente MySQL nodo2

```bash
docker stop mysql-node2
```

No debe detener `tailscale-node2`, porque se perdería también la ruta de red.

Resultado esperado: devuelve `mysql-node2` y nodo1 continúa como escritor.

### 4.3 Byron espera y consulta resultados

```bash
wait "$fase6_pid"
sed -n '1,12p' evidencias/fase6/resultados/escenario-b_stats.csv
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

```powershell
New-Item -ItemType Directory -Force .\evidencias\fase6\resultados | Out-Null
docker build -t proyecto-db2-locust:2.32.10 .\database\load\locust
docker run --rm proyecto-db2-locust:2.32.10 --version
```

Resultado esperado: muestra `locust 2.32.10`.

### 5.2 Carlos carga la contraseña de `app_user`

```powershell
$fase6Cred = Get-Credential -UserName app_user -Message "Contraseña de app_user"
```

Sirve para: pedir el secreto sin escribirlo en el comando.

### 5.3 Carlos ejecuta 60 segundos de lectura directa en nodo3

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
