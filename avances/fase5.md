# Fase 5 — Fallo múltiple y contingencia

## Objetivo oficial

Detener nodo1 y nodo2, comprobar que las escrituras dejan de estar disponibles,
mantener lectura directa desde nodo3 y recuperar gradualmente los tres nodos.

Esta es la prueba más delicada. Los responsables pueden rotar para aprender,
pero solo cada dueño controla Docker en su computadora. Nadie ejecuta un paso
sin confirmación en el chat del grupo.

## Responsables iniciales

| Función | Responsable |
|---|---|
| Detener/recuperar nodo1 y coordinar | Byron |
| Detener/recuperar nodo2 y medir tiempos | Michael |
| Consultar nodo3, evidencias y estado de contingencia | Carlos |

## 1. Precondiciones y punto de retorno

**Byron:**

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
SELECT @@global.gtid_executed;
"'
```

**Michael y Carlos:** guardan también su `@@global.gtid_executed`.

**Carlos:**

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host,@@global.read_only,@@global.super_read_only;"
```

No continuar salvo que:

- los tres estén `ONLINE`;
- los tres tengan los mismos GTID;
- nodo3 reporte `1/1`;
- Fases 3 y 4 ya tengan evidencia y recuperación probada.

> **CAPTURA F5-01 — Carlos:** membresía, GTID y nodo3 protegido.

## 2. Crear una marca previa

**Byron, por ProxySQL:**

```bash
read -s 'app_password?Contraseña de app_user: '
echo
docker exec -e MYSQL_PWD="$app_password" mysql-node1 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
INSERT INTO cliente(nombre,correo)
VALUES ('Evidencia fase 5','fase5.antes@example.com')
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);
SELECT correo,nombre FROM cliente WHERE correo='fase5.antes@example.com';
"
unset app_password
```

Sirve para: comprobar que el dato permanece disponible durante la contingencia
y después de recuperar el grupo.

> **CAPTURA F5-02 — Byron:** marca previa confirmada.

## 3. Detener nodo1 y nodo2

Se detienen únicamente los contenedores MySQL. ProxySQL y el sidecar Tailscale
de nodo2 permanecen activos.

**Byron:**

```bash
date --iso-8601=seconds
docker stop mysql-node1
```

**Michael, inmediatamente después:**

```bash
date --iso-8601=seconds
docker stop mysql-node2
```

Carlos registra el segundo momento como `T0` del fallo múltiple.

> **CAPTURA F5-03 — Byron/Michael:** ambos MySQL detenidos.

## 4. Comprobar que la escritura no está disponible

**Carlos intenta una escritura directa en nodo3:**

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "INSERT INTO cliente(nombre,correo) VALUES ('No debe entrar','fase5.noescribir@example.com');"
```

Resultado correcto: `ERROR 1290` por `super-read-only` o rechazo equivalente.

**Comprobación adicional por ProxySQL:** una escritura por `6033` debe fallar
o no encontrar escritores saludables. No se fuerza nodo3 como escritor.

> **CAPTURA F5-04 — Carlos:** escritura rechazada. Esto demuestra protección,
> no un defecto.

## 5. Consultar nodo3 en modo contingencia

**Carlos:**

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -Ddata_bugs -e "SELECT correo,nombre FROM cliente WHERE correo='fase5.antes@example.com'; SELECT COUNT(*) AS clientes FROM cliente;"
```

Resultado esperado: la marca previa y los datos siguen disponibles.

> **CAPTURA F5-05 — Carlos:** lectura exitosa con nodo1/nodo2 apagados.

Es normal que Group Replication pierda quórum con solo uno de tres miembros.
La finalidad aquí es conservar datos y lectura, no aceptar escrituras sin
mayoría.

## 6. Recuperar primero nodo1

**Byron:**

```bash
docker start mysql-node1
docker exec mysql-node1 sh -c 'until mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do sleep 2; done'
```

Primero se consulta el estado, sin bootstrap:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT @@global.gtid_executed;
SELECT MEMBER_HOST,MEMBER_STATE
FROM performance_schema.replication_group_members;
"'
```

### Ruta principal: nodo3 conserva el grupo y nodo1 puede unirse

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"'
```

Se espera a que nodo1 y nodo3 aparezcan `ONLINE`. En ese momento vuelve a haber
un escritor disponible y Carlos registra `T1`.

### Alternativa: ningún miembro queda `ONLINE`

No repetir `START` a ciegas. Se comparan los GTID de nodo1 y nodo3. Como no se
permitieron escrituras durante la contingencia, deberían coincidir.

Si coinciden, se detiene Group Replication en nodo3 y Byron ejecuta el
procedimiento de bootstrap único descrito en `avances/fase1.md`, sección 7,
usando nodo1. Después Carlos une nodo3 con `START GROUP_REPLICATION` y vuelve a
ejecutar:

```sql
SET GLOBAL super_read_only=ON;
```

Esta alternativa solo se usa cuando se confirmó que no existe ningún miembro
`ONLINE`.

> **CAPTURA F5-06 — Byron:** servicio de escritura recuperado y nodo3 unido.

## 7. Recuperar el nodo restante

**Michael:**

```bash
docker start mysql-node2
docker exec mysql-node2 sh -c 'until mysqladmin ping -hlocalhost -uroot -p"$MYSQL_ROOT_PASSWORD" --silent; do sleep 2; done'
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"'
```

Después los tres verifican:

```sql
SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;

SELECT correo,nombre
FROM data_bugs.cliente
WHERE correo='fase5.antes@example.com';
```

Resultado esperado: tres `ONLINE`, marca presente y nodo3 otra vez en lectura.

> **CAPTURA F5-07 — Michael:** tres miembros `ONLINE`.
>
> **CAPTURA F5-08 — Carlos:** dato consistente y nodo3 `read_only=1`.

## 8. Limpieza

Después de las capturas:

```sql
DELETE FROM data_bugs.cliente
WHERE correo IN ('fase5.antes@example.com','fase5.noescribir@example.com');
```

La segunda dirección normalmente no existirá porque la escritura fue
rechazada; incluirla hace la limpieza repetible.

## 9. Detalles interesantes para la defensa

- Tres miembros toleran la pérdida de uno; perder dos elimina el quórum.
- Bloquear escrituras sin quórum reduce el riesgo de split-brain.
- RPO esperado: cero, porque durante la contingencia no se aceptaron
  escrituras y la marca previa permaneció.
- RTO se mide desde el segundo apagado (`T0`) hasta recuperar un escritor
  utilizable (`T1`).
- ProxySQL puede quedarse sin backend escritor de forma intencional; es más
  seguro fallar una escritura que enviarla a un nodo de contingencia.

## Criterio de cierre

- Nodo1 y nodo2 estuvieron fuera de servicio.
- Las escrituras fueron rechazadas.
- Nodo3 conservó lectura y datos.
- Se recuperó primero un escritor y luego el nodo restante.
- Los tres terminaron `ONLINE` y sincronizados.
- Se registraron RTO, RPO, consultas, logs y capturas.
