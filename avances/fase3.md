# Fase 3 — Fallo de un nodo principal

## Objetivo oficial

Validar la disponibilidad ante la caída del primer nodo de lectura y escritura.
La prueba debe demostrar que ProxySQL detecta la caída de nodo1, nodo2 mantiene
lectura/escritura, nodo3 recibe los cambios y nodo1 se reintegra sin pérdida de
datos.

Los responsables indicados organizan la prueba, pero todos deben entender cada
comando. Las operaciones locales de Docker solo las ejecuta el dueño físico de
la computadora correspondiente.

## Responsables iniciales

| Función | Responsable |
|---|---|
| Detener, encender y reincorporar `mysql-node1` | Byron |
| Ejecutar lectura/escritura mediante ProxySQL | Michael |
| Verificar nodo3, controlar tiempos y evidencias | Carlos |

## Regla importante de esta fase

No se apaga físicamente la computadora de Byron porque ProxySQL está alojado
en ella. Se detiene únicamente el contenedor `mysql-node1`; el contenedor
`proxysql-db2`, Tailscale y el sistema operativo permanecen activos.

Esto prueba la caída del MySQL principal. La caída completa del host de Byron
también derribaría el único ProxySQL y se registra como una limitación o punto
único de fallo de la arquitectura.

No avanzar al siguiente numeral hasta confirmar y capturar el resultado del
actual.

---

## 1. Verificar que los tres nodos estén funcionando

### Ejecuta: Byron en nodo1

Desde la raíz del repositorio:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'

docker ps --format 'table {{.Names}}\t{{.Status}}' \
  | grep -E 'mysql-node1|proxysql-db2'
```

Sirve para: confirmar que la prueba comienza con tres miembros disponibles y
que ProxySQL seguirá funcionando cuando se detenga MySQL de nodo1.

### Ejecuta: Carlos en nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host AS nodo,@@global.read_only AS read_only,@@global.super_read_only AS super_read_only;"
```

### Resultado esperado

- `.39`, `.24` y `.57` aparecen `ONLINE / PRIMARY`.
- `mysql-node1` está saludable.
- `proxysql-db2` está saludable.
- Nodo3 muestra `read_only=1` y `super_read_only=1`.

> **CAPTURA F3-01:** tres miembros `ONLINE`, ProxySQL activo y nodo3 protegido.

Si falta un miembro, no se inicia la falla: se recupera primero siguiendo
`avances/inicio.md`.

---

## 2. Insertar información antes de provocar la falla

### Ejecuta: Michael desde nodo2, mediante ProxySQL

```bash
docker exec -it mysql-node2 mysql \
  -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 3 antes','fase3.antes@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

SELECT correo,nombre
FROM cliente
WHERE correo='fase3.antes@example.com';
"
```

La contraseña de `app_user` que es `1e36ef73c4155f18823d67fa16fe096a82dd7c193e73602d` se introduce en el prompt y no se escribe en el
comando ni en la captura.

Sirve para: crear una marca previa a la falla que deberá seguir disponible y
aparecer también en nodo1 después de su recuperación.

### Resultado esperado

```text
fase3.antes@example.com | Evidencia fase 3 antes
```

> **CAPTURA F3-02:** fila previa confirmada mediante el puerto `6033`.

---

## 3. Apagar o detener el servicio del Nodo 1

### Ejecuta: Byron

```bash
date --iso-8601=seconds
date +%s > /tmp/fase3-t0
docker stop mysql-node1
docker ps --format 'table {{.Names}}\t{{.Status}}' \
  | grep -E 'mysql-node1|proxysql-db2' || true
```

Sirve para:

- registrar `T0`, inicio de la interrupción;
- simular la caída del servicio MySQL de nodo1;
- comprobar que ProxySQL permanece encendido.

### Resultado esperado

- `docker stop` responde `mysql-node1`.
- `mysql-node1` ya no aparece entre los contenedores activos.
- `proxysql-db2` continúa activo.

> **CAPTURA F3-03:** hora T0, contenedor nodo1 detenido y ProxySQL todavía
> activo.

No utilizar `docker compose down`, `down -v` ni apagar la computadora de Byron.

---

## 4. Verificar que el proxy o balanceador detecte la caída

### Ejecuta: Byron

Como `mysql-node1` está detenido, se utiliza temporalmente el cliente de la
imagen MySQL para consultar el puerto administrativo local de ProxySQL:

```bash
admin_pair=$(sed -n 's/^[[:space:]]*admin_credentials="\([^"]*\)".*/\1/p' proxy/conf/proxysql.cnf | head -n1)
proxy_admin_user=${admin_pair%%:*}
proxy_admin_pass=${admin_pair#*:}

docker run --rm --network host \
  -e MYSQL_PWD="$proxy_admin_pass" mysql:8.4 \
  mysql -h127.0.0.1 -P6032 -u"$proxy_admin_user" -e "
SELECT hostgroup_id,hostname,port,status
FROM runtime_mysql_servers
ORDER BY hostgroup_id,hostname;
"

unset admin_pair proxy_admin_user proxy_admin_pass
```

Sirve para: consultar el estado en memoria de ProxySQL sin modificarlo y
comprobar que nodo1 dejó de ser un backend utilizable.

### Resultado esperado

- Nodo1 `.39` ya no aparece `ONLINE` en un hostgroup activo o aparece en el
  hostgroup de servidores apartados.
- Nodo2 `.24` permanece disponible como escritor.
- Nodo3 `.57` permanece disponible para lectura.

El monitor puede tardar algunos segundos. Si el primer resultado aún muestra
nodo1 activo, esperar un ciclo de monitoreo y repetir únicamente esta consulta.

> **CAPTURA F3-04:** hostgroups después de que ProxySQL detecte la caída.

---

## 5. Ejecutar operaciones de lectura y escritura en el Nodo 2

### Ejecuta: Michael desde nodo2, mediante ProxySQL

```bash
docker exec -it mysql-node2 mysql \
  -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "
START TRANSACTION;

SELECT @@report_host AS backend_escritor,
       @@server_id AS server_id,
       correo,nombre
FROM cliente
WHERE correo='fase3.antes@example.com'
FOR UPDATE;

INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 3 durante','fase3.durante@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

COMMIT;

SELECT correo,nombre
FROM cliente
WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com')
ORDER BY correo;
"
```

Sirve para:

- leer y bloquear la marca previa usando el backend escritor;
- insertar una nueva marca mientras nodo1 está caído;
- confirmar que el servicio continúa disponible mediante ProxySQL.

### Resultado esperado

- `backend_escritor=100.126.57.24` y `server_id=2`.
- La transacción termina sin error.
- La consulta final muestra los correos `fase3.antes` y `fase3.durante`.

> **CAPTURA F3-05:** backend `.24`, lectura previa y escritura exitosa.

---

## 6. Verificar que los cambios se reflejen en el Nodo 3

### Ejecuta: Carlos directamente en nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT correo,nombre FROM cliente WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com') ORDER BY correo; SELECT @@global.read_only AS read_only,@@global.super_read_only AS super_read_only;"
```

Sirve para: demostrar que nodo3 recibió por replicación la escritura realizada
en nodo2 y continúa protegido contra escrituras directas.

### Resultado esperado

- Aparecen las dos filas de evidencia.
- Nodo3 continúa con `read_only=1` y `super_read_only=1`.

> **CAPTURA F3-06:** dos filas visibles en nodo3 y protección `1/1`.

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
  sleep 2;
done
exit 1
'

docker ps --filter name=mysql-node1 \
  --format 'table {{.Names}}\t{{.Status}}'
```

Sirve para: encender el servicio MySQL y esperar a que acepte conexiones antes
de intentar reincorporarlo al grupo. La espera tiene un límite aproximado de
60 segundos; si termina con error, se revisan los logs y no se ejecuta START.

### Resultado esperado

- `mysqladmin ping` termina correctamente.
- `mysql-node1` aparece activo o saludable.
- Todavía puede estar `OFFLINE` de Group Replication; eso es normal porque
  `group_replication_start_on_boot=OFF`.

> **CAPTURA F3-07:** contenedor nodo1 encendido y MySQL respondiendo.

---

## 8. Verificar que nodo1 se reintegre y sincronice

### Ejecuta: Byron

No se utiliza bootstrap porque nodo2 y nodo3 conservaron el grupo activo.

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Si nodo1 aparece `RECOVERING`, esperar unos segundos y ejecutar solamente:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Cuando nodo1 esté `ONLINE`, Byron confirma la sincronización:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT correo,nombre
FROM data_bugs.cliente
WHERE correo IN ('\''fase3.antes@example.com'\'','\''fase3.durante@example.com'\'')
ORDER BY correo;

SELECT @@global.gtid_executed;
"'
```

Sirve para: reincorporar nodo1 mediante recuperación distribuida y demostrar
que recibió la transacción ejecutada durante su caída.

### Resultado esperado

- Los tres miembros aparecen `ONLINE / PRIMARY`.
- Nodo1 muestra ambas filas de evidencia.
- No aparece `ERROR` ni queda permanentemente en `RECOVERING`.

> **CAPTURA F3-08:** tres miembros `ONLINE` y ambas filas recuperadas en
> nodo1.

---

## 9. Registrar el tiempo de recuperación

### Ejecuta: Byron; registra y captura: Carlos

Se toma `T1` únicamente después de observar nodo1 `ONLINE` y sincronizado:

```bash
fase3_t1=$(date +%s)
fase3_t0=$(cat /tmp/fase3-t0)

date --iso-8601=seconds
echo "RTO_fase3=$((fase3_t1-fase3_t0)) segundos"

unset fase3_t0 fase3_t1
```

Sirve para: medir el RTO desde la detención de nodo1 hasta su recuperación
completa dentro del grupo.

### Resultado esperado

```text
RTO_fase3=N segundos
```

El valor real `N` se copia en la bitácora y en el informe; no se inventa ni se
reemplaza por una estimación.

> **CAPTURA F3-09:** hora T1 y RTO calculado.

---

## Limpieza posterior a la evidencia

La limpieza no forma parte de los nueve numerales oficiales y se realiza solo
después de guardar todas las capturas.

### Ejecuta: Byron mediante ProxySQL

Desde la raíz del repositorio:

```bash
read -s 'fase3_app_password?Contraseña de app_user: '
echo

docker run --rm --network host \
  -e MYSQL_PWD="$fase3_app_password" mysql:8.4 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
DELETE FROM cliente
WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com');

SELECT COUNT(*) AS marcas_fase3
FROM cliente
WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com');
"

unset fase3_app_password
```

Resultado esperado: `marcas_fase3=0`. Michael y Carlos pueden confirmar la
eliminación en sus nodos.

## Detalles para explicar durante la defensa

- ProxySQL retira el backend caído sin cambiar la dirección usada por el
  cliente.
- Group Replication mantiene disponibilidad con dos de tres miembros porque
  conserva quórum.
- GTID permite que nodo1 identifique y recupere las transacciones que perdió.
- Nodo3 recibe los cambios, pero `super_read_only` impide usarlo para escritura.
- El host de Byron sigue siendo un punto único para ProxySQL; una mejora sería
  desplegar otro proxy y una IP virtual o DNS de failover.

## Criterio de cierre

- [ ] Los tres nodos iniciaron `ONLINE`.
- [ ] Se insertó una marca antes de la falla.
- [ ] Se detuvo únicamente `mysql-node1`.
- [ ] ProxySQL detectó la caída.
- [ ] Nodo2 mantuvo lectura y escritura mediante el puerto `6033`.
- [ ] Nodo3 recibió el cambio y permaneció en solo lectura.
- [ ] Nodo1 volvió a encender.
- [ ] Nodo1 se reintegró `ONLINE` y recuperó ambas marcas.
- [ ] Se registró el RTO real.
- [ ] Las marcas temporales fueron eliminadas después de las evidencias.

La Fase 3 termina únicamente cuando todos los puntos están comprobados y el
clúster vuelve a quedar con tres miembros `ONLINE`.
