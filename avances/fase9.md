# Fase 9 — Prueba de resiliencia durante la calificación

## Objetivo oficial

Responder de forma ordenada al componente que el auxiliar decida apagar y
explicar qué ocurrió, cómo respondió la arquitectura, quién asumió el servicio,
si hubo indisponibilidad y cómo se recuperó.

Esta fase no tiene un único fallo predeterminado. Es un runbook de decisión
que reutiliza las pruebas ya validadas en Fases 3–8.

## Roles durante la demostración

| Rol | Responsable inicial | Tarea |
|---|---|---|
| Coordinador | Byron | Repite la solicitud del auxiliar y decide la ruta |
| Operador | Dueño del componente | Ejecuta únicamente el comando autorizado |
| Observador/cronometrista | Integrante libre | T0/T1, dashboard y bitácora |

Los roles se pueden rotar. Nadie ejecuta simultáneamente un “arreglo” distinto.

## Semáforo antes de recibir el fallo

### Byron — clúster

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
"'
```

### Byron — ProxySQL

```bash
cd proxy
docker compose ps
```

### Carlos — nodo3 protegido

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT @@report_host,@@global.read_only,@@global.super_read_only;"
```

Resultado esperado: tres `ONLINE`, ProxySQL activo y nodo3 `1/1`.

> **CAPTURA F9-01:** estado inmediatamente anterior al escenario elegido.

---

## Procedimiento universal de cinco pasos

Para cualquier componente:

1. **Confirmar alcance:** repetir en voz alta qué componente se apagará.
2. **Registrar T0:** el cronometrista registra hora ISO y milisegundos.
3. **Observar antes de corregir:** estado MySQL, ProxySQL y dashboard.
4. **Demostrar continuidad o limitación:** ejecutar una lectura/escritura
   segura según el escenario.
5. **Recuperar y validar:** restaurar el componente, medir T1 y comprobar datos.

Nunca hacer bootstrap mientras exista un grupo con miembros `ONLINE`.

---

## Ruta A — El auxiliar apaga MySQL nodo1

### Operador: Byron

Reutilizar `avances/fase3.md`:

- detener nodo1;
- observar `.39` en HG40/`SHUNNED`;
- comprobar escritura por nodo2 y lectura en nodo3;
- iniciar nodo1;
- ejecutar `START GROUP_REPLICATION` sin bootstrap;
- esperar tres `ONLINE` y GTID iguales.

### Explicación que debe dar el equipo

- Ocurrió: se perdió uno de los dos escritores.
- Respuesta: ProxySQL retiró el backend no saludable.
- Asumió servicio: nodo2.
- Disponibilidad: posible interrupción corta durante detección; luego continúa.
- Recuperación: nodo1 hizo distributed recovery y volvió `ONLINE`.

---

## Ruta B — El auxiliar apaga MySQL nodo2

### Operador: Michael

Reutilizar `avances/fase4.md`:

- detener únicamente `mysql-node2`, no `tailscale-node2`;
- comprobar nodo2 `SHUNNED` y nodo1 escritor;
- recuperar MySQL nodo2;
- ejecutar `START GROUP_REPLICATION` sin bootstrap;
- validar tres `ONLINE` y sincronización.

### Explicación

Nodo1 conserva escrituras, nodo3 conserva lectura/contingencia y ProxySQL
retira nodo2 hasta que esté saludable nuevamente.

---

## Ruta C — El auxiliar apaga MySQL nodo3

### Operador: Carlos

Carlos detiene el contenedor indicado por su compose:

```powershell
docker stop mysql-nodo3
```

Byron comprueba que nodo1/nodo2 continúan `ONLINE` y realiza una consulta por
ProxySQL. Para recuperar:

```powershell
docker start mysql-nodo3
docker exec -it mysql-nodo3 mysql -uroot -p
```

Dentro de MySQL:

```sql
START GROUP_REPLICATION;
SET GLOBAL super_read_only=ON;

SELECT MEMBER_HOST,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;

SELECT @@global.read_only,@@global.super_read_only;
```

Esperado: nodo1/nodo2 mantienen servicio; nodo3 vuelve `ONLINE` y `1/1`.

### Explicación

Se perdió el nodo de contingencia/lectura, no ambos escritores. La arquitectura
mantiene operaciones normales, pero temporalmente reduce redundancia.

---

## Ruta D — El auxiliar apaga ProxySQL

### Operador: Byron

Desde `proxy/`:

```bash
date --iso-8601=seconds
docker stop proxysql-db2
docker compose ps
```

Resultado esperado: el acceso por `6033` falla aunque MySQL siga `ONLINE`.
Esto demuestra el punto único restante del diseño, no una pérdida de datos.

Recuperar:

```bash
docker start proxysql-db2
docker compose ps
```

Después probar una consulta con `app_user` por `6033` y verificar los
hostgroups con el procedimiento de Fase 3, punto 4.

### Explicación

- Los tres MySQL y la replicación continúan.
- El endpoint único de aplicaciones queda temporalmente indisponible.
- Reiniciar ProxySQL recupera el acceso; un segundo proxy/VIP sería mejora
  futura para eliminar este SPOF.

---

## Ruta E — El auxiliar apaga Tailscale de nodo2

### Operador: Michael

Detener el sidecar también interrumpe la red compartida de `mysql-node2`:

```bash
docker stop tailscale-node2
```

Byron comprueba timeout hacia `.24:3306`; ProxySQL debe conservar nodo1. Para
recuperar:

```bash
docker start tailscale-node2
docker restart mysql-node2
docker exec tailscale-node2 tailscale status
```

Si los exporters de nodo2 comparten `container:tailscale-node2`, reiniciarlos:

```bash
docker restart mysqld-exporter-node2 node-exporter-node2
```

Luego `START GROUP_REPLICATION` en nodo2 sin bootstrap y validar tres
`ONLINE`.

### Explicación

Falló la conectividad privada del nodo, por lo que para el clúster equivale a
un miembro inalcanzable aunque su volumen permanezca intacto.

---

## Ruta F — Fallo múltiple o todos aparecen OFFLINE

Reutilizar exclusivamente:

- `avances/fase5.md` para la prueba controlada de ambos escritores;
- `avances/inicio.md` para recuperar después de apagados;
- comparación de GTID antes de elegir bootstrap.

Si todos están `OFFLINE`, no adivinar. Comparar `gtid_executed`; elegir el nodo
más actualizado; hacer bootstrap **una sola vez**; apagar inmediatamente la
bandera y unir los otros nodos. Si existe algún grupo `ONLINE`, no hacer
bootstrap: los demás solo ejecutan `START GROUP_REPLICATION`.

---

## Validación final para cualquier ruta

### Membresía

```sql
SELECT MEMBER_HOST,MEMBER_PORT,MEMBER_STATE,MEMBER_ROLE
FROM performance_schema.replication_group_members;
```

Esperado: tres `ONLINE / PRIMARY`.

### Datos

```sql
SELECT @@global.gtid_executed;
```

Esperado: mismo conjunto en los tres nodos.

### Protección de nodo3

```sql
SELECT @@global.read_only,@@global.super_read_only;
```

Esperado en nodo3: `1 / 1`.

### Proxy

Esperado: nodo1/nodo2 en hostgroups activos, nodo3 en lectura y ningún miembro
recuperado permanece injustificadamente `SHUNNED`.

> **CAPTURA F9-02:** falla seleccionada y respuesta.
>
> **CAPTURA F9-03:** recuperación final y tiempo registrado.

## Guion oral de 30 segundos

```text
El componente que falló fue ______. Lo detectamos mediante ______.
Durante la falla, ______ asumió/conservó el servicio y la disponibilidad fue
______. Los datos permanecieron ______. Recuperamos el componente ejecutando
______ sin formar un segundo grupo. Finalmente verificamos tres miembros
ONLINE, GTID iguales, nodo3 protegido y un tiempo de recuperación de ______.
```

## Criterio de cierre

- [ ] Cada integrante practicó al menos dos rutas.
- [ ] El equipo sabe cuándo NO usar bootstrap.
- [ ] Se puede explicar el SPOF de ProxySQL sin ocultarlo.
- [ ] Toda recuperación termina verificando membresía, GTID y nodo3 `1/1`.
- [ ] La prueba real de calificación se añade a la bitácora.
