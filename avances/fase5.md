# Fase 5 — Fallo múltiple

## Objetivo oficial

Validar el funcionamiento de emergencia cuando nodo1 y nodo2 dejan de estar
disponibles. La arquitectura debe bloquear las escrituras, conservar consultas
de lectura en nodo3 y recuperar gradualmente el servicio hasta volver a tener
los tres nodos sincronizados.

Esta es la prueba más delicada. Nadie avanza al siguiente numeral sin que los
tres integrantes confirmen el resultado actual en el chat del grupo.

## Responsables iniciales

| Función | Responsable |
|---|---|
| Detener/recuperar nodo1 y coordinar ProxySQL | Byron |
| Detener/recuperar nodo2 y medir T0/T1 | Michael |
| Operar nodo3, controlar lectura y guardar evidencias | Carlos |

Los responsables pueden rotarse para explicar los comandos, pero solo el dueño
de cada computadora ejecuta las operaciones Docker locales.

## Reglas de seguridad

- Se detienen únicamente `mysql-node1` y `mysql-node2`.
- No se apaga la computadora de Byron porque allí vive ProxySQL.
- No se detiene `tailscale-node2` en la prueba principal.
- No ejecutar `docker compose down -v`, borrar volúmenes ni borrar `data/*`.
- No hacer bootstrap mientras algún grupo operativo conserve quórum.
- Nodo3 permanece con `super_read_only=ON` durante toda la contingencia.
- No realizar escrituras reales entre los pasos 3 y 8.

---

## 1. Verificar que los tres nodos estén funcionando y sincronizados

### 1.1 Ejecuta Byron — membresía y GTID de nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
SELECT @@global.gtid_executed;
"'
```

### 1.2 Ejecuta Michael — GTID de nodo2

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.gtid_executed;
"'
```

### 1.3 Ejecuta Carlos — GTID y protección de nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@global.gtid_executed; SELECT @@report_host AS nodo,@@global.read_only AS read_only,@@global.super_read_only AS super_read_only;"
```

Sirve para: establecer un punto de retorno verificable antes del fallo
múltiple.

### Resultado esperado

- Tres miembros `ONLINE / PRIMARY`.
- Mismo conjunto `gtid_executed` en los tres nodos.
- Nodo3 `.57` con `read_only=1` y `super_read_only=1`.
- ProxySQL saludable.

Si los GTID difieren, esperar y volver a consultar. No se inicia la falla hasta
que coincidan.

### 1.4 Crear una marca previa de disponibilidad

Ejecuta Byron mediante ProxySQL:

```bash
read -s 'fase5_app_password?Contraseña de app_user: '
echo

docker exec -e MYSQL_PWD="$fase5_app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 5 antes','fase5.antes@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

SELECT correo,nombre
FROM cliente
WHERE correo='fase5.antes@example.com';
"

unset fase5_app_password
```

Sirve para: crear un dato conocido que debe permanecer legible durante la
contingencia y después de recuperar todos los nodos.

> **CAPTURA F5-01:** tres `ONLINE`, GTID iguales, nodo3 `1/1` y marca previa.

---

## 2. Apagar el Nodo 1

### Ejecuta: Byron

```bash
date --iso-8601=seconds
docker stop mysql-node1

docker ps --format 'table {{.Names}}\t{{.Status}}' \
  | grep -E 'mysql-node1|proxysql-db2' || true
```

Sirve para: retirar el primer escritor y comprobar que ProxySQL continúa
activo en la computadora de Byron.

### Resultado esperado

- `docker stop` responde `mysql-node1`.
- `mysql-node1` deja de aparecer activo.
- `proxysql-db2` continúa activo.
- Nodo2 y nodo3 todavía conservan mayoría de dos miembros.

> **CAPTURA F5-02:** nodo1 detenido y ProxySQL activo.

---

## 3. Apagar el Nodo 2

### Ejecuta: Michael

```bash
date --iso-8601=seconds
date +%s > /tmp/fase5-t0
docker stop mysql-node2

docker ps --format 'table {{.Names}}\t{{.Status}}' \
  | grep -E 'mysql-node2|tailscale-node2' || true
```

Sirve para: provocar el fallo múltiple y registrar T0. El sidecar Tailscale
permanece activo, pero MySQL nodo2 deja de estar disponible.

### Resultado esperado

- `mysql-node2` queda detenido.
- `tailscale-node2` continúa activo.
- Nodo3 queda como único MySQL encendido y pierde quórum.

> **CAPTURA F5-03:** hora T0, ambos MySQL principales detenidos y sidecar
> activo.

---

## 4. Verificar que las operaciones de escritura ya no estén disponibles

Se realizan dos pruebas negativas. El error es el resultado correcto.

### 4.1 Carlos prueba escritura directa en nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "INSERT INTO cliente(nombre,correo) VALUES ('No debe entrar','fase5.noescribir@example.com');"
```

Resultado esperado: `ERROR 1290` por `super-read-only` o rechazo equivalente.

### 4.2 Carlos prueba escritura mediante ProxySQL

```powershell
docker exec -it mysql-nodo3 mysql -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "INSERT INTO cliente(nombre,correo) VALUES ('No debe entrar por proxy','fase5.noescribir.proxy@example.com');"
```

Resultado esperado: ProxySQL rechaza la operación porque no existe un escritor
saludable. Puede mostrar que no hay backend disponible, timeout controlado o
un error de conexión; no debe insertar la fila.

### 4.3 Carlos confirma que ninguna escritura entró

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT COUNT(*) AS escrituras_indebidas FROM cliente WHERE correo IN ('fase5.noescribir@example.com','fase5.noescribir.proxy@example.com');"
```

Resultado obligatorio:

```text
escrituras_indebidas  0
```

Sirve para: demostrar que la arquitectura prefiere bloquear escrituras antes
que aceptar datos sin quórum y arriesgar split-brain.

> **CAPTURA F5-04:** ambos rechazos y conteo final igual a cero.

---

## 5. Ejecutar consultas SELECT utilizando el Nodo 3

### Ejecuta: Carlos directamente en nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT correo,nombre FROM cliente WHERE correo='fase5.antes@example.com'; SELECT COUNT(*) AS clientes FROM cliente; SELECT nombre,stock FROM producto WHERE nombre='Adaptador USB-C';"
```

Sirve para: comprobar que la pérdida de los escritores no elimina los datos y
que nodo3 todavía atiende consultas de lectura directa.

### Resultado esperado

- Aparece `fase5.antes@example.com`.
- El conteo de clientes y el stock coinciden con el cierre de la Fase 4.
- Los `SELECT` terminan sin error.

> **CAPTURA F5-05:** marca previa, conteo y producto leídos desde nodo3.

---

## 6. Comprobar que la información siga disponible en modo de solo lectura

### Ejecuta: Carlos

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host AS nodo,@@global.read_only AS read_only,@@global.super_read_only AS super_read_only,@@global.gtid_executed AS gtid_executed; SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE FROM performance_schema.replication_group_members;"
```

Sirve para: relacionar la disponibilidad de los datos con el estado de
contingencia y demostrar que nodo3 no fue promovido inseguramente a escritor.

### Resultado esperado

- Nodo `.57`.
- `read_only=1` y `super_read_only=1`.
- GTID conservado.
- La vista puede mostrar nodo3 aislado y los otros miembros `UNREACHABLE`, o
  nodo3 puede pasar a `ERROR/OFFLINE` por pérdida de mayoría. Ambas situaciones
  son compatibles con la contingencia siempre que los `SELECT` directos sigan
  disponibles y las escrituras estén bloqueadas.

> **CAPTURA F5-06:** datos disponibles, flags `1/1`, GTID y membresía observada.

---

## 7. Encender nuevamente el Nodo 1

### Ejecuta: Byron

```bash
docker start mysql-node1

docker exec mysql-node1 sh -c '
intento=1
while [ "$intento" -le 30 ]; do
  if mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; then
    exit 0
  fi
  intento=$((intento + 1))
  sleep 2
done
exit 1
'

docker ps --filter name=mysql-node1 \
  --format 'table {{.Names}}\t{{.Status}}'
```

Sirve para: encender el primer servidor que se utilizará para recuperar la
capacidad de escritura. Todavía no se hace bootstrap ni JOIN en este punto.

### Resultado esperado

- `mysql-node1` activo o saludable.
- MySQL acepta conexiones.
- Group Replication de nodo1 continúa `OFFLINE`, lo cual es normal.

> **CAPTURA F5-07:** nodo1 encendido y MySQL respondiendo.

---

## 8. Verificar la recuperación del servicio de escritura

Después del fallo múltiple, nodo3 puede conservar una vista minoritaria sin
quórum. Para evitar dos grupos, se comparan GTID y se forma una sola vista.

### 8.1 Byron consulta GTID de nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "
SELECT @@global.gtid_executed;
"'
```

### 8.2 Carlos consulta GTID y estado de nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -N -e "SELECT @@global.gtid_executed; SELECT MEMBER_HOST,MEMBER_STATE FROM performance_schema.replication_group_members;"
```

Los GTID pueden ser idénticos o nodo3 puede contener eventos adicionales de
cambio de vista aunque no se aceptaran escrituras de aplicación. Si no son
idénticos, se comprueba inclusión y no se decide por la longitud del texto.

En nodo1 se abre MySQL y se sustituye el marcador por el GTID completo de
nodo3:

```bash
docker exec -it mysql-node1 mysql -uroot -p
```

```sql
SELECT GTID_SUBSET('GTID_COMPLETO_NODO3', @@global.gtid_executed)
       AS nodo3_esta_en_nodo1;
```

Carlos hace la comparación inversa dentro de MySQL nodo3:

```sql
SELECT GTID_SUBSET('GTID_COMPLETO_NODO1', @@global.gtid_executed)
       AS nodo1_esta_en_nodo3;
```

Interpretación:

| `nodo3_esta_en_nodo1` | `nodo1_esta_en_nodo3` | Candidato de bootstrap |
|---:|---:|---|
| 1 | 1 | Son equivalentes; usar nodo1 por convenio. |
| 1 | 0 | Nodo1 contiene a nodo3; usar nodo1. |
| 0 | 1 | Nodo3 contiene a nodo1; usar nodo3. |
| 0 | 0 | Hay divergencia; detener la fase y no hacer bootstrap. |

### 8.3 Carlos detiene la vista minoritaria de nodo3

Carlos abre MySQL:

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p
```

Dentro de `mysql>`:

```sql
STOP GROUP_REPLICATION;
SET GLOBAL super_read_only=ON;

SELECT MEMBER_HOST,MEMBER_STATE
FROM performance_schema.replication_group_members;
```

Si `STOP GROUP_REPLICATION` indica que el plugin ya estaba detenido, no es un
problema: se ejecuta `SET GLOBAL super_read_only=ON` y se confirma `OFFLINE`.

Resultado esperado: nodo3 queda `OFFLINE`. En este momento nodo1 y nodo3 están
fuera del grupo y nodo2 sigue detenido; por lo tanto no queda ningún grupo
activo.

### 8.4 Realizar un único bootstrap en el candidato más completo

Se ejecuta **solo una** de las dos rutas siguientes.

#### Ruta A — GTID equivalentes o nodo1 contiene a nodo3

Este bloque se ejecuta solamente después de confirmar GTID compatibles y
nodo3 `OFFLINE`:

```bash
docker exec mysql-node1 sh -c '
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=ON;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"
fase5_bootstrap_rc=$?
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=OFF;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"
exit "$fase5_bootstrap_rc"
'
```

Resultado esperado: `bootstrap=0` y nodo1 `.39 ONLINE`.

#### Ruta B — Nodo3 contiene a nodo1

Carlos ejecuta dentro de `mysql>` y comprueba cada instrucción:

```sql
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;

SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

Incluso si `START` muestra un error, Carlos ejecuta inmediatamente
`SET GLOBAL group_replication_bootstrap_group=OFF`. Resultado esperado:
`bootstrap=0` y nodo3 `.57 ONLINE`, todavía protegido con
`super_read_only=1`.

### 8.5 Unir el nodo restante y restaurar la protección

#### Si se utilizó la Ruta A

Carlos une nodo3 dentro de `mysql>`:

Dentro de `mysql>`:

```sql
START GROUP_REPLICATION;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;

SET GLOBAL super_read_only=ON;
SELECT @@global.read_only,@@global.super_read_only;
```

Si nodo3 aparece `RECOVERING`, esperar y repetir únicamente el `SELECT` de
membresía. Resultado esperado: nodo1 y nodo3 `ONLINE`; nodo3 `1/1`.

#### Si se utilizó la Ruta B

Byron une nodo1, sin bootstrap:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Si nodo1 aparece `RECOVERING`, esperar y repetir solo la consulta. Cuando ambos
estén `ONLINE`, Carlos confirma otra vez:

```sql
SET GLOBAL super_read_only=ON;
SELECT @@global.read_only,@@global.super_read_only;
```

En ambas rutas, el punto 8.5 termina únicamente con nodo1 y nodo3 `ONLINE` y
nodo3 protegido `1/1`.

### 8.6 Byron demuestra que la escritura volvió

Esperar a que ProxySQL vuelva a mostrar nodo1 como escritor y ejecutar:

```bash
read -s 'fase5_app_password?Contraseña de app_user: '
echo

docker exec -e MYSQL_PWD="$fase5_app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 5 recuperacion','fase5.recuperacion@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

SELECT @@report_host AS backend,correo,nombre
FROM cliente
WHERE correo='fase5.recuperacion@example.com';
"

unset fase5_app_password
```

Resultado esperado: backend `.39` y fila insertada correctamente.

### 8.7 Michael registra T1 y calcula el RTO

Cuando Byron confirme la escritura exitosa:

```bash
fase5_t1=$(date +%s)
fase5_t0=$(cat /tmp/fase5-t0)

date --iso-8601=seconds
echo "RTO_fase5=$((fase5_t1-fase5_t0)) segundos"

unset fase5_t0 fase5_t1
```

El RTO se mide desde el segundo apagado hasta recuperar un escritor utilizable.

> **CAPTURA F5-08:** nodo1/nodo3 `ONLINE`, nodo3 `1/1`, escritura recuperada y
> RTO real.

---

## 9. Encender el nodo restante

### Ejecuta: Michael en nodo2

```bash
docker start mysql-node2

docker exec mysql-node2 sh -c '
intento=1
while [ "$intento" -le 30 ]; do
  if mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; then
    exit 0
  fi
  intento=$((intento + 1))
  sleep 2
done
exit 1
'

docker ps --filter name=mysql-node2 \
  --format 'table {{.Names}}\t{{.Status}}'
```

Sirve para: encender el último MySQL sin alterar su volumen ni la identidad del
sidecar Tailscale.

### Resultado esperado

- `mysql-node2` activo o saludable.
- `tailscale-node2` continúa con IP `.24`.
- Group Replication todavía puede mostrar nodo2 `OFFLINE` hasta el punto 10.

> **CAPTURA F5-09:** nodo2 encendido y Tailscale conservado.

---

## 10. Comprobar la sincronización de los tres nodos

### 10.1 Michael une nodo2 al grupo existente

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Si aparece `RECOVERING`, esperar y repetir solamente la consulta de membresía.
No hacer bootstrap en nodo2.

### 10.2 Los tres comparan GTID y datos

En cada nodo se consulta:

```sql
SELECT @@global.gtid_executed;

SELECT correo,nombre
FROM data_bugs.cliente
WHERE correo IN ('fase5.antes@example.com','fase5.recuperacion@example.com')
ORDER BY correo;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

Carlos confirma además:

```sql
SELECT @@global.read_only,@@global.super_read_only;
```

### Resultado esperado

- Tres miembros `ONLINE / PRIMARY`.
- Mismo GTID en los tres nodos.
- Ambas marcas visibles en nodo1, nodo2 y nodo3.
- Nodo3 continúa con `read_only=1` y `super_read_only=1`.
- RPO observado igual a cero: la marca previa permaneció y no se aceptaron
  escrituras durante la falta de quórum.

> **CAPTURA F5-10:** tres `ONLINE`, GTID iguales, ambas marcas y nodo3 `1/1`.

---

## Limpieza posterior a las evidencias

Se ejecuta únicamente después de completar y capturar el punto 10.

### Ejecuta: Byron mediante ProxySQL

```bash
read -s 'fase5_app_password?Contraseña de app_user: '
echo

docker exec -e MYSQL_PWD="$fase5_app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
DELETE FROM cliente
WHERE correo IN (
  'fase5.antes@example.com',
  'fase5.recuperacion@example.com',
  'fase5.noescribir@example.com',
  'fase5.noescribir.proxy@example.com'
);

SELECT ROW_COUNT() AS filas_eliminadas;

SELECT COUNT(*) AS marcas_fase5
FROM cliente
WHERE correo LIKE 'fase5.%@example.com';
"

fase5_cleanup_rc=$?
unset fase5_app_password
echo "resultado_limpieza=$fase5_cleanup_rc"
```

Resultado esperado: `marcas_fase5=0` y `resultado_limpieza=0`. La eliminación
se replica a los tres nodos.

## Detalles para explicar durante la defensa

- Tres miembros toleran la pérdida de uno; perder dos elimina el quórum.
- Bloquear escrituras sin quórum reduce el riesgo de split-brain.
- Nodo3 funciona como contingencia de lectura, no como escritor aislado.
- El bootstrap se usa una sola vez y solo después de dejar todos los miembros
  `OFFLINE` y comparar GTID.
- RTO se mide desde el segundo apagado hasta recuperar un escritor mediante
  ProxySQL.
- RPO observado debe ser cero porque no se aceptaron escrituras durante la
  contingencia y los datos previos permanecieron disponibles.

## Criterio de cierre

- [ ] Los tres nodos comenzaron `ONLINE` y sincronizados.
- [ ] Nodo1 fue detenido.
- [ ] Nodo2 fue detenido.
- [ ] Las escrituras directa y por proxy fueron rechazadas.
- [ ] Los `SELECT` directos en nodo3 continuaron disponibles.
- [ ] Nodo3 permaneció protegido en solo lectura.
- [ ] Nodo1 volvió a encender.
- [ ] Se recuperó la escritura y se registró el RTO.
- [ ] Nodo2 volvió a encender.
- [ ] Los tres terminaron `ONLINE`, con GTID/datos iguales y RPO cero.
- [ ] Las marcas temporales se eliminaron después de las evidencias.

La Fase 5 termina únicamente cuando se cumplen los diez numerales y el clúster
queda restaurado con tres miembros `ONLINE`.
