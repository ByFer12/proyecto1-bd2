# Inicio y recuperación después de apagar los equipos

## Propósito

Esta guía deja el clúster listo para continuar las Fases 2–5 después de que una
o varias computadoras se apaguen. Primero se identifica el escenario y después
se ejecuta únicamente la ruta correspondiente.

Responsables iniciales:

- Byron: nodo1, decisión de bootstrap y ProxySQL.
- Michael: nodo2, sidecar Tailscale y MySQL nodo2.
- Carlos: nodo3 Windows y protección de solo lectura.

Los roles pueden rotarse para aprender, salvo los comandos locales de Docker,
que debe ejecutarlos quien controla físicamente cada computadora.

## Reglas que evitan perder el grupo

1. No activar bootstrap antes de comprobar todos los nodos.
2. Si existe un grupo operativo con algún miembro `ONLINE`, los demás hacen
   solamente `START GROUP_REPLICATION`.
3. Si todos están `OFFLINE`, comparar GTID antes de elegir el nodo de bootstrap.
4. Solo un nodo hace bootstrap y debe volver a dejarlo en `OFF`.
5. No ejecutar `docker compose down -v`, `docker volume rm` ni borrar `data/*`.
6. No cambiar `my.cnf` para resolver un simple apagado.
7. Nodo3 vuelve a `super_read_only=ON` después de cada reinicio o JOIN.
8. Group Replication utiliza pila `MYSQL` y puerto `3306`, no XCOM/33061.

## A. Qué ocurre al apagar los equipos

`STOP GROUP_REPLICATION` es un cierre ordenado **recomendado**, pero no es un
requisito para que el volumen conserve la base de datos. Si alguien ya apagó
su equipo sin ejecutarlo, no debe encenderlo nuevamente solo para hacer STOP.

### A.1 Posibles formas de apagado

| Situación | Qué ocurre | Consecuencia al regresar |
|---|---|---|
| Ejecuta `STOP GROUP_REPLICATION` y luego apaga normalmente | El nodo anuncia que abandona el grupo antes de cerrar MySQL. | Recuperación más predecible y logs más limpios. |
| Apaga normalmente sin ejecutar STOP | Docker y el sistema operativo detienen MySQL; los otros miembros detectan su salida. | Los datos persisten; al volver se revisan GTID y membresía. |
| Se traba, pierde energía o se fuerza el apagado | El nodo desaparece sin despedirse y los demás esperan hasta declararlo ausente. | MySQL puede ejecutar recuperación de InnoDB al iniciar; hay que revisar logs y estado. |
| Algunos ejecutan STOP y otros apagan directamente | Los que hicieron STOP salen ordenadamente; los demás son detectados como ausentes. | No crea dos grupos ni borra datos; se aplica el diagnóstico normal al regresar. |

Una transacción que ya fue confirmada y replicada debe permanecer en los
volúmenes. Una operación que estaba en curso y nunca recibió confirmación
puede ser revertida durante la recuperación. Por eso no se apaga mientras se
está ejecutando una prueba CRUD.

Ejecutar `STOP GROUP_REPLICATION`:

- no detiene el servidor MySQL;
- no apaga Docker ni la computadora;
- no borra tablas, GTID ni configuraciones;
- únicamente retira esa instancia del grupo actual.

### A.2 Efecto sobre el quórum

Si sale uno de tres nodos, los otros dos conservan mayoría y normalmente siguen
`ONLINE`. Cuando sale un segundo nodo, queda uno solo y ya no existe mayoría;
ese último miembro puede quedar sin grupo operativo para evitar escrituras
inseguras. Cuando finalmente todos se apagan, no queda ningún grupo activo.

Al encender, `group_replication_start_on_boot=OFF` deja MySQL funcionando pero
Group Replication detenido. Esto es intencional: evita que varios nodos formen
grupos independientes automáticamente.

### A.3 Apagado ordenado recomendado cuando los tres están activos

Si todavía es posible coordinarse, el orden recomendado es:

```text
1. Nodo3 ejecuta STOP GROUP_REPLICATION.
2. Nodo2 ejecuta STOP GROUP_REPLICATION.
3. Nodo1, como último miembro, ejecuta STOP GROUP_REPLICATION.
4. Los tres apagan normalmente sus sistemas operativos.
```

Esto retira primero los nodos secundarios y deja una única referencia hasta el
final. Si un equipo ya se apagó, no se intenta encenderlo solo para ejecutar
`STOP`; se continúa con los miembros que todavía están disponibles.

#### A.3.1 Carlos detiene Group Replication en nodo3

Carlos abre MySQL sin escribir la contraseña en PowerShell:

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p
```

Dentro de MySQL:

```sql
STOP GROUP_REPLICATION;
SET GLOBAL super_read_only=ON;
SELECT @@global.group_replication_bootstrap_group,
       @@global.read_only,
       @@global.super_read_only;
```

Sirve para: retirar nodo3 ordenadamente y dejarlo protegido.

Resultado esperado: comandos exitosos, `bootstrap=0`, `read_only=1` y
`super_read_only=1`.

#### A.3.2 Michael detiene nodo2 si todavía está encendido

Si nodo2 ya está apagado, este paso se omite. Si continúa encendido, Michael lo
retira antes que nodo1:

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
STOP GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
"'
```

Sirve para: retirar nodo2 ordenadamente sin borrar sus datos. Esperado:
`bootstrap=0`.

#### A.3.3 Byron detiene Group Replication en nodo1

Después de que los otros nodos disponibles confirmen su salida:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
STOP GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
"'
```

Sirve para: cerrar el último miembro de forma explícita y garantizar que
bootstrap no quede accidentalmente activo.

Resultado esperado: `bootstrap=0`, sin error fatal.

#### A.3.4 Apagar normalmente

Después pueden cerrar aplicaciones y apagar los sistemas operativos de forma
normal. Los datos permanecen en volúmenes Docker; no es necesario borrarlos ni
recrear contenedores.

Al regresar, todos estarán probablemente `OFFLINE` de Group Replication. Eso
es esperado. Se comienza siempre en la sección B, sin asumir que el apagado
anterior fue ordenado.

## B. Arranque base de las tres computadoras

Los tres encienden Tailscale y Docker antes de formar el grupo.

### B.1 Byron — nodo1 Ubuntu

Desde `nodes/node1/`:

```bash
tailscale ip -4
tailscale status
docker compose up -d
docker compose ps
```

Sirve para: recuperar la IP `.39`, iniciar MySQL sin borrar el volumen y
comprobar que queda `healthy`.

Resultado esperado:

```text
100.113.38.39
mysql-node1 ... healthy
```

Si MySQL todavía dice `health: starting`, esperar y repetir
`docker compose ps`; no reiniciarlo repetidamente.

### B.2 Michael — nodo2 Debian con Docker Desktop

Desde `nodes/node2/`:

```bash
docker context show
docker compose up -d
docker compose ps
docker exec tailscale-node2 tailscale ip -4
docker exec tailscale-node2 tailscale status
```

Sirve para: iniciar el sidecar Tailscale y MySQL en el mismo espacio de red.

Resultado esperado:

```text
contexto: desktop-linux
tailscale-node2: Up
mysql-node2: healthy
IP: 100.126.57.24
```

La IP `.122` es el Tailscale del host de Michael; MySQL del proyecto utiliza
la IP `.24` del sidecar.

### B.3 Carlos — nodo3 Windows

Desde la carpeta que contiene su `docker-compose.yml`:

```powershell
tailscale ip -4
tailscale status
docker compose up -d
docker compose ps
```

Sirve para: recuperar la IP `.57` e iniciar `mysql-nodo3` con su volumen.

Resultado esperado: Tailscale `100.107.61.57` y MySQL saludable.

## C. Comprobar red antes del grupo

### C.1 Byron comprueba nodo2 y nodo3

```bash
tailscale ping 100.126.57.24
tailscale ping 100.107.61.57
nc -vz -w 5 100.126.57.24 3306
nc -vz -w 5 100.107.61.57 3306
```

Sirve para: separar problemas de red de problemas de Group Replication.

Esperado: `pong` y `succeeded` para ambos nodos.

Interpretación:

- `refused`: la máquina responde, pero MySQL no está escuchando.
- `timed out`: equipo, Tailscale, firewall o sidecar no disponible.
- `no matching peer`: IP/tailnet incorrectos.

No se continúa hasta alcanzar los dos puertos.

## D. Diagnóstico obligatorio antes de START o bootstrap

Cada integrante obtiene dos datos: GTID y membresía actual.

### D.1 Byron — nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.gtid_executed;
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

### D.2 Michael — nodo2

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.gtid_executed;
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

### D.3 Carlos — nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@global.gtid_executed; SELECT @@global.group_replication_bootstrap_group AS bootstrap; SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE FROM performance_schema.replication_group_members;"
```

Sirve para: decidir si hay un grupo vivo y cuál nodo tiene más transacciones.

Todos envían al chat únicamente GTID, bootstrap y membresía; nunca la
contraseña.

## E. Elegir exactamente un escenario

### Escenario 1 — Los tres aparecen `OFFLINE`

Este será el escenario normal después del apagado ordenado de esta noche.

1. Comparar los GTID de los tres.
2. Si son idénticos, elegir nodo1 para bootstrap.
3. Si son diferentes, no improvisar: comprobar cuál contiene a los otros dos.

#### Cómo comparar GTID diferentes sin adivinar

Byron abre MySQL sin exponer su contraseña:

```bash
docker exec -it mysql-node1 mysql -uroot -p
```

Después copia únicamente los GTID informados por nodo2 y nodo3 dentro de esta
consulta:

```sql
SELECT GTID_SUBSET('GTID_COMPLETO_NODO2', @@global.gtid_executed)
       AS nodo2_esta_en_nodo1,
       GTID_SUBSET('GTID_COMPLETO_NODO3', @@global.gtid_executed)
       AS nodo3_esta_en_nodo1;
```

Sirve para: comprobar si nodo1 contiene todas las transacciones de ambos
nodos. Si devuelve `1` y `1`, nodo1 puede ser el candidato de bootstrap. Si no,
se hace la comparación equivalente en el otro candidato.

Si ningún nodo contiene completamente a los otros dos, los conjuntos son
divergentes: **no se hace bootstrap ni se borran volúmenes**. Se guardan los
tres GTID y los logs para resolver la divergencia de forma controlada.

#### E.1.1 Byron forma el grupo únicamente en nodo1

```bash
docker exec mysql-node1 sh -c '
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=ON;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"
cmd_rc=$?
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SET GLOBAL group_replication_bootstrap_group=OFF;"
mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.group_replication_bootstrap_group AS bootstrap;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"
exit "$cmd_rc"
'
```

Sirve para: crear una única vista inicial del grupo y desactivar bootstrap aun
si el START falla.

Resultado esperado: `bootstrap=0` y nodo1 `.39 ONLINE`.

#### E.1.2 Michael une nodo2

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Sirve para: unir nodo2 al grupo existente. Nunca activa bootstrap.

Resultado: nodo2 puede aparecer `RECOVERING`; se espera hasta `ONLINE`.

#### E.1.3 Carlos une y protege nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p
```

Dentro de MySQL:

```sql
START GROUP_REPLICATION;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;

SET GLOBAL super_read_only=ON;
SELECT @@global.read_only,@@global.super_read_only;
```

Resultado: tres `ONLINE` y nodo3 `1/1`.

### Escenario 2 — Al menos dos miembros mantienen el grupo `ONLINE`

Ejemplo: nodo1 se apagó, pero nodo2 y nodo3 siguieron encendidos.

No hacer bootstrap. En el nodo recuperado se ejecuta solamente:

```sql
START GROUP_REPLICATION;
```

Después se consulta la membresía y se espera `ONLINE`.

Sirve para: reincorporarse a la vista existente y recuperar las transacciones
faltantes mediante GTID.

### Escenario 3 — Nodo1 y nodo2 se apagaron, nodo3 quedó encendido

Primero Carlos consulta la membresía. Hay dos posibilidades.

#### E.3.A Nodo3 todavía pertenece a una vista recuperable

1. Encender nodo1.
2. No hacer bootstrap.
3. Byron ejecuta una vez `START GROUP_REPLICATION` en nodo1.
4. Si nodo1 y nodo3 quedan `ONLINE`, se recuperó el quórum.
5. Michael une nodo2 cuando esté disponible.
6. Carlos vuelve a activar `super_read_only=ON`.

#### E.3.B Nodo3 está `ERROR/OFFLINE` o nodo1 no puede unirse

1. No repetir START indefinidamente.
2. Comparar GTID de nodo1 y nodo3.
3. Confirmar que no existe ningún miembro `ONLINE`.
4. Aplicar el Escenario 1: un único bootstrap en el nodo con GTID más completo.
5. Unir los otros nodos sin bootstrap.

Aunque nodo3 pierda quórum, sus datos siguen disponibles para `SELECT` directo;
las escrituras deben permanecer bloqueadas.

### Escenario 4 — Solo nodo1 estaba apagado

Si nodo2 y nodo3 aparecen `ONLINE`, Byron inicia MySQL y ejecuta solamente:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"'
```

No usa bootstrap porque el grupo ya existe.

### Escenario 5 — Solo nodo2 estaba apagado

Michael recupera sidecar/MySQL y, si nodo1/nodo3 siguen `ONLINE`, ejecuta:

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"'
```

### Escenario 6 — Solo nodo3 estaba apagado

Carlos inicia el contenedor, ejecuta `START GROUP_REPLICATION`, espera
`ONLINE` y después ejecuta `SET GLOBAL super_read_only=ON`.

## F. Caso especial: nodo2 no recupera Tailscale

Michael diagnostica:

```bash
docker inspect -f '{{.State.Status}} reinicios={{.RestartCount}} salida={{.State.ExitCode}} error={{.State.Error}}' tailscale-node2
docker logs tailscale-node2 --since 10m --tail 120
docker exec tailscale-node2 tailscale status
```

Sirve para: diferenciar un arranque lento de una clave inválida o sesión
perdida.

### F.1 Dice `starting`

Esperar uno o dos minutos y repetir `tailscale status`. No recrear
inmediatamente.

### F.2 Dice `invalid key`, `NeedsLogin` o `You are logged out`

1. Generar una clave Tailscale reutilizable/no efímera en el tailnet correcto.
2. Michael actualiza `TS_AUTHKEY` en `nodes/node2/.env`.
3. Confirmar que `.env` está ignorado:

   ```bash
   git check-ignore -v .env
   ```

4. Recrear sin borrar volúmenes:

   ```bash
   docker compose up -d --force-recreate tailscale-node2 mysql-node2
   docker exec tailscale-node2 tailscale ip -4
   docker exec tailscale-node2 tailscale status
   docker compose ps
   ```

Resultado esperado: recuperar exactamente `100.126.57.24` y MySQL `healthy`.

Si recibe otra IP, no iniciar Group Replication: primero hay que actualizar de
forma coordinada direcciones/semillas, o recuperar la identidad persistente.

### F.3 MySQL reinicia con errores de permisos

Comprobar montajes:

```bash
docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{println}}{{end}}' mysql-node2
```

Esperado:

```text
volume node2_mysql_node2_data -> /var/lib/mysql
bind -> /etc/mysql/conf.d/my.cnf
```

No regresar a `./data:/var/lib/mysql`, no usar `chmod 777` y no borrar el
volumen.

## G. Validación final antes de Fase 2

### G.1 Byron confirma membresía

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Resultado obligatorio:

```text
100.113.38.39  3306  ONLINE  PRIMARY
100.126.57.24  3306  ONLINE  PRIMARY
100.107.61.57  3306  ONLINE  PRIMARY
```

### G.2 Carlos confirma solo lectura

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host,@@global.read_only,@@global.super_read_only;"
```

Resultado: `.57`, `1`, `1`.

### G.3 Byron levanta y comprueba ProxySQL

Desde `proxy/`:

```bash
docker compose up -d
docker compose ps
docker logs proxysql-db2 --since 10m 2>&1 | tail -n 30
```

Sirve para: recuperar el punto de entrada y verificar que el monitor ya ve el
grupo.

### G.4 Prueba remota limpia

Carlos:

```powershell
docker exec -it mysql-nodo3 mysql -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "SELECT @@report_host AS backend,@@server_id AS server_id,@@global.read_only AS read_only;"
```

La contraseña se introduce en el prompt. Un backend saludable de HG 30 es
válido; si responde nodo3 debe mostrar `read_only=1`.

## H. Semáforo para comenzar Fase 2

| Comprobación | Debe mostrar |
|---|---|
| Tailscale | `.39`, `.24`, `.57` alcanzables |
| Docker | tres MySQL saludables |
| Group Replication | tres miembros `ONLINE` |
| Bootstrap | `0` en todos |
| Nodo1/nodo2 | lectura/escritura |
| Nodo3 | `read_only=1`, `super_read_only=1` |
| ProxySQL | saludable y puerto `6033` accesible |
| Dataset | cinco tablas, stock inicial conocido, sin cliente de prueba |

Solo cuando todo esté verde se abre `avances/fase2.md` y se ejecuta el primer
INSERT.

## I. Resumen para memorizar

```text
1. Encender Docker y Tailscale.
2. Confirmar IP y puertos.
3. Consultar membresía y GTID.
4. Si hay grupo ONLINE: JOIN, nunca bootstrap.
5. Si todos OFFLINE: comparar GTID y un solo bootstrap.
6. Unir nodo2 y nodo3.
7. Proteger nodo3 con super_read_only.
8. Confirmar tres ONLINE.
9. Levantar ProxySQL.
10. Probar 6033 y comenzar Fase 2.
```
