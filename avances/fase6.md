# Fase 6 — Pruebas de carga

## Objetivo oficial

Validar el balanceo y la resiliencia bajo carga, provocar la caída de cada
escritor aproximadamente al 50 % de las operaciones y comprobar lectura en
nodo3 cuando ambos escritores estén apagados.

## Herramienta seleccionada

Se utilizará `mysqlslap`, cliente oficial incluido en la imagen `mysql:8.4`.
No se instala nada en los sistemas operativos. La carga entra por ProxySQL
(`6033`) y combina `SELECT` con un `UPDATE` sin cambio de valor, evitando
alterar el dataset.

Responsables: Byron genera carga y observa ProxySQL; Michael controla nodo2;
Carlos controla nodo3, evidencias y tabla de resultados.

## Preparación común

Ejecuta Byron desde la raíz:

```bash
mkdir -p evidencias/fase6/resultados
docker run --rm mysql:8.4 mysqlslap --version
```

Esperado: versión MySQL 8.4. Después verifica tres nodos `ONLINE`, nodo3 `1/1`
y ProxySQL saludable usando el semáforo de `avances/fase2.md`.

Byron carga la contraseña una vez en la terminal:

```bash
read -s 'fase6_app_password?Contraseña de app_user: '
echo
```

No se captura ni comparte esta variable. Al terminar toda la fase se ejecuta
`unset fase6_app_password`.

---

## 1. Generar carga controlada sobre nodo1 y nodo2

Con ambos escritores `ONLINE`, Byron ejecuta la primera mitad (100 operaciones):

```bash
set -o pipefail
docker run --rm --network host \
  -e MYSQL_PWD="$fase6_app_password" mysql:8.4 \
  mysqlslap -h127.0.0.1 -P6033 -uapp_user \
  --create-schema=data_bugs --no-drop \
  --concurrency=10 --iterations=1 --number-of-queries=100 \
  --delimiter=';' \
  --query="SELECT nombre,stock FROM producto WHERE producto_id=1;UPDATE producto SET stock=stock WHERE producto_id=1" \
  | tee evidencias/fase6/resultados/escenario-a-antes.txt
```

Sirve para: establecer latencia/tiempo base con nodo1 y nodo2 disponibles.

Esperado: `Average number of seconds`, mínimo, máximo y clientes simulados, sin
errores. ProxySQL puede repartir conexiones entre los escritores/lectores.

> **CAPTURA F6-01:** resumen de la primera mitad y tres nodos `ONLINE`.

---

## 2. Al 50 %, provocar la caída de nodo1

La prueba controlada se divide en dos lotes iguales; la frontera entre ambos
representa aproximadamente el 50 %.

Ejecuta Byron:

```bash
date --iso-8601=seconds
docker stop mysql-node1
```

Esperado: `mysql-node1` detenido y `proxysql-db2` activo. Se reutiliza el
procedimiento de observación de hostgroups de `avances/fase3.md`, punto 4.

> **CAPTURA F6-02:** nodo1 en HG40/SHUNNED y nodo2 escritor.

---

## 3. Verificar que las operaciones restantes continúen en nodo2

Byron ejecuta la segunda mitad con el mismo tamaño:

```bash
docker run --rm --network host \
  -e MYSQL_PWD="$fase6_app_password" mysql:8.4 \
  mysqlslap -h127.0.0.1 -P6033 -uapp_user \
  --create-schema=data_bugs --no-drop \
  --concurrency=10 --iterations=1 --number-of-queries=100 \
  --delimiter=';' \
  --query="SELECT nombre,stock FROM producto WHERE producto_id=1;UPDATE producto SET stock=stock WHERE producto_id=1" \
  | tee evidencias/fase6/resultados/escenario-a-despues.txt
```

Esperado: el lote termina mediante nodo2 `.24`. Se registran operaciones
exitosas/fallidas y latencia. Después se recupera nodo1 siguiendo Fase 3,
puntos 7–8, hasta volver a tres `ONLINE`.

> **CAPTURA F6-03:** resumen posterior a la falla y nodo2 disponible.

---

## 4. Repetir provocando la caída de nodo2

Primero confirmar otra vez tres `ONLINE`. Byron ejecuta el lote previo:

```bash
docker run --rm --network host \
  -e MYSQL_PWD="$fase6_app_password" mysql:8.4 \
  mysqlslap -h127.0.0.1 -P6033 -uapp_user \
  --create-schema=data_bugs --no-drop \
  --concurrency=10 --iterations=1 --number-of-queries=100 \
  --delimiter=';' \
  --query="SELECT nombre,stock FROM producto WHERE producto_id=1;UPDATE producto SET stock=stock WHERE producto_id=1" \
  | tee evidencias/fase6/resultados/escenario-b-antes.txt
```

Esperado: 100 operaciones completadas antes de la falla, sin errores.

Michael registra la hora y detiene únicamente MySQL:

```bash
date --iso-8601=seconds
docker stop mysql-node2
```

Byron repite 100 operaciones y guarda:

```bash
docker run --rm --network host \
  -e MYSQL_PWD="$fase6_app_password" mysql:8.4 \
  mysqlslap -h127.0.0.1 -P6033 -uapp_user \
  --create-schema=data_bugs --no-drop \
  --concurrency=10 --iterations=1 --number-of-queries=100 \
  --delimiter=';' \
  --query="SELECT nombre,stock FROM producto WHERE producto_id=1;UPDATE producto SET stock=stock WHERE producto_id=1" \
  | tee evidencias/fase6/resultados/escenario-b-despues.txt
```

Esperado: segundo lote atendido por nodo1 `.39`. Después Michael recupera
nodo2 siguiendo Fase 4, puntos 6–7: iniciar `mysql-node2`, esperar que MySQL
responda, ejecutar `START GROUP_REPLICATION` sin bootstrap y comprobar
`ONLINE`/GTID iguales.

> **CAPTURA F6-04:** nodo2 caído, nodo1 escritor y resumen de carga.

---

## 5. Apagar nodo1/nodo2 y generar carga de lectura en nodo3

Reutilizar Fase 5, puntos 1–6: verificar sincronización, detener nodo1, detener
nodo2, demostrar escrituras bloqueadas y conservar nodo3 `1/1`.

Carlos ejecuta dentro del contenedor una carga exclusivamente de lectura:

```powershell
docker exec mysql-nodo3 sh -c 'mysqlslap -h127.0.0.1 -P3306 -uroot -p"$MYSQL_ROOT_PASSWORD" --create-schema=data_bugs --no-drop --concurrency=10 --iterations=1 --number-of-queries=100 --query="SELECT nombre,stock FROM producto ORDER BY producto_id"'
```

Esperado: 100 consultas de lectura atendidas; ninguna escritura habilitada.
Después se recupera el clúster siguiendo Fase 5, puntos 7–10.

> **CAPTURA F6-05:** resumen de lectura y nodo3 `read_only=1`.

---

## 6. Registrar el comportamiento de cada escenario

Carlos completa una fila por lote:

| Escenario | Total | Antes de falla | Después de falla | Fallidas | Tiempo promedio | Latencia mín/máx | Disponibilidad |
|---|---:|---:|---:|---:|---:|---:|---:|
| Normal / nodo1 cae | 200 | 100 | 100 | | | | |
| Normal / nodo2 cae | 200 | 100 | 100 | | | | |
| Solo lectura nodo3 | 100 | 0 | 100 lecturas | | | | |

Disponibilidad:

```text
operaciones exitosas / operaciones intentadas × 100
```

Los errores se copian literalmente; no se ocultan ni se cuentan como éxito.

---

## 7. Comparar tiempos y disponibilidad

El equipo responde en el informe:

- ¿Cambió el promedio después de cada caída?
- ¿Qué nodo atendió las operaciones restantes?
- ¿Cuántas operaciones fallaron durante la detección del proxy?
- ¿Fue mayor la latencia a través de DERP/Tailscale?
- ¿Continuaron las lecturas con solo nodo3?
- ¿Cuál fue la disponibilidad porcentual de cada escenario?

> **CAPTURA F6-06:** tabla final y comparación de los tres escenarios.

Al terminar:

```bash
unset fase6_app_password
```

## Criterio de cierre

- [ ] Se midieron totales, éxitos, fallos y tiempos.
- [ ] Se provocó la caída de nodo1 aproximadamente al 50 %.
- [ ] Se repitió con nodo2.
- [ ] Nodo3 atendió carga directa únicamente de lectura.
- [ ] El clúster terminó restaurado con tres `ONLINE`.
- [ ] Resultados y capturas quedaron asociados a la bitácora.
