# Fase 4 — Fallo de nodo2

## Objetivo oficial

Demostrar que la solución continúa con nodo1 cuando MySQL nodo2 falla, que
nodo3 recibe los cambios y que nodo2 puede reintegrarse sincronizado.

Los responsables pueden rotarse para practicar. Solo Michael puede ejecutar
los comandos Docker locales de nodo2 y su sidecar Tailscale.

## Responsables iniciales

| Función | Responsable |
|---|---|
| Escritura por ProxySQL e integración | Byron |
| Detener/recuperar nodo2 y registrar T0/T1 | Michael |
| Verificar nodo3 y capturar | Carlos |

## 1. Verificar sincronización inicial

**Byron:**

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
SELECT @@global.gtid_executed;
"'
```

**Michael y Carlos:** consultan también `@@global.gtid_executed` localmente.

Sirve para: registrar la posición inicial y los tres miembros `ONLINE`.

> **CAPTURA F4-01 — Carlos:** membresía y GTID iniciales.

## 2. Detener nodo2

**Michael, desde `nodes/node2/`:**

```bash
date --iso-8601=seconds
docker stop mysql-node2
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'mysql-node2|tailscale-node2'
```

Se deja `tailscale-node2` activo; solo falla MySQL. Carlos registra la hora como
`T0`.

> **CAPTURA F4-02 — Michael:** MySQL detenido y sidecar Tailscale activo.

Alternativa más severa, solo si el escenario principal ya fue documentado:
detener también `tailscale-node2` para simular pérdida total de red del nodo.
Después exige validar primero Tailscale antes de reintegrar MySQL.

## 3. Confirmar detección de la caída

**Byron:** espera dos ciclos del monitor y ejecuta la consulta administrativa
de hostgroups descrita en `avances/fase1.md`, sección 10.

Resultado esperado:

- nodo2 deja de estar disponible en HG 10/30;
- nodo1 permanece escritor en HG 10;
- nodo3 permanece lector en HG 30.

> **CAPTURA F4-03 — Byron:** hostgroups durante la caída.

## 4. Ejecutar lectura y escritura en nodo1

**Byron por ProxySQL:**

```bash
read -s 'app_password?Contraseña de app_user: '
echo
docker exec -e MYSQL_PWD="$app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
START TRANSACTION;
SELECT @@report_host AS backend_escritor,@@server_id AS server_id FOR UPDATE;
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 4','fase4.durante@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);
COMMIT;
SELECT correo,nombre FROM cliente WHERE correo='fase4.durante@example.com';
"
unset app_password
```

Resultado esperado: escritura exitosa mediante nodo1 `.39`.

> **CAPTURA F4-04 — Byron:** backend escritor y fila creada.

## 5. Verificar el cambio en nodo3

**Carlos:**

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT correo,nombre FROM cliente WHERE correo='fase4.durante@example.com';"
```

> **CAPTURA F4-05 — Carlos:** fila visible mientras nodo2 está apagado.

## 6. Recuperar y reintegrar nodo2

**Michael:**

```bash
docker start mysql-node2
docker exec mysql-node2 sh -c 'until mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do sleep 2; done'

docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
"'
```

No se usa bootstrap porque nodo1 y nodo3 permanecieron en el grupo.

Después Michael consulta:

```bash
date --iso-8601=seconds
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
SELECT correo,nombre FROM data_bugs.cliente
WHERE correo='\''fase4.durante@example.com'\'';
"'
```

Carlos registra `T1` cuando nodo2 aparece `ONLINE`; se calcula `RTO=T1-T0`.

> **CAPTURA F4-06 — Michael:** tres miembros `ONLINE` y fila recuperada.

Si `START GROUP_REPLICATION` falla:

1. revisar `docker logs mysql-node2 --since 10m`;
2. comprobar `docker exec tailscale-node2 tailscale status`;
3. probar desde nodo1 `nc -vz -w 5 100.126.57.24 3306`;
4. no borrar volúmenes ni activar bootstrap mientras nodo1/nodo3 estén
   `ONLINE`.

## 7. Limpieza

Byron elimina la marca después de las capturas:

```sql
DELETE FROM data_bugs.cliente
WHERE correo='fase4.durante@example.com';
```

## 8. Detalle interesante para la defensa

- El sidecar Tailscale y MySQL son componentes separados: puede fallar uno sin
  borrar el volumen del otro.
- ProxySQL reintroduce automáticamente nodo2 cuando vuelve a ser viable.
- Comparar GTID antes y después demuestra recuperación lógica, no solo que el
  contenedor volvió a encender.

## Criterio de cierre

- Nodo2 fue detenido y detectado por ProxySQL.
- Nodo1 mantuvo lectura/escritura.
- Nodo3 recibió el cambio.
- Nodo2 regresó `ONLINE` con la fila creada durante su ausencia.
- Se registraron T0, T1, RTO, consultas, logs y capturas.
