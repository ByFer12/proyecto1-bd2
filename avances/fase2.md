# Fase 2 — Replicación normal

## Objetivo oficial

Demostrar INSERT, UPDATE y DELETE desde nodo1 y repetirlos desde nodo2,
verificando cada operación en los otros dos nodos.

Los responsables indicados son operativos, no exclusivos: todos deben aprender
el procedimiento y pueden intercambiarse. Solo los comandos locales de Docker
deben ejecutarse en la computadora que aloja el contenedor correspondiente.

## Estado

**Preparada.** El 18 de septiembre de 2026 se confirmó la línea base sin
modificar datos. Después del apagado se recuperó el grupo y volvieron a
observarse los tres miembros `ONLINE`. Antes del primer INSERT todavía se debe
cerrar el semáforo de entrada descrito abajo y volver a capturar la línea base.

```text
cliente          4
producto         4
pedido           2
detalle_pedido   3
pago             1
Adaptador USB-C  stock 60
cliente.prueba@example.com  0 filas
```

Los tres miembros estaban `ONLINE / PRIMARY` y las tres consultas devolvieron
exactamente los mismos valores.

Las tablas ya fueron creadas anteriormente con `database/schema.sql` y los
datos iniciales con `database/data.sql`. Por eso esta fase empieza insertando:
el esquema y las relaciones ya existen. No se vuelven a ejecutar esos archivos
porque las tablas y valores únicos provocarían duplicados.

No utilizar `information_schema.TABLE_ROWS` como conteo exacto en InnoDB: es
una estimación. Para evidencia de consistencia se usa `COUNT(*)`.

## Responsables durante la prueba

| Acción | Responsable |
|---|---|
| Ejecutar escritura de nodo1 | Byron |
| Verificar desde nodo2 | Michael |
| Verificar desde nodo3 y capturar | Carlos |
| Ejecutar escritura de nodo2 | Michael |
| Verificar desde nodo1 e integrar bitácora | Byron |

No se ejecuta el siguiente paso hasta recibir las dos verificaciones del paso
actual.

## Advertencias

- No ejecutar nuevamente `database/schema.sql`.
- No ejecutar nuevamente `database/data.sql`.
- No ejecutar dos escrituras al mismo tiempo.
- No ejecutar `insert.sql` si ya existe `cliente.prueba@example.com`.
- `delete.sql` se usa solamente después de insertar el cliente de prueba.
- No detener nodos durante esta fase.

## 1. Estado inicial

### Semáforo antes de comenzar

No se ejecuta ninguna escritura de esta fase hasta comprobar:

- tres miembros `ONLINE`;
- nodo1 y nodo2 con `read_only=0` y `super_read_only=0`;
- nodo3 con `read_only=1` y `super_read_only=1`;
- `proxysql-db2` saludable y hostgroups 10/30 operativos;
- conexión de prueba por ProxySQL en el puerto `6033`.

Si la validación de ProxySQL de la Fase 1 sigue pendiente después de un
apagado, se termina primero esa validación y luego se regresa a esta sección.

### Byron — membresía

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

Sirve para: demostrar que la prueba empieza con tres miembros `ONLINE`.

> **CAPTURA F2-01 — Byron:** comando y tres filas `ONLINE`. Si falta una fila,
> detener la fase y recuperar ese nodo.

### Consulta exacta de consistencia

Los tres ejecutan la misma consulta en sus respectivas instancias. Byron puede
registrar primero el valor de referencia, pero Michael y Carlos deben confirmar
que reciben exactamente lo mismo.

#### Byron — nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT '\''cliente'\'' AS entidad, COUNT(*) AS cantidad FROM data_bugs.cliente
UNION ALL SELECT '\''producto'\'', COUNT(*) FROM data_bugs.producto
UNION ALL SELECT '\''pedido'\'', COUNT(*) FROM data_bugs.pedido
UNION ALL SELECT '\''detalle_pedido'\'', COUNT(*) FROM data_bugs.detalle_pedido
UNION ALL SELECT '\''pago'\'', COUNT(*) FROM data_bugs.pago;
SELECT nombre,stock FROM data_bugs.producto WHERE nombre='\''Adaptador USB-C'\'';
SELECT COUNT(*) AS cliente_prueba FROM data_bugs.cliente
WHERE correo='\''cliente.prueba@example.com'\'';
"'
```

#### Michael — nodo2

Ejecuta el mismo bloque anterior sustituyendo únicamente `mysql-node1` por
`mysql-node2`.

#### Carlos — nodo3

Carlos entra con `docker exec -it mysql-nodo3 mysql -uroot -p` y pega dentro
de `mysql>` el SQL siguiente:

```sql
SELECT 'cliente' AS entidad, COUNT(*) AS cantidad FROM data_bugs.cliente
UNION ALL SELECT 'producto', COUNT(*) FROM data_bugs.producto
UNION ALL SELECT 'pedido', COUNT(*) FROM data_bugs.pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM data_bugs.detalle_pedido
UNION ALL SELECT 'pago', COUNT(*) FROM data_bugs.pago;

SELECT nombre,stock
FROM data_bugs.producto
WHERE nombre='Adaptador USB-C';

SELECT COUNT(*) AS cliente_prueba
FROM data_bugs.cliente
WHERE correo='cliente.prueba@example.com';
```

Sirve para: registrar el estado antes de las escrituras.

> **CAPTURA F2-02 — Carlos:** conteos iniciales, stock 60 y cliente de prueba
> igual a 0. Michael confirma que obtiene lo mismo.

## 2. Ciclo desde nodo1

Todos los comandos de Byron se ejecutan desde la raíz del repositorio.

### 2.1 INSERT — Byron

```bash
docker exec -i mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/insert.sql
```

Sirve para: crear un cliente, pedido y detalle relacionados dentro de una
transacción.

Resultado esperado: una fila para `Cliente de prueba` con pedido `PENDIENTE`.

> **CAPTURA F2-03 — Byron:** salida del INSERT con cliente, pedido y estado.

### 2.2 Verificar INSERT — Michael

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT c.correo,p.pedido_id,p.estado,p.total
FROM data_bugs.cliente c
JOIN data_bugs.pedido p ON p.cliente_id=c.cliente_id
WHERE c.correo=\"cliente.prueba@example.com\";
"'
```

### 2.3 Verificar INSERT — Carlos

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT c.correo,p.pedido_id,p.estado,p.total FROM data_bugs.cliente c JOIN data_bugs.pedido p ON p.cliente_id=c.cliente_id WHERE c.correo='cliente.prueba@example.com';"
```

Sirve para: demostrar que el INSERT originado en nodo1 llegó a nodo2 y nodo3.

> **CAPTURA F2-04 — Michael y Carlos:** misma fila en ambos nodos. No avanzar
> al UPDATE hasta recibir ambas verificaciones.

### 2.4 UPDATE — Byron

```bash
docker exec -i mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/update.sql
```

Sirve para: disminuir en uno el stock de `Adaptador USB-C` y cambiar el pedido
de prueba a `PAGADO`.

Resultado esperado: stock 59 y pedido `PAGADO` en el primer ciclo.

> **CAPTURA F2-05 — Byron:** stock y pedido después del UPDATE.

### 2.5 Verificar UPDATE — Michael y Carlos

```sql
SELECT nombre,stock
FROM data_bugs.producto
WHERE nombre='Adaptador USB-C';

SELECT c.correo,p.estado
FROM data_bugs.cliente c
JOIN data_bugs.pedido p ON p.cliente_id=c.cliente_id
WHERE c.correo='cliente.prueba@example.com';
```

Sirve para: comprobar el mismo stock y estado en ambos nodos.

> **CAPTURA F2-06 — Michael y Carlos:** stock 59 y estado `PAGADO`.

### 2.6 DELETE — Byron

```bash
docker exec -i mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/delete.sql
```

Sirve para: eliminar detalle, pago si existe, pedido y cliente de prueba
respetando las claves foráneas.

Resultado esperado: `clientes_de_prueba = 0`.

> **CAPTURA F2-07 — Byron:** confirmación del DELETE.

### 2.7 Verificar DELETE — Michael y Carlos

```sql
SELECT COUNT(*) AS clientes_de_prueba
FROM data_bugs.cliente
WHERE correo='cliente.prueba@example.com';
```

Resultado esperado en ambos: `0`.

> **CAPTURA F2-08 — Michael y Carlos:** resultado 0 en ambos nodos.

## 3. Ciclo desde nodo2

Se inicia únicamente después de terminar y documentar el ciclo de nodo1. Como
el cliente de prueba fue eliminado, puede reutilizarse el mismo script.

Michael, desde la raíz de su repositorio:

```bash
docker exec -i mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/insert.sql

docker exec -i mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/update.sql

docker exec -i mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/delete.sql
```

Después de cada comando, Byron verifica en nodo1 y Carlos en nodo3 antes de
que Michael ejecute el siguiente.

En el segundo ciclo el stock esperado pasa de 59 a 58. El DELETE no restaura
el stock; esto es normal y debe documentarse.

> **CAPTURAS F2-09 a F2-11:** Michael captura INSERT, UPDATE y DELETE desde
> nodo2; Byron y Carlos capturan la verificación correspondiente después de
> cada operación.

## 4. Consistencia final

Cada integrante se ubica en la raíz de su copia del repositorio. Los nombres
de contenedor usan guion (`-`), no guion bajo (`_`).

Byron — nodo1:

```bash
docker exec -i mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/consistency.sql
```

Si Byron está ubicado dentro de `nodes/node1/`, la ruta equivalente es:

```bash
docker exec -i mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < ../../database/tests/consistency.sql
```

La opción `-i` es obligatoria cuando se redirige un archivo con `<`: mantiene
abierta la entrada estándar del contenedor. Si se omite, puede aparecer solo la
advertencia de contraseña y ninguna tabla, porque MySQL no recibió el SQL. Ese
caso no significa que la consistencia haya sido validada; se corrige agregando
`-i` y ejecutando nuevamente la consulta.

Michael — nodo2:

```bash
docker exec -i mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  < database/tests/consistency.sql
```

Carlos — nodo3 en PowerShell, desde la raíz de su repositorio:

```powershell
Get-Content .\database\tests\consistency.sql | docker exec -i mysql-nodo3 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
```

La contraseña se toma de la variable interna del contenedor y no se escribe en
PowerShell. Como alternativa, Carlos puede abrir MySQL con
`docker exec -it mysql-nodo3 mysql -uroot -p` y pegar el contenido del archivo
desde el prompt `mysql>`.

También se registra:

```sql
SELECT @@global.gtid_executed;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

Resultado requerido:

- mismos conteos y datos en los tres nodos;
- cliente de prueba eliminado;
- stock final 58;
- tres miembros `ONLINE`;
- sin errores de replicación.

Después de completar los dos ciclos CRUD, el primer resultado esperado es:

```text
entidad    cantidad
clientes   4
productos  4
pedidos    2
detalles   3
pagos      1
```

Los pedidos iniciales deben continuar consistentes:

```text
pedido_id  cliente      estado      total   total_calculado
1          Ana Torres   PAGADO      280.50  280.50
2          Luis Moreno  PENDIENTE   720.00  720.00
```

La última consulta de `consistency.sql` busca pagos duplicados. El resultado
correcto es ninguna fila.

El archivo de consistencia no muestra el stock ni cuenta explícitamente el
correo de prueba. Byron los confirma adicionalmente:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT nombre,stock
FROM data_bugs.producto
WHERE nombre=\"Adaptador USB-C\";

SELECT COUNT(*) AS cliente_prueba
FROM data_bugs.cliente
WHERE correo=\"cliente.prueba@example.com\";
"'
```

Resultado esperado:

```text
Después del ciclo de nodo1: stock 59, cliente_prueba 0.
Después también del ciclo de nodo2: stock 58, cliente_prueba 0.
```

La línea `Using a password on the command line interface can be insecure` es
una advertencia del cliente MySQL, no un fallo de la consulta.

> **CAPTURAS F2-12 y F2-13:** consistencia final y membresía con tres `ONLINE`.

## 5. Evidencias

1. `fase2-01-linea-base.png`
2. `fase2-02-insert-nodo1.png`
3. `fase2-03-insert-verificado-nodos2-3.png`
4. `fase2-04-update-nodo1.png`
5. `fase2-05-update-verificado-nodos2-3.png`
6. `fase2-06-delete-nodo1.png`
7. `fase2-07-ciclo-nodo2.png`
8. `fase2-08-verificacion-nodos1-3.png`
9. `fase2-09-consistencia-final.png`
10. `fase2-10-tres-online.png`

No incluir contraseñas en ninguna captura.

## 6. Criterio de cierre

La Fase 2 queda completa cuando ambos ciclos CRUD fueron verificados en los
otros dos nodos, la consistencia final coincide y los tres miembros siguen
`ONLINE`.
