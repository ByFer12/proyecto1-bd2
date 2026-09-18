# Fase 3 — Fallo de nodo1

## Objetivo oficial

Demostrar que, al detener MySQL de nodo1, ProxySQL detecta la caída, nodo2
mantiene lectura/escritura, nodo3 recibe los cambios y nodo1 puede reintegrarse
sin pérdida de datos.

Los responsables son operativos y pueden rotarse para practicar. El comando
que detiene un contenedor solo puede ejecutarlo quien controla esa máquina.

## Responsables de la ejecución

| Función | Responsable inicial |
|---|---|
| Detener y recuperar `mysql-node1` | Byron |
| Operar por ProxySQL desde nodo2 | Michael |
| Verificar nodo3, medir tiempo y capturar | Carlos |

No apagar físicamente la computadora de Byron en esta prueba: ProxySQL vive en
ese host. Se detiene solamente `mysql-node1`, dejando `proxysql-db2` activo.
Esto prueba la caída del servidor MySQL; el punto único de fallo del host del
proxy se documenta como limitación de la arquitectura.

## 1. Precondiciones

**Byron:**

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'mysql-node1|proxysql-db2'
```

Sirve para: confirmar tres miembros `ONLINE` y ProxySQL saludable.

**Carlos:** confirma nodo3 protegido:

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host,@@global.read_only,@@global.super_read_only;"
```

Resultado esperado: `.57`, `1`, `1`.

> **CAPTURA F3-01 — Carlos:** tres miembros `ONLINE`, ProxySQL saludable y
> nodo3 `1/1`.

## 2. Insertar información antes de la falla

**Michael, utilizando ProxySQL:**

```bash
docker exec -it mysql-node2 mysql -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 3 antes','fase3.antes@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);
SELECT correo,nombre FROM cliente WHERE correo='fase3.antes@example.com';
"
```

Sirve para: dejar una marca previa que después debe existir en nodo1
reintegrado. La contraseña se introduce en el prompt.

> **CAPTURA F3-02 — Michael:** fila previa confirmada por ProxySQL.

## 3. Detener nodo1 y marcar T0

**Byron:**

```bash
date --iso-8601=seconds
docker stop mysql-node1
```

Sirve para: simular la caída del servicio y registrar el inicio del fallo.
Carlos anota esa hora como `T0`.

> **CAPTURA F3-03 — Byron:** hora T0 y confirmación `mysql-node1` detenido.

Alternativa si se necesita una detención ordenada:

```bash
docker exec mysql-node1 sh -c 'mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" shutdown'
```

Para la evidencia principal se prefiere `docker stop`, que representa mejor
una pérdida inesperada del servicio.

## 4. Comprobar que ProxySQL detectó la caída

**Byron usa un contenedor temporal porque `mysql-node1` está detenido:**

```bash
admin_pair=$(sed -n 's/^[[:space:]]*admin_credentials="\([^"]*\)".*/\1/p' proxy/conf/proxysql.cnf | head -n1)
proxy_admin_user=${admin_pair%%:*}
proxy_admin_pass=${admin_pair#*:}

docker run --rm --network host -e MYSQL_PWD="$proxy_admin_pass" mysql:8.4 \
  mysql -h127.0.0.1 -P6032 -u"$proxy_admin_user" -e "
SELECT hostgroup_id,hostname,status
FROM runtime_mysql_servers
ORDER BY hostgroup_id,hostname;
"

unset admin_pair proxy_admin_user proxy_admin_pass
```

Sirve para: observar que nodo1 dejó de ser un backend utilizable y que nodo2
permanece escritor. No modifica ProxySQL.

> **CAPTURA F3-04 — Byron:** hostgroups durante la caída.

## 5. Escribir desde nodo2 durante la falla

**Michael:**

```bash
docker exec -it mysql-node2 mysql -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "
START TRANSACTION;
SELECT @@report_host AS backend_escritor,@@server_id AS server_id FOR UPDATE;
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 3 durante','fase3.durante@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);
COMMIT;
SELECT correo,nombre FROM cliente WHERE correo='fase3.durante@example.com';
"
```

Resultado esperado: backend escritor `.24` y operación exitosa.

> **CAPTURA F3-05 — Michael:** backend y escritura exitosa durante la caída.

## 6. Verificar el cambio en nodo3

**Carlos:**

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT correo,nombre FROM cliente WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com') ORDER BY correo;"
```

Sirve para: demostrar que la información continúa disponible en contingencia.

> **CAPTURA F3-06 — Carlos:** las dos filas visibles en nodo3.

## 7. Recuperar nodo1 y medir T1

**Byron:**

```bash
docker start mysql-node1
docker exec mysql-node1 sh -c 'until mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do sleep 2; done'

docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
"'
```

No se usa bootstrap: nodo2 y nodo3 mantuvieron el grupo vivo.

Después:

```bash
date --iso-8601=seconds
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
SELECT correo,nombre FROM data_bugs.cliente
WHERE correo IN ('\''fase3.antes@example.com'\'','\''fase3.durante@example.com'\'')
ORDER BY correo;
"'
```

Carlos registra `T1` cuando nodo1 aparece `ONLINE` y calcula `RTO=T1-T0`.

> **CAPTURA F3-07 — Byron:** tres `ONLINE` y ambas filas en nodo1 recuperado.

## 8. Limpieza

Después de guardar evidencia, Byron elimina las dos marcas mediante ProxySQL:

```bash
read -s 'app_password?Contraseña de app_user: '
echo
docker exec -e MYSQL_PWD="$app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
DELETE FROM cliente
WHERE correo IN ('fase3.antes@example.com','fase3.durante@example.com');
"
unset app_password
```

## 9. Detalle interesante para la defensa

- ProxySQL retira automáticamente el backend caído sin cambiar la aplicación.
- GTID permite que nodo1 solicite las transacciones que perdió durante la
  caída.
- El host de nodo1 todavía es un punto único para ProxySQL. Una mejora futura
  sería ejecutar un segundo ProxySQL con una IP virtual o DNS de failover.

## Criterio de cierre

- Nodo1 fue detenido.
- Nodo2 aceptó escritura mediante ProxySQL.
- Nodo3 mostró el cambio.
- Nodo1 se reintegró `ONLINE` y recuperó los datos.
- RTO, logs y capturas quedaron registrados.
