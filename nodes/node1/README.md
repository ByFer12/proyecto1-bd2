# Nodo 1 — Ubuntu

Este directorio contiene la instancia MySQL 8.4 de Byron, utilizada como nodo
inicial del grupo y fuente del dataset `data_bugs`.

El avance reproducible de cada fase se documenta por separado en
[`avances/`](./avances/). La Fase 1 está detallada en
[`avances/fase1.md`](./avances/fase1.md).

## Estado actual

- Contenedor: `mysql-node1`.
- Motor validado: MySQL 8.4.11.
- `server_id`: `1`.
- IP Tailscale: `100.113.38.39`.
- Puerto MySQL: `3306`.
- Comunicación de Group Replication: pila `MYSQL` sobre el puerto `3306`.
- Group Replication: tres nodos validados simultáneamente `ONLINE / PRIMARY`.
- Dataset principal: `data_bugs`.
- Red Docker: `network_mode: host`.

## Direcciones oficiales de la Tailnet

| Nodo | Responsable | Sistema | IP Tailscale | Rol |
|---|---|---|---|---|
| Nodo 1 | Byron | Ubuntu | `100.113.38.39` | Lectura/escritura e inicialización |
| Nodo 2 | Michael | Debian | `100.126.57.24` (servicio MySQL) | Lectura/escritura |
| Nodo 3 | Carlos | Windows 11 | `100.107.61.57` | Lectura/contingencia |

La IP `100.109.4.122` corresponde al host de Michael. MySQL nodo2 utiliza la
IP `100.126.57.24` de su sidecar Tailscale. El equipo antiguo
`100.75.156.76` no forma parte del clúster.

## Preparación local

1. Copiar `.env.example` como `.env`.
2. Definir una contraseña privada en `MYSQL_ROOT_PASSWORD`.
3. No subir `.env` al repositorio.
4. Crear o actualizar el contenedor:

```bash
cd nodes/node1
docker compose up -d --force-recreate
```

5. Consultar su estado y logs:

```bash
docker compose ps
docker logs mysql-node1 --tail 30
```

Resultado validado: MySQL inicia correctamente, escucha en `3306` y el
contenedor llega al estado `healthy`.

## Verificación de Tailscale

```bash
tailscale ip -4
tailscale status
tailscale ping 100.126.57.24
tailscale ping 100.107.61.57
nc -vz -w 5 100.126.57.24 3306
nc -vz -w 5 100.107.61.57 3306
```

Resultados validados:

- Nodo2 puede conectarse y autenticarse contra nodo1 por `3306`.
- Nodo1 y nodo2 están `ONLINE` mediante la pila `MYSQL`.
- Nodo1 recibe respuesta Tailscale de nodo3 y alcanza correctamente
  `100.107.61.57:3306`.

## Configuración validada de Group Replication

Los tres nodos utilizan:

```text
UUID: c395e8af-d580-4d6c-8574-a629027f1379
Pila de comunicación: MYSQL
Modo single-primary: OFF
Enforce update everywhere checks: ON
Semillas:
  100.113.38.39:3306
  100.126.57.24:3306
  100.107.61.57:3306
```

Consulta ejecutada en nodo1:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT PLUGIN_NAME, PLUGIN_STATUS
FROM INFORMATION_SCHEMA.PLUGINS
WHERE PLUGIN_NAME = '\''group_replication'\'';

SELECT
  @@server_id,
  @@group_replication_group_name,
  @@group_replication_local_address,
  @@group_replication_group_seeds,
  @@group_replication_single_primary_mode,
  @@group_replication_enforce_update_everywhere_checks;
"'
```

Resultado validado:

```text
plugin: group_replication ACTIVE
server_id: 1
local_address: 100.113.38.39:3306
communication_stack: MYSQL
single_primary_mode: 0
enforce_update_everywhere_checks: 1
```

## Datos y GTID de nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@global.gtid_executed;"'
```

Resultado observado durante la preparación:

```text
5248cb8e-aff2-11f1-8a74-fa8b2c2f6510:1-20
```

Para listar las bases:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"'
```

Se confirmó que existe `data_bugs`. Por ello nodo1 será el miembro inicial y
la fuente de datos del grupo.

## Usuario y canal de recuperación

Se confirmó que existe `repl@%` con este permiso:

```text
GRANT REPLICATION SLAVE ON *.* TO `repl`@`%`
```

Para establecer o rotar su contraseña sin replicar el cambio:

```sql
SET SQL_LOG_BIN=0;
ALTER USER 'repl'@'%' IDENTIFIED BY 'CLAVE_PRIVADA_COMPARTIDA';
SET SQL_LOG_BIN=1;
```

La contraseña real no debe escribirse aquí ni subirse a Git.

Configuración correcta del canal especial de recuperación:

```sql
SET GLOBAL group_replication_recovery_get_public_key=ON;

CHANGE REPLICATION SOURCE TO
  SOURCE_USER='repl',
  SOURCE_PASSWORD='CLAVE_PRIVADA_COMPARTIDA'
FOR CHANNEL 'group_replication_recovery';
```

No se debe agregar `GET_SOURCE_PUBLIC_KEY` directamente a `CHANGE REPLICATION
SOURCE` para este canal; MySQL devuelve el error `3139`. Group Replication usa
la variable `group_replication_recovery_get_public_key`.

Verificación realizada:

```sql
SELECT CHANNEL_NAME, USER
FROM performance_schema.replication_connection_configuration
WHERE CHANNEL_NAME='group_replication_recovery';
```

Resultado validado:

```text
group_replication_recovery | repl
```

## Dirección anunciada

Nodo1 anuncia su IP Tailscale y permite obtener la clave pública de recuperación:

```ini
report_host=100.113.38.39
loose-group_replication_recovery_get_public_key=ON
```

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@report_host, @@group_replication_recovery_get_public_key;"'
```

Resultado validado:

```text
100.113.38.39  1
```

## Inicialización del grupo desde nodo1

El grupo se inicializó una sola vez desde nodo1 con estas instrucciones:

```sql
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
```

Es obligatorio volver a colocar `group_replication_bootstrap_group=OFF`, incluso
si el inicio produce un error, para evitar crear accidentalmente otro grupo.

Consulta de estado:

```sql
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

Resultado validado:

```text
MEMBER_HOST       MEMBER_PORT  MEMBER_STATE  MEMBER_ROLE
100.113.38.39     3306         ONLINE        PRIMARY
```

Esto confirma que nodo1 creó correctamente el grupo y está disponible como
primer miembro. Todavía no confirma replicación entre hosts; faltan nodo2 y
nodo3.

## Avance de la Fase 1

Evaluación contra los ocho puntos de la Fase 1 del enunciado:

- [x] Tres nodos en equipos independientes.
- [x] Red privada Tailscale común y direcciones identificadas.
- [x] Mecanismo de replicación configurado: tres miembros `ONLINE`.
- [x] Nodo1 y nodo2 configurados para lectura/escritura en modo multi-primary.
- [x] Nodo3 configurado y validado como lectura/contingencia.
- [x] ProxySQL integrado y validado localmente con separación lectura/escritura.
- [x] Conectividad directa y cliente remoto autenticado mediante ProxySQL.
- [x] Tres nodos disponibles simultáneamente.

**Implementación funcional de Fase 1: 100 %** (8 puntos completos). El núcleo
de Group Replication está en **3 de 3 nodos ONLINE**, ProxySQL enruta por roles
y un cliente remoto de nodo3 autenticó correctamente por el puerto `6033`.
Las capturas se organizarán en paralelo dentro del informe final.
Las pruebas CRUD pertenecen a la Fase 2 y todavía no se contabilizan como
completadas.

Después de un apagado inesperado de nodo1, Docker recuperó MySQL y ProxySQL
sin pérdida de volúmenes. Nodo2 y nodo3 conservaron el grupo `ONLINE`; sus
GTID coincidían con nodo1, por lo que nodo1 regresó mediante
`START GROUP_REPLICATION`, sin bootstrap. La comprobación final volvió a
mostrar los tres miembros `ONLINE / PRIMARY`.

## Avance global contra el enunciado y el plan

Estos porcentajes son una estimación técnica, no la ponderación oficial de la
calificación. Solo se marca como terminado lo que además de estar configurado
ya fue ejecutado y comprobado con evidencia.

| Fase oficial | Avance | Estado actual |
|---|---:|---|
| 1. Preparación | 100 % | Tres nodos `ONLINE`, roles, ProxySQL, cliente remoto y diagrama validados. |
| 2. Replicación normal | 10 % | Existen scripts CRUD, pero aún no se ejecutó y evidenció el ciclo desde nodo1 y nodo2. |
| 3. Fallo de nodo1 | 10 % | Hay experiencia y procedimiento de recuperación, pero falta la prueba controlada mediante proxy, CRUD y RTO. |
| 4. Fallo de nodo2 | 10 % | Se recuperó un incidente real de nodo2, pero falta ejecutar el escenario oficial completo y medirlo. |
| 5. Fallo múltiple | 5 % | Se practicó un apagado total, pero no el escenario exigido con nodo3 atendiendo lecturas de contingencia. |
| 6. Carga | 0 % | Falta herramienta, guion, ejecución y resultados. |
| 7. Monitoreo | 15 % | Hay archivos iniciales de Prometheus/Grafana en nodo3; faltan exporters de los tres nodos, corregir destinos, dashboard y pruebas. |
| 8. RTO/RPO | 0 % | Falta medición formal y análisis de pérdida de datos. |
| 9. Resiliencia en calificación | 15 % | Existe un runbook de recuperación, pero falta el simulacro integral del grupo. |
| 10. Informe final | 20 % | Este README conserva una bitácora amplia; faltan consolidar arquitectura, evidencias, resultados, limitaciones y conclusiones. |

**Avance práctico estimado del enunciado obligatorio: 33 %.** La media simple
de fases sería menor, pero la infraestructura y Group Replication representan
una parte técnica central ya resuelta. El proyecto no se considera terminado
hasta completar pruebas, proxy, observabilidad, métricas e informe.

**Avance estimado del plan completo con mejoras: 23 %.** Las mejoras de backup,
PITR, TLS, partición de red, validación automática, alertas, Clone Plugin y
Telegram/Discord siguen pendientes o apenas iniciadas. No deben desplazar los
requisitos obligatorios mientras quede alguna fase oficial incompleta.

El siguiente orden seguro es: inventariar el dataset existente; ejecutar los
scripts de `database/tests/` para la Fase 2;
después realizar fallos, carga, monitoreo y RTO/RPO con evidencia.

Evidencia técnica ya obtenida:

- UUID, pila `MYSQL`, semillas y modo multi-primary coincidentes en los tres nodos.
- Canales de recuperación y usuario `repl` preparados en los tres nodos.
- Nodo1 `100.113.38.39:3306`, nodo2 `100.126.57.24:3306` y nodo3
  `100.107.61.57:3306` simultáneamente `ONLINE / PRIMARY`.
- Bootstrap confirmado en `OFF` después de formar el grupo.

### Primer intento de unión de nodo2

Nodo2 confirmó previamente:

```text
report_host: 100.109.4.122
group_replication_recovery_get_public_key: 1
canal group_replication_recovery: usuario repl
```

Al ejecutar:

```sql
START GROUP_REPLICATION;
```

se obtuvo:

```text
ERROR 3096 (HY000): The START GROUP_REPLICATION command failed as there was an
error when initializing the group communication layer.
```

La conectividad desde nodo2 hacia `100.113.38.39:33061` fue validada como
correcta. Los logs identificaron la causa exacta:

```text
[GCS] There is no local IP address matching the one configured for the local
node (100.109.4.122:33061).
```

El error sucede antes de la recuperación de datos. En nodo2, Docker Desktop no
expone la interfaz Tailscale del sistema dentro del contenedor aunque Compose
declare `network_mode: host`. La configuración se cambió para asignar al
contenedor una dirección estática `100.109.4.122` en una red bridge y publicar
`3306` y `33061`, siguiendo el enfoque utilizado por nodo3.

La imagen mínima `mysql:8.4` no incluye el ejecutable `hostname`, por lo que
`docker exec mysql-node2 hostname -I` devuelve `executable file not found`.
La dirección interna debe comprobarse desde el host con `docker inspect`:

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mysql-node2
```

El resultado esperado después de recrear el contenedor es `100.109.4.122`.

Resultado validado tras cambiar nodo2 a la red bridge estática:

```text
100.109.4.122
```

Esto confirma que la dirección configurada en
`group_replication_local_address` ya existe dentro del contenedor y permite
reintentar la unión al grupo.

### Segundo intento de unión de nodo2

Después de validar la IP interna, `START GROUP_REPLICATION` avanzó más que en
el primer intento, pero la sesión perdió la conexión con el servidor:

```text
ERROR 2013 (HY000): Lost connection to MySQL server during query
ERROR 2002 (HY000): Can't connect to local MySQL server through socket
```

Esto indica que el proceso `mysqld` terminó o se reinició durante el inicio de
Group Replication. Después apareció un ciclo de reinicio con:

```text
chown: changing ownership of '/var/lib/mysql/mysql.sock': Operation not permitted
```

La causa es el bind mount `./data:/var/lib/mysql` sobre el sistema de archivos
compartido de Docker Desktop. La solución elegida es un volumen administrado
por Docker (`mysql_node2_data:/var/lib/mysql`), donde MySQL sí puede gestionar
propietarios y permisos. La carpeta antigua `nodes/node2/data` se conserva como
respaldo y no se borra.

`fix-node.sh` se reemplazó por una recreación segura que espera el healthcheck.
Ya no ejecuta `rm -rf`, no aplica permisos `777` y no contiene contraseñas.

El montaje nuevo fue validado con `docker inspect`:

```text
volume node2_mysql_node2_data -> /var/lib/mysql
bind -> /etc/mysql/conf.d/my.cnf
```

La primera línea confirma que los datos de MySQL usan almacenamiento gestionado
por Docker. El segundo montaje es correcto: corresponde únicamente al archivo
`my.cnf` de solo lectura.

Después de crear el volumen, nodo2 quedó `Up (healthy)`, publicó `3306` y
`33061`, y MySQL 8.4.11 terminó correctamente su inicialización. Los logs ya no
presentan errores de propietarios. Durante la inicialización se creó `datadb`,
por lo que se debe revisar `gtid_executed` antes de unirlo al historial de
nodo1.

La consulta devolvió:

```text
f64d3eba-b24e-11f1-b1c8-0abd1308b014:1-6
```

Estos seis GTID locales fueron generados durante la inicialización de nodo2,
incluida la creación automática de `datadb` mediante `MYSQL_DATABASE=datadb`.
Como el dataset oficial es `data_bugs`, nodo2 debe eliminar esa base sin
registrar otro GTID y restablecer sus binary logs/GTID antes de unirse al grupo.
También debe retirarse `MYSQL_DATABASE=datadb` de su `.env` para que no vuelva
a crearse al inicializar un volumen nuevo.

Nodo2 eliminó `datadb` con el binary log desactivado y ejecutó `RESET BINARY
LOGS AND GTIDS`. La validación posterior mostró `gtid_executed` vacío y solo
las bases de sistema (`information_schema`, `mysql`, `performance_schema` y
`sys`). Nodo2 quedó listo para recibir el historial autoritativo de nodo1.

Sobre el volumen limpio se configuró nuevamente el canal
`group_replication_recovery`. La consulta de validación devolvió:

```text
group_replication_recovery | repl
```

Con esto quedaron preparados la red, almacenamiento, GTID y credenciales de
nodo2 para un nuevo intento de unión.

### Tercer intento de unión de nodo2

Con el volumen administrado, `gtid_executed` vacío y el canal de recuperación
recreado, se ejecutó nuevamente:

```sql
START GROUP_REPLICATION;
```

La conexión volvió a cerrarse durante la operación:

```text
ERROR 2013 (HY000): Lost connection to MySQL server during query
ERROR 2002 (HY000): Can't connect to local MySQL server through socket
```

Esto confirma que el proceso `mysqld` del nodo2 termina o se reinicia durante
el arranque de Group Replication. El siguiente diagnóstico es revisar los
mensajes finales del contenedor producidos exactamente durante este intento;
no se debe volver a ejecutar `START GROUP_REPLICATION` hasta identificar esa
causa.

El log completo permitió precisar el punto del fallo. Group Replication inicia
el canal `group_replication_applier` y alcanza este mensaje:

```text
The Group Replication certifier broadcast thread (THD_certifier_broadcast) started.
```

Inmediatamente después, el propio servidor MySQL 8.4.11 aborta:

```text
*** buffer overflow detected ***: terminated
mysqld got signal 6
```

El mismo patrón apareció en dos intentos consecutivos. Por tanto, este cierre
no lo causan la contraseña de `repl`, los GTID, el volumen ni un comando SQL
incorrecto. Es un aborto interno del proceso durante la inicialización de la
capa de comunicación/certificación. Antes de aplicar una solución se
comprobarán los límites y descriptores del proceso, porque la capa XCom utiliza
descriptores de red y un descriptor fuera de rango puede provocar esta clase
de aborto. No se debe borrar ni recrear el volumen para este diagnóstico.

La comprobación de recursos del proceso devolvió:

```text
Límite de descriptores: 1048576
Descriptor más alto:    36
Descriptores abiertos:  37
```

El descriptor más alto es muy inferior a 1024, por lo que se descarta que el
aborto se deba a agotamiento de descriptores o a un descriptor de red fuera de
rango. La comparación con el archivo funcional de nodo1 mostró que el `my.cnf`
de nodo2 no declara explícitamente `report_host`, `binlog_format=ROW`,
`skip_name_resolve=ON` ni `group_replication_recovery_get_public_key=ON`. El
siguiente paso es consultar sus valores efectivos antes de modificar el
archivo.

La consulta de valores efectivos en nodo2 devolvió:

```text
report_host:                                100.109.4.122
binlog_format:                              ROW
skip_name_resolve:                          1
group_replication_recovery_get_public_key:  1
```

Aunque algunas opciones no aparecen en la copia local de `my.cnf`, sus valores
activos son correctos. Por ello no se consideran la causa del aborto y no se
modifican todavía. El diagnóstico continúa sobre la pila de comunicación de
Group Replication, que es donde ocurre el cierre.

La versión y pila de comunicación activas se confirmaron como:

```text
8.4.11  XCOM
```

El aborto ocurre, por tanto, al iniciar XCom en nodo2. Debe confirmarse si el
daemon utilizado es Docker Desktop: en Linux, su máquina virtual de red no
comparte directamente la interfaz Tailscale del host. Esa separación fue la
causa del primer error de dirección local y obligó a asignar artificialmente
la IP Tailscale a una red bridge. Si existe Docker Engine nativo, utilizarlo
con red host evita esa topología artificial.

La comprobación del motor de nodo2 devolvió:

```text
Contexto activo:   desktop-linux
Sistema del daemon: Docker Desktop
```

Queda confirmado que MySQL no se ejecuta directamente sobre la red del Debian
anfitrión, sino dentro de la máquina virtual de Docker Desktop. La IP
`100.109.4.122` agregada a la red bridge solamente imita la IP Tailscale; no es
la interfaz Tailscale real. Este diseño explica tanto el error inicial de XCom
al usar red host como el aborto posterior al forzar una red bridge solapada.
La corrección preferida es usar Docker Engine nativo con `network_mode: host`,
pero antes se comprobará si el contexto nativo ya está instalado y disponible.

El contexto `default` apunta correctamente a `/var/run/docker.sock`, pero la
consulta respondió:

```text
failed to connect to the docker API at unix:///var/run/docker.sock
no such file or directory
```

Por tanto, el daemon de Docker Engine nativo no está disponible actualmente.
Docker Desktop y sus volúmenes permanecen intactos. Antes de instalar el motor
nativo se revisarán los paquetes existentes para evitar sustituir o mezclar
paquetes incompatibles.

La revisión de paquetes mostró que Docker Desktop, `docker-ce-cli`, Buildx y
Compose están instalados, pero no `docker-ce` ni `containerd.io`. También
reveló una inconsistencia que debe resolverse antes de instalar:

```text
docker-ce candidato:    repositorio debian trixie
containerd.io candidato: repositorio debian trixie
docker.io candidato:     repositorio debian bookworm
```

El equipo había sido reportado como Debian 12 (`bookworm`), pero
`/etc/os-release` y `hostnamectl` confirmaron que en realidad ejecuta Debian
`trixie/sid`. Por tanto, el repositorio oficial de Docker configurado como
`trixie` es correcto y no existe mezcla de versiones. Se puede instalar
`docker-ce` y `containerd.io` desde el repositorio ya configurado, conservando
Docker Desktop y sus datos mientras se valida el motor nativo.

La simulación de instalación evitó realizar cambios y reveló una instalación
parcialmente mezclada:

```text
containerd.io requiere: libseccomp2 >= 2.6.0
versión seleccionada:   libseccomp2 2.5.4-1+deb12u1
```

Aunque `/etc/os-release` indica `trixie/sid`, una biblioteca base procede de
Debian 12. No se debe forzar la actualización aislada de `libseccomp2`, porque
puede desestabilizar el sistema. Antes de instalar Docker Engine se verificará
si los repositorios y la biblioteca C base corresponden realmente a Bookworm
o a Trixie; con esa evidencia se elegirá la variante compatible del repositorio
Docker. La simulación no instaló ni eliminó nada.

La inspección confirmó una actualización parcial del sistema:

```text
/etc/os-release:                    trixie/sid
libc6 instalada:                    2.41-6
repositorios principales de Debian: bookworm
libseccomp2 instalada/candidata:     2.5.4-1+deb12u1
repositorio Docker:                  trixie
```

No se intentará completar ni revertir la actualización completa de Debian
durante la configuración del clúster. La corrección acotada consiste en cambiar
solo el repositorio de Docker de `trixie` a `bookworm`, manteniendo los demás
repositorios intactos. Los paquetes Docker de Bookworm son compatibles con la
`libseccomp2` disponible. Antes de instalar se hará otra simulación y se
conservará una copia de seguridad de `docker.list`.

### Decisión de seguridad sobre nodo2

Debido a que el equipo de Michael contiene documentos y otros proyectos, se
detuvo la instalación de Docker Engine nativo. En un sistema con una
actualización parcial de Debian no puede garantizarse riesgo cero al cambiar
paquetes base. No se ejecutará `apt install`, `apt upgrade`, ni se forzará una
versión de `libseccomp2`. Se buscará una alternativa contenida en Docker
Desktop o se utilizará otro host, sin modificar el sistema operativo.

Se comprobó que `/etc/apt/sources.list.d/docker.list` continúa apuntando a
`trixie`. Por tanto, los comandos propuestos para copiar o editar ese archivo
no llegaron a ejecutarse y no hay cambios que restaurar. Tampoco se instalaron
paquetes. La alternativa seleccionada para evaluar es ejecutar Tailscale como
contenedor auxiliar dentro de Docker Desktop y compartir su espacio de red con
MySQL. Primero se comprobará de forma temporal si Docker Desktop permite usar
el dispositivo `/dev/net/tun`; esta prueba no modifica Compose ni el sistema
operativo.

La prueba temporal devolvió correctamente:

```text
crw-rw-rw- 1 root root 10, 200 ... /dev/net/tun
```

Docker Desktop puede proporcionar `/dev/net/tun` a un contenedor, por lo que
es viable ejecutar Tailscale dentro de Docker y hacer que MySQL comparta su
espacio de red. El contenedor de prueba se eliminó automáticamente; únicamente
quedó la imagen pequeña `alpine:3.20` en la caché de Docker Desktop. La futura
credencial de Tailscale será privada y nunca se guardará en Git ni en este
README.

Carlos generó la clave de autenticación para el contenedor de nodo2 y la
compartió de forma privada con Michael. El archivo `nodes/node2/.env` está
excluido por `.gitignore`; la clave se guardará únicamente allí como
`TS_AUTHKEY`, sin imprimirla en terminal ni incluirla en commits.

Michael confirmó con `git check-ignore -v .env` que el archivo está excluido
por la regla `/nodes/node2/.env`. Después se actualizó el Compose de nodo2:

- Se agregó `tailscale-node2` usando la imagen oficial de Tailscale.
- Se habilitó kernel networking mediante `/dev/net/tun`, `NET_ADMIN` y
  `NET_RAW`.
- La identidad se conserva en el volumen `tailscale_node2_state`.
- MySQL utiliza `network_mode: service:tailscale-node2` para compartir la
  interfaz Tailscale real.
- Los puertos `3306` y `33061` se publican desde ese espacio de red.
- Se eliminó la red bridge artificial `100.109.4.0/24`.
- El volumen `mysql_node2_data` se conserva sin borrarlo.

La sintaxis del archivo fue validada con `docker compose config --no-interpolate
--quiet`.

Michael recibió el Compose actualizado y ejecutó `docker compose config
--services`. Se reconocieron correctamente los servicios `tailscale-node2`,
`mysql-node2` y `prometheus`. Antes de levantar el nuevo servicio Tailscale se
debe detener el contenedor MySQL anterior, porque aún publica `3306` y `33061`;
detenerlo no elimina su volumen ni sus datos.

El contenedor anterior se detuvo correctamente con `docker stop mysql-node2`.
El comando devolvió `mysql-node2`; no se ejecutó `docker compose down` y el
volumen `mysql_node2_data` permanece intacto. Los puertos quedaron disponibles
para iniciar el contenedor Tailscale.

Se inició únicamente `tailscale-node2`. Docker Desktop descargó la imagen
oficial, creó la red `node2_default`, creó el volumen persistente
`node2_tailscale_node2_state` y dejó el contenedor en estado `Started`. MySQL
continúa detenido. El siguiente paso es confirmar la autenticación y obtener la
nueva IP Tailscale del contenedor antes de modificar `my.cnf`.

El contenedor se autenticó correctamente en el tailnet de Carlos y recibió:

```text
100.126.57.24  mysql-node2  clp64413@  linux
```

Esta es la nueva IP oficial para MySQL nodo2. `100.109.4.122` continúa siendo
la IP Tailscale del host de Michael, pero ya no se usará como dirección de
Group Replication. Se actualizaron en el repositorio:

- `report_host` de nodo2 a `100.126.57.24`.
- `group_replication_local_address` de nodo2 a `100.126.57.24:33061`.
- Las semillas de nodo1 y nodo2 para sustituir `100.109.4.122:33061` por
  `100.126.57.24:33061`.
- Las opciones explícitas `binlog_format=ROW`, `skip_name_resolve=ON` y
  `group_replication_recovery_get_public_key=ON` en nodo2.

Nodo3 todavía no se modifica; sus semillas se actualizarán antes de unirlo.

Michael confirmó en su copia de `conf/my.cnf` los tres valores esperados:

```text
report_host = 100.126.57.24
group_replication_local_address = 100.126.57.24:33061
group_replication_group_seeds = 100.113.38.39:33061,100.126.57.24:33061,100.107.61.57:33061
```

Nodo2 está listo para recrear solamente el contenedor MySQL sobre el mismo
volumen `mysql_node2_data`, compartiendo la red del contenedor Tailscale. Group
Replication permanecerá detenido durante esta recreación.

El contenedor se recreó correctamente:

```text
tailscale-node2  Running
mysql-node2      Started
```

MySQL utiliza ahora el mismo espacio de red que la interfaz Tailscale real del
contenedor. El volumen existente se conservó. Antes de intentar la unión se
comprobará que el healthcheck termine correctamente.

`docker compose ps` confirmó:

```text
mysql-node2       Up (healthy)
tailscale-node2   Up, puertos 3306 y 33061 publicados
prometheus-node2  Up
```

La nueva topología está estable. Antes de unir nodo2 se actualizarán también
las semillas activas del MySQL nodo1, porque el proceso nodo1 fue iniciado antes
del cambio de `100.109.4.122` a `100.126.57.24`.

Nodo1 actualizó en caliente `group_replication_group_seeds` y la consulta de
verificación devolvió:

```text
100.113.38.39:33061,100.126.57.24:33061,100.107.61.57:33061
```

El grupo de nodo1 permaneció activo. Falta comprobar en nodo2 los valores
efectivos, el canal de recuperación y su GTID antes del nuevo intento de unión.

La validación final de nodo2 confirmó:

```text
report_host:                     100.126.57.24
group_name:                      c395e8af-d580-4d6c-8574-a629027f1379
local_address:                   100.126.57.24:33061
group_seeds:                     100.113.38.39, 100.126.57.24, 100.107.61.57
recovery channel/user:           group_replication_recovery / repl
gtid_executed:                   vacío
```

Nodo2 cumple todos los requisitos previos y está listo para ejecutar
`START GROUP_REPLICATION` sin `bootstrap_group`.

### Intento con Tailscale dentro de Docker Desktop

Aunque nodo2 ya utilizaba una interfaz Tailscale real, el nuevo intento de
`START GROUP_REPLICATION` volvió a terminar con:

```text
ERROR 2013 (HY000): Lost connection to MySQL server during query
```

La configuración, recuperación, GTID y red habían sido validados previamente.
No se repetirá el comando hasta revisar el log de este intento. Si vuelve a
aparecer `buffer overflow` y `signal 6`, quedará confirmado que el aborto es
reproducible en el binario MySQL 8.4.11 y no depende de la antigua red bridge.

El filtro final confirmó nuevamente:

```text
THD_certifier_broadcast started
buffer overflow detected
mysqld got signal 6
```

El fallo es reproducible con XCom tanto en la red bridge anterior como sobre
la interfaz Tailscale real. La imagen oficial `mysql:8.4` continúa publicando
MySQL 8.4.11 y Docker Hub no ofrece todavía una etiqueta oficial 8.4.12. No se
hará un cambio de versión improvisado.

La solución seleccionada es migrar el grupo completo a
`group_replication_communication_stack=MYSQL`. Esta pila está soportada por
MySQL, admite namespaces de red y evita la implementación XCom donde ocurre el
aborto. Como solo nodo1 está `ONLINE`, se realizará un reinicio controlado del
grupo conservando su volumen y datos. El usuario `repl` debe recibir primero
`CONNECTION_ADMIN`, `BACKUP_ADMIN` y `GROUP_REPLICATION_STREAM`, sin registrar
estos cambios en el binary log.

### Alternativa evaluada y descartada

Se evaluó agregar `relay-log=mysql-node2-relay-bin` y ampliar
`group_replication_ip_allowlist` con `127.0.0.1`. Definir un nombre estable para
el relay log es una mejora válida y elimina la advertencia sobre cambios de
hostname, pero esa advertencia no provoca el aborto: MySQL alcanza el hilo
certificador antes de terminar con `signal 6`.

Agregar `127.0.0.1` al allowlist tampoco deshabilita IPv6 ni obliga a XCom a
usar exclusivamente IPv4. El propio log indica que GCS añade obligatoriamente
localhost IPv4 e IPv6. Por tanto, esos ajustes pueden incorporarse como higiene
de configuración, pero no se utilizarán como solución al `buffer overflow`.
La migración soportada a la pila `MYSQL` evita directamente la implementación
XCom afectada.

### Permisos preparados en nodo1 para la pila MYSQL

En nodo1 se otorgaron localmente, con `SQL_LOG_BIN=0`, los privilegios que la
pila de comunicación `MYSQL` necesita para el usuario de recuperación. La
salida de `SHOW GRANTS FOR 'repl'@'%'` confirmó:

```text
GRANT REPLICATION SLAVE ON *.* TO `repl`@`%`
GRANT BACKUP_ADMIN,CONNECTION_ADMIN,GROUP_REPLICATION_STREAM ON *.* TO `repl`@`%`
```

El cambio no se escribió en el binary log. Nodo1 conserva sus datos y continúa
siendo el único miembro `ONLINE`; todavía no se ha detenido ni migrado el grupo.

La verificación equivalente en nodo2 no devolvió filas para `repl` en
`mysql.user`. Esto confirma que el nombre estaba guardado en el canal
`group_replication_recovery`, pero la cuenta local aún no existía. Antes de
migrar el grupo se debe crear `repl@'%'` localmente en nodo2 con la misma
contraseña privada del canal y los cuatro privilegios requeridos.

La cuenta fue creada posteriormente en nodo2 con `SQL_LOG_BIN=0`. La salida de
`SHOW GRANTS` confirmó `REPLICATION SLAVE`, `BACKUP_ADMIN`, `CONNECTION_ADMIN`
y `GROUP_REPLICATION_STREAM`. La contraseña no se documenta en este archivo.

Nodo1 también fue normalizado localmente con `SQL_LOG_BIN=0`. La consulta de
verificación devolvió `repl | % | caching_sha2_password`, por lo que nodo1 y
nodo2 ya comparten el mismo usuario y método de autenticación para la migración.

Los archivos `my.cnf` de nodo1 y nodo2 quedaron preparados para la migración:

```text
group_replication_communication_stack = MYSQL
nodo1 local_address = 100.113.38.39:3306
nodo2 local_address = 100.126.57.24:3306
seeds = 100.113.38.39:3306,100.126.57.24:3306,100.107.61.57:3306
```

El allowlist de XCom fue retirado porque no se utiliza con la pila `MYSQL`.
Estos valores todavía no estarán activos hasta recrear los contenedores.

### Reinicio controlado para activar la pila MYSQL

Después de preparar usuarios y configuraciones, se ejecutó
`STOP GROUP_REPLICATION` en nodo1. El comando terminó sin errores. Solamente se
detuvo el grupo; el contenedor, la base `data_bugs` y el volumen persistente no
fueron eliminados.

El contenedor `mysql-node1` fue recreado correctamente mediante Compose para
cargar el nuevo archivo de configuración, conservando el volumen
`mysql_node1_data`. Antes del bootstrap se debe comprobar su estado de salud y
los valores efectivos de la pila de comunicación.

`docker compose ps` confirmó posteriormente `mysql-node1` en estado
`Up (healthy)`, sin ciclo de reinicios.

La consulta de variables efectivas confirmó la pila `MYSQL`, la dirección local
`100.113.38.39:3306` y las tres semillas sobre el puerto `3306`. También se
confirmó que la base `data_bugs` continúa presente después de la recreación.

El primer intento de bootstrap con la pila `MYSQL` devolvió `ERROR 3092`: el
servidor indicó que aún no estaba configurado correctamente para ser miembro
activo. No se repitió el arranque. Se ejecutó explícitamente
`SET GLOBAL group_replication_bootstrap_group=OFF` y la consulta devolvió `0`,
por lo que no quedó habilitado el modo bootstrap. El siguiente diagnóstico se
hará sobre el log de este intento.

El log mostró que la pila y el hilo certificador sí comenzaron, pero la pila
`MYSQL` no pudo establecer su conexión cliente local hacia
`100.113.38.39:3306` (`MY-013780`). GCS repitió la prueba de conectividad hasta
agotar el tiempo y abandonó el grupo. No fue un `buffer overflow` ni un aborto
del servidor. Se debe distinguir ahora entre un fallo de alcance de esa
dirección y un fallo de autenticación del usuario de recuperación.

La conexión directa desde el contenedor hacia `100.113.38.39:3306` usando
`repl`, solicitud interactiva de contraseña y `ssl-mode=PREFERRED` devolvió
`conexion = 1`. Esto confirma que la dirección local escucha, la ruta funciona
y la cuenta acepta la contraseña compartida. La causa probable queda limitada
a la credencial que estaba almacenada previamente en el canal
`group_replication_recovery`.

El primer intento de regrabar el canal devolvió `ERROR 3139` porque incluyó
`GET_SOURCE_PUBLIC_KEY=1` en `CHANGE REPLICATION SOURCE`. No se modificó el
canal. Para Group Replication esta opción ya está cubierta por
`group_replication_recovery_get_public_key=ON`; el cambio del canal se repite
únicamente con `SOURCE_USER` y `SOURCE_PASSWORD`.

El cambio corregido, sin `GET_SOURCE_PUBLIC_KEY`, terminó correctamente. La
consulta posterior confirmó el canal `group_replication_recovery` con el
usuario `repl`. La contraseña almacenada no se muestra ni se documenta.

El segundo bootstrap de nodo1 terminó correctamente después de actualizar el
canal. Se desactivó inmediatamente el modo bootstrap y la evidencia final fue:

```text
bootstrap:             0
communication_stack:   MYSQL
MEMBER_HOST:            100.113.38.39
MEMBER_PORT:            3306
MEMBER_STATE:           ONLINE
MEMBER_ROLE:            PRIMARY
```

El grupo está formado de nuevo con un miembro. Los demás nodos deben unirse sin
activar `group_replication_bootstrap_group`.

Desde el contenedor `mysql-node2`, compartiendo la red del sidecar Tailscale,
se realizó una conexión MySQL hacia `100.113.38.39:3306` con el usuario de
recuperación. `SELECT 1` devolvió `1`; nodo2 puede alcanzar y autenticarse
contra nodo1 mediante el mismo camino que utilizará Group Replication.

La verificación del archivo local de Michael mostró que aún conservaba las
direcciones XCom en `33061` y no incluía
`group_replication_communication_stack=MYSQL`. No se reinició el contenedor con
ese archivo. Se debe actualizar primero ese `my.cnf` local a la configuración
ya preparada en el repositorio de nodo1.

Michael corrigió su archivo local y la verificación confirmó la pila `MYSQL`,
la dirección local `100.126.57.24:3306` y las tres semillas en el puerto
`3306`. Nodo2 quedó listo para recrear únicamente su contenedor MySQL,
conservando el sidecar Tailscale y el volumen nombrado.

Compose recreó `mysql-node2` correctamente mientras `tailscale-node2`
permaneció en ejecución. No se eliminó ningún volumen y todavía no se ejecutó
`START GROUP_REPLICATION` en nodo2.

La comprobación posterior mostró `mysql-node2` en estado `Up (healthy)`, sin
ciclo de reinicios después de activar el nuevo archivo de configuración.

En nodo2 se regrabaron correctamente las credenciales del canal sin usar
`GET_SOURCE_PUBLIC_KEY` en la sentencia. Las variables efectivas confirmaron
`MYSQL`, `100.126.57.24:3306`, las tres semillas en `3306` y el canal
`group_replication_recovery` con el usuario `repl`.

La prueba de conexión local de nodo2 hacia `100.126.57.24:3306`, usando el
usuario de recuperación, devolvió `conexion = 1`. Esto valida que la pila
`MYSQL` puede abrir su conexión propia dentro del namespace del sidecar
Tailscale. Nodo2 quedó listo para unirse al grupo sin bootstrap.

`START GROUP_REPLICATION` en nodo2 terminó sin errores y la vista del grupo
mostró nodo1 `ONLINE` y nodo2 `RECOVERING`, ambos con rol `PRIMARY` por tratarse
de un grupo multi-primary. El estado `RECOVERING` indica que nodo2 está
recibiendo las transacciones faltantes; se debe esperar a `ONLINE` antes de
hacer pruebas de escritura.

La consulta posterior confirmó la recuperación completa:

```text
100.113.38.39:3306  ONLINE  PRIMARY
100.126.57.24:3306  ONLINE  PRIMARY
```

Nodo1 y nodo2 forman ahora un grupo multi-primary funcional sobre la pila
`MYSQL`. Falta preparar y unir nodo3, y después ejecutar las pruebas CRUD.

### Auditoría inicial de nodo3

Antes de modificar su volumen, Carlos ejecutó una consulta de solo lectura. El
resultado fue:

```text
gtid_executed: cf1a5e24-afec-11f1-b257-b630c78a6f0b:1-3
bases: data_bugs, information_schema, mysql, performance_schema, sys
```

Nodo3 tiene tres transacciones GTID propias que no pertenecen todavía al grupo
de nodo1/nodo2. No se debe ejecutar `START GROUP_REPLICATION`, borrar el
volumen ni reinicializarlo hasta comprobar si `data_bugs` contiene tablas o
datos que deban conservarse. El siguiente paso será una consulta de inventario
y, si esos datos no son necesarios, se preparará un volumen nuevo conservando
el volumen anterior como respaldo recuperable.

Una auditoría posterior de nodo3 mostró que su volumen fue reinicializado o
limpiado después de aquella observación: `gtid_executed` y `gtid_purged`
aparecen vacíos, y `data_bugs` no contiene tablas. Este resultado más reciente
es el que se usará para la incorporación al grupo. También confirmó:

```text
MySQL:                       8.4.11 healthy
communication_stack:         MYSQL
local_address:               100.107.61.57:3306
bootstrap:                   0
estado:                      OFFLINE
usuario local:               repl@% / caching_sha2_password
canal de recuperación:       repl_user
```

La cuenta `repl` de nodo3 todavía carece de `CONNECTION_ADMIN` y
`GROUP_REPLICATION_STREAM`, el canal usa un usuario distinto (`repl_user`) y
las semillas contienen tanto la IP antigua de nodo2 (`100.109.4.122`) como la
IP del sidecar (`100.126.57.24`). Los intentos prematuros de
`START GROUP_REPLICATION` fallaron sin formar grupo ni activar bootstrap. Estas
correcciones se harán después de recuperar nodo1/nodo2.

Después de recuperar nodo1 y nodo2, la conectividad desde nodo1 hacia nodo3 se
validó nuevamente:

```text
tailscale ping 100.107.61.57: pong
TCP 100.107.61.57:3306:       succeeded
```

El mensaje posterior de Zsh `no matches found: [tcp/*]` no fue un fallo de
red: ocurrió al pegar accidentalmente en la terminal una línea que era salida
de `nc`. Las dos pruebas reales finalizaron correctamente.

Carlos también comprobó el archivo `my.cnf` persistente de nodo3. Ya contiene
la configuración correcta que sobrevivirá a una recreación del contenedor:

```text
communication_stack: MYSQL
local_address:       100.107.61.57:3306
group_seeds:         100.113.38.39:3306,100.126.57.24:3306,100.107.61.57:3306
```

No aparecen la IP antigua `100.109.4.122` ni el puerto XCOM `33061`.

La verificación inmediatamente anterior a preparar nodo3 confirmó:

```text
gtid_executed:                vacío
gtid_purged:                  vacío
miembro local:                100.107.61.57 / OFFLINE
canal de recuperación:        repl_user
permisos dinámicos de repl:   BACKUP_ADMIN
```

Por tanto, nodo3 no tiene transacciones propias que puedan divergir del grupo y
es seguro configurar sus credenciales de recuperación. Antes de unirlo se debe
cambiar el canal a `repl` y conceder `CONNECTION_ADMIN` y
`GROUP_REPLICATION_STREAM`, manteniendo el binlog de la sesión desactivado para
que esta preparación local no cree GTID nuevos.

La variable `group_replication_recovery_get_public_key` se comprobó activa con
valor `1`. Esto permite que el canal de recuperación autentique al usuario
`repl` con `caching_sha2_password` sin incluir `GET_SOURCE_PUBLIC_KEY` dentro de
`CHANGE REPLICATION SOURCE`, combinación que anteriormente produjo el error
3139.

La preparación del usuario y del canal se completó correctamente. La evidencia
final de nodo3 muestra:

```text
repl@%: REPLICATION SLAVE, REPLICATION CLIENT
repl@%: BACKUP_ADMIN, CONNECTION_ADMIN, GROUP_REPLICATION_STREAM
canal group_replication_recovery: repl
```

Con esto quedan alineados el usuario y los privilegios de recuperación. Antes
de iniciar Group Replication solo falta validar desde el contenedor de nodo3 la
autenticación directa contra nodo1 y nodo2.

Las dos conexiones de recuperación se validaron con el usuario `repl` y la
contraseña compartida:

```text
nodo3 -> 100.113.38.39:3306: conexión 1
nodo3 -> 100.126.57.24:3306: conexión 1
```

Nodo3 puede autenticarse contra cualquiera de los dos donantes. Quedó listo
para ejecutar `START GROUP_REPLICATION` sin bootstrap.

### Incorporación exitosa de nodo3

Nodo3 ejecutó una sola vez `START GROUP_REPLICATION`, sin bootstrap. La vista
de membresía confirmó simultáneamente:

```text
100.113.38.39:3306  ONLINE  PRIMARY
100.107.61.57:3306  ONLINE  PRIMARY
100.126.57.24:3306  ONLINE  PRIMARY
```

El clúster de tres miembros quedó formado correctamente. `PRIMARY` en nodo3 es
el rol normal que reporta Group Replication en modo multi-primary; todavía se
debe activar y validar `super_read_only` para que opere como nodo de
lectura/contingencia según el diseño del proyecto.

La protección de nodo3 se activó después de incorporarlo y quedó validada:

```text
read_only:       1
super_read_only: 1
```

Aunque la membresía continúe mostrando el rol `PRIMARY` por utilizar modo
multi-primary, estas variables bloquean las escrituras directas de clientes en
nodo3 y permiten que los hilos de replicación sigan aplicando transacciones.
La protección debe comprobarse nuevamente después de cada reinicio o unión al
grupo.

La prueba de escritura directa se realizó intentando crear
`prueba_no_escritura_nodo3`. MySQL respondió correctamente:

```text
ERROR 1290 (HY000): The MySQL server is running with the --super-read-only
option so it cannot execute this statement
```

La base de prueba no fue creada. Esto valida que un cliente no puede modificar
nodo3 directamente mientras funciona como contingencia.

Después de preparar la cuenta, la validación confirmó que `repl@%` tiene
`REPLICATION SLAVE`, `BACKUP_ADMIN`, `CONNECTION_ADMIN` y
`GROUP_REPLICATION_STREAM`. El canal `group_replication_recovery` también quedó
configurado para usar `repl`, sustituyendo al usuario incorrecto `repl_user`.

La preparación se completó correctamente con el binlog de sesión desactivado:

- `repl@%` usa la misma credencial privada que nodo1 y nodo2.
- Conserva `REPLICATION SLAVE` y `BACKUP_ADMIN`.
- Recibió `CONNECTION_ADMIN` y `GROUP_REPLICATION_STREAM`.
- El canal `group_replication_recovery` ahora utiliza `repl`, no `repl_user`.
- `group_replication_recovery_get_public_key` devolvió `1`.
- El binlog de la sesión volvió a activarse al terminar.

Después de estas validaciones, nodo3 se incorporó correctamente y quedó
`ONLINE` junto a los otros dos miembros.

## Próximos pasos

1. Activar y validar `super_read_only` en nodo3 para convertirlo en
   lectura/contingencia.
2. Ejecutar y documentar CRUD replicado desde nodo1 y nodo2 para la Fase 2.
3. Integrar ProxySQL o el balanceador elegido y validar conectividad completa.
4. Guardar capturas y diagrama para cerrar la evidencia de Fase 1.
5. Continuar con monitoreo, respaldo y las mejoras adicionales del plan.

`group_replication_bootstrap_group` nunca debe permanecer activo. Solo se usa
al crear el grupo inicial y se desactiva inmediatamente después.

## Continuidad, apagados y seguridad para la evaluación

### Qué persiste al apagar una computadora

- Los datos MySQL permanecen en volúmenes Docker nombrados. Un apagado normal
  no elimina las bases, usuarios, GTID ni canales de recuperación.
- Los archivos `my.cnf`, Compose y README permanecen en el repositorio local.
- El estado del sidecar Tailscale de nodo2 permanece en
  `tailscale_node2_state`, por lo que normalmente conserva `100.126.57.24`.
- `group_replication_start_on_boot=OFF` está puesto deliberadamente. Los
  contenedores pueden arrancar al volver a encender Docker, pero cada MySQL no
  se une solo al grupo. Esto evita formar grupos separados accidentalmente.

### Riesgo actual con solo dos miembros

Con nodo1 y nodo2 únicamente, la caída de cualquiera elimina la mayoría. El
miembro restante puede seguir ejecutándose, pero el grupo no debe considerarse
disponible para escrituras. Al unir nodo3 habrá tres votos y el grupo podrá
tolerar la caída de un miembro.

### Apagado temporal de nodo1 y regreso

Si nodo2 continúa encendido, nodo1 debe abandonar el grupo de forma limpia antes
de apagar Ubuntu:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "STOP GROUP_REPLICATION; SELECT @@global.group_replication_bootstrap_group;"'
```

El resultado seguro es bootstrap `0`. Después se apaga el sistema operativo de
forma normal; no se usa `docker compose down -v` ni se elimina ningún volumen.

Al volver a Ubuntu, primero se comprueba Tailscale y el contenedor:

```bash
tailscale status
cd nodes/node1
docker compose ps
```

Si `mysql-node1` no está iniciado se ejecuta `docker compose up -d`; cuando esté
`healthy` y nodo2 continúe accesible en `100.126.57.24:3306`, nodo1 se une al
grupo existente **sin bootstrap**:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION; SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE FROM performance_schema.replication_group_members;"'
```

Se esperan nuevamente dos filas `ONLINE`. Si nodo2 también se apagó o no existe
ningún grupo `ONLINE`, no se ejecuta bootstrap por prueba y error: se comparan
los GTID y se aplica la recuperación de apagado total.

### Reglas que evitan pérdida o división del grupo

1. Nunca ejecutar `docker compose down -v`, `docker volume rm` ni borrar las
   carpetas/volúmenes de datos.
2. Nunca ejecutar `rm -rf data/*`. El `fix-node.sh` de nodo2 fue sustituido por
   una versión que recrea contenedores sin borrar datos.
3. Nunca activar bootstrap en dos nodos. Si todavía existe un miembro `ONLINE`,
   los demás se unen solamente con `START GROUP_REPLICATION`.
4. Después de un apagado total, no elegir un nodo al azar: comparar
   `@@global.gtid_executed`, seleccionar el miembro más actualizado, hacer
   bootstrap una sola vez y apagar inmediatamente la bandera. Los demás se
   unen sin bootstrap.
5. Antes de una demostración, evitar escrituras simultáneas sobre las mismas
   filas desde nodo1 y nodo2; en multi-primary pueden producir conflictos.
6. Git protege configuraciones y documentación, pero no reemplaza un respaldo
   de la base. Antes de las pruebas de fallos se debe generar y verificar un
   respaldo lógico de `data_bugs`.

### Comprobación rápida antes de calificar

```bash
tailscale status
docker compose ps
```

```sql
SELECT @@global.group_replication_bootstrap_group;
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

La condición segura es bootstrap `0` y tres filas `ONLINE`. Si hubo un apagado
total y no existe ninguna fila `ONLINE`, se aplica el procedimiento de
recuperación total descrito arriba; no se ejecutan varios bootstrap por prueba
y error.

### Punto de reanudación después del apagado del 17 de septiembre

Michael apagó nodo2 y su sidecar quedó `offline`. Nodo1 se detiene con
`STOP GROUP_REPLICATION`, confirma bootstrap `OFF` y después se apaga Ubuntu.
Al iniciar la siguiente sesión:

1. Encender Tailscale, Docker y MySQL en nodo1 y nodo2; esperar ambos
   contenedores `healthy`.
2. No ejecutar todavía `START GROUP_REPLICATION` ni bootstrap.
3. Consultar `@@global.gtid_executed` en ambos nodos.
4. Si los conjuntos GTID son idénticos, hacer un único bootstrap en nodo1,
   apagar inmediatamente la bandera y unir nodo2 sin bootstrap.
5. Si un conjunto contiene completamente al otro, usar como bootstrap el nodo
   más actualizado. Si son divergentes, detenerse y reconciliar antes de formar
   el grupo.
6. Confirmar nodo1 y nodo2 `ONLINE / PRIMARY`; después continuar con la auditoría
   y preparación de nodo3.

Después del encendido, nodo1 fue comprobado en estado `healthy`, con GTID
`5248cb8e-aff2-11f1-8a74-fa8b2c2f6510:1-20`, pila `MYSQL`, bootstrap `0` y
Group Replication `OFFLINE`. Tailscale mostró a Michael conectado, pero el
dispositivo del sidecar `mysql-node2` (`100.126.57.24`) no apareció en la lista.
Antes de recuperar el grupo se debe comprobar el GTID y el estado Tailscale
interno de nodo2.

La comprobación de nodo2 confirmó que MySQL no perdió configuración ni datos:

```text
gtid_executed:        5248cb8e-aff2-11f1-8a74-fa8b2c2f6510:1-20
communication_stack:  MYSQL
local_address:        100.126.57.24:3306
bootstrap:            0
estado del grupo:     OFFLINE
```

El GTID coincide exactamente con nodo1. El único fallo real es el sidecar:
conserva `100.126.57.24`, pero `tailscale status` informa `logged out` y un
error al contactar el servidor de coordinación. La IP Tailscale del host
`100.109.4.122` y su puerto `3306` siguen accesibles. Además, un
`docker compose ps` ejecutado desde la raíz devolvió `no configuration file
provided`; esto no es desconfiguración y se corrige entrando primero a
`nodes/node2`.

Orden de recuperación: validar logs y `tailscale netcheck`, reiniciar el mismo
sidecar conservando su volumen de estado, renovar la clave solo si continúa
cerrada la sesión, confirmar nuevamente `100.126.57.24`, hacer un único
bootstrap en nodo1 y unir nodo2 sin bootstrap.

El reinicio conservó el volumen, pero el sidecar entró en ciclo de reinicio. El
log confirmó la causa definitiva: la clave de autenticación configurada ya no
es válida y Tailscale queda en `NeedsLogin/NoState`. `tailscale netcheck` había
confirmado previamente conectividad UDP y DERP, por lo que no es un fallo de
Internet. El aviso de que `tailscale0` todavía no existe es una consecuencia
normal del reinicio, no la causa. Se requiere una clave nueva de la misma
tailnet, guardada únicamente en el `.env` ignorado de Michael.

Después de reemplazar la clave privada, se recrearon únicamente
`tailscale-node2` y `mysql-node2`, conservando ambos volúmenes. El sidecar
recuperó `100.126.57.24`, MySQL volvió a `healthy` y nodo1 confirmó conexión TCP
exitosa hacia `100.126.57.24:3306`. No se inició Group Replication durante esta
recuperación.

La verificación de nodo2 confirmó el mismo GTID exacto que nodo1,
`5248cb8e-aff2-11f1-8a74-fa8b2c2f6510:1-20`, pila `MYSQL`, dirección local
`100.126.57.24:3306`, semillas correctas, bootstrap `0` y estado `OFFLINE`.
No existe divergencia. Después de renovar la clave privada del sidecar,
`tailscale-node2` recuperó la misma IP `100.126.57.24`, apareció conectado en
la tailnet y `mysql-node2` quedó `healthy`. Desde nodo1 también se comprobó que
`100.126.57.24:3306` era accesible.

### Recuperación posterior al encendido: 17 de septiembre

Con los GTID de nodo1 y nodo2 iguales y la red restablecida, se reconstruyó el
grupo haciendo **un único bootstrap en nodo1**. El procedimiento encendió la
bandera, inició Group Replication y la apagó inmediatamente incluso antes de
consultar el resultado final.

Resultado comprobado en nodo1:

```text
bootstrap:   0
MEMBER_HOST: 100.113.38.39
MEMBER_PORT: 3306
MEMBER_STATE: ONLINE
MEMBER_ROLE: PRIMARY
```

Esto confirma que nodo1 formó correctamente el grupo y que la bandera de
bootstrap no quedó activa. Después, nodo2 ejecutó solamente
`START GROUP_REPLICATION`, **sin bootstrap**, y terminó su recuperación.

Estado final comprobado después del encendido:

```text
MEMBER_HOST       MEMBER_PORT  MEMBER_STATE  MEMBER_ROLE
100.113.38.39     3306         ONLINE        PRIMARY
100.126.57.24     3306         ONLINE        PRIMARY
```

Nodo1 y nodo2 quedaron nuevamente operativos. No se requiere ninguna otra
configuración en nodo2 antes de preparar nodo3.

## Procedimiento operativo ante reinicios y fallos

Esta sección es la guía corta que se debe seguir sin improvisar durante la
evaluación.

### Caso A: encender un nodo cuando otro miembro continúa `ONLINE`

1. Confirmar Tailscale, contenedor y acceso al puerto `3306` del miembro vivo.
2. Iniciar Group Replication en el nodo que regresó **sin bootstrap**:

```bash
docker exec mysql-nodeX sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

El nodo puede aparecer brevemente como `RECOVERING`; el resultado final debe
ser `ONLINE`. Nunca se activa bootstrap mientras exista un grupo vivo.

### Caso B: todos los equipos estuvieron apagados

1. Encender Tailscale, Docker y MySQL, pero no iniciar Group Replication.
2. Consultar el GTID en cada nodo candidato:

```bash
docker exec mysql-nodeX sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@global.gtid_executed;"'
```

3. Elegir el nodo con el conjunto GTID más actualizado. Si nodo1 y nodo2 tienen
   el mismo GTID, se usa nodo1. Si son divergentes, detenerse y reconciliarlos.
4. Formar el grupo una sola vez en el nodo elegido y garantizar que la bandera
   vuelva a `OFF`:

```bash
docker exec mysql-node1 sh -c '
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=ON;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"
resultado=$?
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=OFF;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
"
exit "$resultado"
'
```

Se espera `bootstrap = 0` y el nodo elegido `ONLINE`. Los demás nodos se unen
después con el comando del caso A, nunca con otro bootstrap.

### Caso C: nodo2 está `healthy`, pero su Tailscale está desconectado

Comprobar primero el estado y los logs del sidecar:

```bash
docker exec tailscale-node2 tailscale status
docker logs tailscale-node2 --since 10m --tail 120
```

Si el log indica una clave inválida, se genera una nueva clave de la misma
tailnet, se guarda solamente como `TS_AUTHKEY` en el `.env` ignorado de nodo2 y
se recrean los dos servicios sin eliminar volúmenes:

```bash
docker compose up -d --force-recreate tailscale-node2 mysql-node2
docker exec tailscale-node2 tailscale ip -4
docker compose ps
```

La IP esperada es `100.126.57.24` y MySQL debe quedar `healthy`. Nunca se pega
la clave en el README ni se ejecuta `docker compose down -v`.

Una clave reutilizable puede autenticar más de una vez, pero no es permanente:
Tailscale permite asignarle una vigencia máxima y también puede ser revocada.
Con `TS_AUTH_ONCE=true` y el volumen `tailscale_node2_state` persistente, un
reinicio normal reutiliza la identidad guardada y no debería consumir ni volver
a solicitar la clave. Si nodo2 vuelve a desconectarse, primero se revisan
`tailscale status` y los logs; solo se reemplaza `TS_AUTHKEY` cuando el mensaje
confirme clave inválida, expirada o sesión perdida.

Después de recuperar Tailscale, se confirma desde nodo1 que
`100.126.57.24:3306` sea accesible. Si nodo1 todavía pertenece a un grupo
`ONLINE`, nodo2 regresa **sin bootstrap**:

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Se espera que nodo2 pase de `RECOVERING` a `ONLINE`. Si no queda ningún miembro
`ONLINE`, no se ejecuta este paso a ciegas: primero se comparan los GTID y se
aplica el procedimiento del caso B, con un único bootstrap.

### Verificación final después de cualquier recuperación

```sql
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

La condición correcta es `bootstrap = 0` y todos los miembros esperados en
`ONLINE`. `RECOVERING` es transitorio; `OFFLINE`, `ERROR` o una fila `NULL`
requieren revisar los logs antes de continuar.
