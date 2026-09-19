# Fase 6 — Pruebas de carga

## Objetivo oficial

Validar el balanceo y la resiliencia bajo carga, provocar la caída de cada
escritor aproximadamente al 50 % de las operaciones y comprobar lectura en
nodo3 cuando ambos escritores estén apagados.

## Herramienta seleccionada

Se utilizará el script versionado
`database/tests/load_phase6.sh`, ejecutado dentro de la imagen `mysql:8.4`.
El script utiliza el cliente `mysql`, que sí está presente en esa imagen, y no
`mysqlslap`, que no viene incluido en la imagen utilizada por el proyecto.

No se instala nada en los sistemas operativos. La carga normal entra por
ProxySQL (`6033`) y el script:

- ejecuta exactamente 100 operaciones por lote;
- simula 10 clientes concurrentes;
- alterna `SELECT` y `UPDATE` sin cambio de valor;
- cuenta operaciones exitosas y fallidas;
- calcula duración, latencia promedio/mínima/máxima y disponibilidad.

### Por qué cumple el enunciado

El enunciado recomienda k6, JMeter, Locust **o una herramienta equivalente**.
El script es una herramienta equivalente y reproducible porque controla
cantidad, concurrencia, tipo de operación, resultados y tiempos sobre el
protocolo MySQL real.

Cada escenario contiene dos lotes iguales:

```text
100 operaciones antes de la falla
              ↓ 50 %
         caída del nodo
              ↓
100 operaciones después de la falla
```

Prometheus y Grafana, configurados en Fase 7, complementan esta carga con CPU,
memoria, disponibilidad, replicación y comportamiento durante la falla.

### Por qué no se utiliza `mysqlslap`

Aunque `mysqlslap` es una herramienta oficial de MySQL, la ejecución comprobó:

```text
/usr/local/bin/docker-entrypoint.sh: ... mysqlslap: not found
```

La imagen `mysql:8.4` de este proyecto contiene `mysql`, pero no ese binario.
No se modifica el sistema ni se instala un paquete solo para ocultar el error;
se utiliza el script verificable incluido en el repositorio.

## Responsables

| Tarea | Responsable inicial |
|---|---|
| Generar carga y observar ProxySQL | Byron |
| Detener/recuperar nodo2 | Michael |
| Operar nodo3, evidencias y tabla | Carlos |

---

## Preparación común

### Ejecuta: Byron desde la raíz del repositorio

```bash
mkdir -p evidencias/fase6/resultados
chmod +x database/tests/load_phase6.sh
sh -n database/tests/load_phase6.sh
docker run --rm mysql:8.4 mysql --version
```

Sirve para: preparar resultados, comprobar la sintaxis del generador y validar
que el cliente `mysql` existe en la imagen.

Resultado esperado:

- `sh -n` no imprime errores.
- `mysql --version` muestra MySQL 8.4.

Después confirmar mediante el semáforo de `avances/fase2.md`:

- tres miembros `ONLINE`;
- nodo3 con `read_only=1` y `super_read_only=1`;
- ProxySQL activo;
- las marcas temporales de Fase 5 ya fueron limpiadas.

Byron carga una sola vez la contraseña privada de `app_user`:

```bash
read -s 'fase6_app_password?Contraseña de app_user: '
echo
```

No se muestra ni se captura esta variable. Al terminar se ejecuta
`unset fase6_app_password`.

---

## 1. Generar carga controlada sobre nodo1 y nodo2

### Ejecuta: Byron

Con ambos escritores `ONLINE`, ejecutar el primer lote de 100 operaciones:

```bash
set -o pipefail

docker run --rm --network host --entrypoint sh \
  -e MYSQL_PWD="$fase6_app_password" \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_SCHEMA=data_bugs \
  -e LOAD_TOTAL=100 -e LOAD_CONCURRENCY=10 \
  -e LOAD_MODE=mixed -e LOAD_LABEL=escenario-a-antes \
  -v "$PWD/database/tests/load_phase6.sh:/load_phase6.sh:ro" \
  mysql:8.4 /load_phase6.sh \
  | tee evidencias/fase6/resultados/escenario-a-antes.txt
```

Sirve para: establecer la línea base con nodo1 y nodo2 disponibles.

Resultado esperado:

```text
operaciones_intentadas=100
operaciones_exitosas=100
operaciones_fallidas=0
disponibilidad_porcentaje=100.00
```

También aparecen duración y latencias. Si hay fallos, detener la prueba y
guardar los errores; todavía no provocar la caída.

> **CAPTURA F6-01:** resumen completo y tres nodos `ONLINE`.

---

## 2. Al 50 %, provocar la caída de nodo1

La finalización del primer lote representa 100 de 200 operaciones, es decir,
el 50 % del escenario.

### Ejecuta: Byron

```bash
date --iso-8601=seconds
docker stop mysql-node1
```

Sirve para: retirar el primer escritor conservando ProxySQL activo.

Resultado esperado: `mysql-node1` detenido. Reutilizar la consulta de
hostgroups de Fase 3, punto 4; nodo1 debe pasar a HG40/`SHUNNED` y nodo2 debe
permanecer escritor.

> **CAPTURA F6-02:** hora, nodo1 detenido y detección de ProxySQL.

---

## 3. Continuar las operaciones restantes sobre nodo2

### Ejecuta: Byron

```bash
docker run --rm --network host --entrypoint sh \
  -e MYSQL_PWD="$fase6_app_password" \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_SCHEMA=data_bugs \
  -e LOAD_TOTAL=100 -e LOAD_CONCURRENCY=10 \
  -e LOAD_MODE=mixed -e LOAD_LABEL=escenario-a-despues \
  -v "$PWD/database/tests/load_phase6.sh:/load_phase6.sh:ro" \
  mysql:8.4 /load_phase6.sh \
  | tee evidencias/fase6/resultados/escenario-a-despues.txt
```

Sirve para: ejecutar las 100 operaciones restantes mediante nodo2.

Resultado esperado: 100 intentadas, 100 exitosas y cero fallidas. Si ProxySQL
aún está detectando la caída, puede aparecer alguna operación fallida; se
registra como resultado real y no se oculta.

Después recuperar nodo1 siguiendo Fase 3, puntos 7–8: encenderlo, ejecutar
`START GROUP_REPLICATION` sin bootstrap y esperar tres `ONLINE`/GTID iguales.

> **CAPTURA F6-03:** resumen posterior a la falla y nodo2 disponible.

---

## 4. Repetir provocando la caída de nodo2

No comenzar hasta confirmar otra vez tres miembros `ONLINE`.

### 4.1 Byron ejecuta las primeras 100 operaciones

```bash
docker run --rm --network host --entrypoint sh \
  -e MYSQL_PWD="$fase6_app_password" \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_SCHEMA=data_bugs \
  -e LOAD_TOTAL=100 -e LOAD_CONCURRENCY=10 \
  -e LOAD_MODE=mixed -e LOAD_LABEL=escenario-b-antes \
  -v "$PWD/database/tests/load_phase6.sh:/load_phase6.sh:ro" \
  mysql:8.4 /load_phase6.sh \
  | tee evidencias/fase6/resultados/escenario-b-antes.txt
```

Esperado: 100 exitosas, cero fallidas.

### 4.2 Michael detiene únicamente MySQL nodo2

```bash
date --iso-8601=seconds
docker stop mysql-node2
```

Sirve para: retirar el segundo escritor sin apagar `tailscale-node2`.

### 4.3 Byron ejecuta las 100 operaciones restantes

```bash
docker run --rm --network host --entrypoint sh \
  -e MYSQL_PWD="$fase6_app_password" \
  -e DB_HOST=127.0.0.1 -e DB_PORT=6033 \
  -e DB_USER=app_user -e DB_SCHEMA=data_bugs \
  -e LOAD_TOTAL=100 -e LOAD_CONCURRENCY=10 \
  -e LOAD_MODE=mixed -e LOAD_LABEL=escenario-b-despues \
  -v "$PWD/database/tests/load_phase6.sh:/load_phase6.sh:ro" \
  mysql:8.4 /load_phase6.sh \
  | tee evidencias/fase6/resultados/escenario-b-despues.txt
```

Resultado esperado: nodo1 `.39` atiende la carga restante. Después Michael
recupera nodo2 siguiendo Fase 4, puntos 6–7: iniciar `mysql-node2`, ejecutar
`START GROUP_REPLICATION` sin bootstrap y esperar `ONLINE`/GTID iguales.

> **CAPTURA F6-04:** nodo2 caído, nodo1 escritor y resumen de carga.

---

## 5. Apagar nodo1/nodo2 y generar carga de lectura en nodo3

Reutilizar Fase 5, puntos 1–6: verificar sincronización, detener nodo1, detener
nodo2, demostrar escrituras bloqueadas y conservar nodo3 `1/1`.

### Ejecuta: Carlos desde la raíz de su repositorio

Primero copia el script dentro del contenedor:

```powershell
docker cp .\database\tests\load_phase6.sh mysql-nodo3:/tmp/load_phase6.sh
```

Después genera 100 operaciones exclusivamente de lectura:

```powershell
docker exec -e DB_HOST=127.0.0.1 -e DB_PORT=3306 -e DB_USER=root -e DB_SCHEMA=data_bugs -e LOAD_TOTAL=100 -e LOAD_CONCURRENCY=10 -e LOAD_MODE=read -e LOAD_LABEL=solo-lectura-nodo3 mysql-nodo3 sh /tmp/load_phase6.sh | Tee-Object -FilePath .\evidencias\fase6\resultados\solo-lectura-nodo3.txt
```

El script usa `MYSQL_ROOT_PASSWORD` ya presente dentro de nodo3; Carlos no
escribe la contraseña.

Resultado esperado: 100 lecturas exitosas, cero fallidas y nodo3 continúa
`read_only=1` / `super_read_only=1`.

Después recuperar el clúster siguiendo Fase 5, puntos 7–10.

> **CAPTURA F6-05:** resumen de lectura y nodo3 protegido `1/1`.

---

## 6. Registrar el comportamiento de cada escenario

### Ejecuta: Carlos con los archivos guardados

| Escenario | Total | Antes de falla | Después de falla | Fallidas | Latencia promedio | Mín/máx | Disponibilidad |
|---|---:|---:|---:|---:|---:|---:|---:|
| Normal / nodo1 cae | 200 | | | | | | |
| Normal / nodo2 cae | 200 | | | | | | |
| Solo lectura nodo3 | 100 | 0 | | | | | |

Los valores salen directamente de los archivos de `resultados/`.

Disponibilidad:

```text
operaciones exitosas / operaciones intentadas × 100
```

Los errores se copian literalmente; no se cuentan como éxito.

---

## 7. Comparar tiempos y disponibilidad

El equipo responde en el informe:

- ¿Cambió la latencia después de cada caída?
- ¿Qué nodo atendió las operaciones restantes?
- ¿Cuántas operaciones fallaron durante la detección del proxy?
- ¿Fue mayor la latencia a través de Tailscale/DERP?
- ¿Continuaron las lecturas con solo nodo3?
- ¿Cuál fue la disponibilidad porcentual de cada escenario?

> **CAPTURA F6-06:** tabla final y comparación de escenarios.

Al terminar:

```bash
unset fase6_app_password
```

## Criterio de cierre

- [ ] Se midieron operaciones intentadas, exitosas, fallidas y latencias.
- [ ] Se provocó la caída de nodo1 al completar 100 de 200 operaciones.
- [ ] Se repitió la prueba con nodo2.
- [ ] Nodo3 atendió 100 lecturas directas y permaneció `1/1`.
- [ ] Fase 7 complementó la prueba con Prometheus/Grafana.
- [ ] El clúster terminó con tres miembros `ONLINE`.
- [ ] Resultados y capturas quedaron asociados a la bitácora.
