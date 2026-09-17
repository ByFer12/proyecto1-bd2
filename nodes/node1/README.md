# Nodo 1 — Ubuntu

Este directorio contiene la instancia MySQL 8.4 de Byron, utilizada como nodo
inicial del grupo y fuente del dataset `data_bugs`.

## Estado actual

- Contenedor: `mysql-node1`.
- Motor validado: MySQL 8.4.11.
- `server_id`: `1`.
- IP Tailscale: `100.113.38.39`.
- Puerto MySQL: `3306`.
- Comunicación de Group Replication: pila `MYSQL` sobre el puerto `3306`.
- Group Replication: nodo1 y nodo2 validados `ONLINE / PRIMARY`; nodo3 pendiente.
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
- La comprobación definitiva de nodo3 por `3306` sigue pendiente.

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
- [~] Mecanismo de replicación configurado: nodo1 y nodo2 están `ONLINE`; falta nodo3.
- [x] Nodo1 y nodo2 configurados para lectura/escritura en modo multi-primary.
- [ ] Nodo3 configurado y validado como lectura/contingencia.
- [ ] Proxy o balanceador integrado.
- [~] Conectividad validada entre nodo1 y nodo2; falta validación final con nodo3 y proxy.
- [ ] Tres nodos disponibles simultáneamente.

**Avance estimado de Fase 1: 50 %** (3 puntos completos, 2 parciales y 3
pendientes). El núcleo de Group Replication está en **2 de 3 nodos ONLINE**.
Las pruebas CRUD pertenecen a la Fase 2 y todavía no se contabilizan como
completadas.

Evidencia técnica ya obtenida:

- UUID, pila `MYSQL`, semillas y modo multi-primary coincidentes en nodo1/nodo2.
- Canales de recuperación y usuario `repl` preparados en nodo1/nodo2.
- Nodo1 `100.113.38.39:3306` y nodo2 `100.126.57.24:3306` simultáneamente
  `ONLINE / PRIMARY`.
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

## Próximos pasos

1. Revisar GTID y datos existentes en nodo3 antes de tocar su volumen.
2. Migrar nodo3 a pila `MYSQL`, crear su usuario de recuperación y unirlo sin
   bootstrap.
3. Configurar nodo3 como lectura/contingencia y confirmar tres miembros
   `ONLINE`.
4. Integrar ProxySQL o el balanceador elegido y validar conectividad completa.
5. Guardar capturas y diagrama para cerrar la evidencia de Fase 1.
6. Ejecutar y documentar CRUD desde nodo1 y nodo2 para la Fase 2.

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


soy nodo 1 y recien ejecute este comando para antes de irme y este fue su resultado:
fer@Torres-PC  ~/Descargas/bases2/proyecto-1-db2/nodes/node1  ↰ main ±  docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
STOP GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
"'
mysql: [Warning] Using a password on the command line interface can be insecure.
