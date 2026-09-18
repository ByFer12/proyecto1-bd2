# Fase 8 — Medición de RTO y RPO

## Objetivo oficial

Medir el impacto real de una falla: cuánto tarda el servicio en volver a
aceptar operaciones (`RTO`) y cuántas operaciones confirmadas se pierden
(`RPO`).

## Definiciones usadas por el grupo

- **T0:** instante exacto en que se provoca la falla.
- **T1:** primera operación confirmada nuevamente a través de ProxySQL.
- **RTO del servicio:** `T1 - T0`.
- **T2:** instante en que se inicia la recuperación del nodo.
- **T3:** instante en que el nodo vuelve a `ONLINE`.
- **Tiempo de reintegración:** `T3 - T2`.
- **RPO observado:** operaciones que respondieron éxito pero no aparecen
  después de recuperar y comparar los tres nodos.

No confundir el RTO del servicio con el tiempo de reintegración. Nodo2 puede
restaurar escrituras antes de que nodo1 vuelva a formar parte del grupo.

## Responsables iniciales

- Byron: cliente de prueba, nodo1, T0/T1 y evidencias.
- Michael: confirmar continuidad en nodo2 y apoyar T2/T3.
- Carlos: comprobar datos en nodo3, bitácora y cálculo independiente.

## Preparación

Ejecuta Byron desde la raíz del repositorio:

```bash
mkdir -p evidencias/fase8/resultados
read -s 'fase8_app_password?Contraseña de app_user: '
echo
```

Antes de la prueba se reutiliza el semáforo de `avances/fase2.md`: tres nodos
`ONLINE`, GTID iguales, nodo3 `1/1` y ProxySQL saludable.

---

## 1. Registrar el momento exacto de la caída de un nodo

### 1.1 Crear cinco operaciones previas — ejecuta Byron

```bash
for numero in 1 2 3 4 5; do
  docker run --rm --network host \
    -e MYSQL_PWD="$fase8_app_password" mysql:8.4 \
    mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
      INSERT INTO cliente(nombre,correo)
      VALUES ('Fase 8 previa ${numero}','fase8.previa.${numero}@example.com')
      ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);"
done
```

Sirve para: disponer de cinco operaciones conocidas anteriores a la falla.
Esperado: las cinco terminan con código de salida `0`.

### 1.2 Registrar T0 y detener nodo1 — ejecuta Byron

```bash
fase8_t0_iso=$(date --iso-8601=seconds)
fase8_t0_ms=$(date +%s%3N)
printf 'T0=%s epoch_ms=%s\n' "$fase8_t0_iso" "$fase8_t0_ms" \
  | tee evidencias/fase8/resultados/tiempos.txt

docker stop mysql-node1
```

Sirve para: fijar el comienzo medible de la interrupción. Esperado:
`mysql-node1` queda detenido y ProxySQL permanece encendido.

> **CAPTURA F8-01:** T0 y nodo1 detenido.

---

## 2. Registrar cuándo el servicio vuelve a estar disponible

### Ejecuta: Byron

Byron intenta las cinco operaciones posteriores, registrando errores reales y
el primer éxito:

```bash
fase8_t1_ms=''

for numero in 6 7 8 9 10; do
  intento_iso=$(date --iso-8601=seconds)

  if docker run --rm --network host \
    -e MYSQL_PWD="$fase8_app_password" mysql:8.4 \
    mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
      INSERT INTO cliente(nombre,correo)
      VALUES ('Fase 8 durante ${numero}','fase8.durante.${numero}@example.com')
      ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);"; then
    printf '%s operación %s EXITOSA\n' "$intento_iso" "$numero" \
      | tee -a evidencias/fase8/resultados/operaciones.txt

    if [ -z "$fase8_t1_ms" ]; then
      fase8_t1_ms=$(date +%s%3N)
      fase8_t1_iso=$(date --iso-8601=seconds)
    fi
  else
    printf '%s operación %s FALLIDA\n' "$intento_iso" "$numero" \
      | tee -a evidencias/fase8/resultados/operaciones.txt
  fi
done

printf 'T1=%s epoch_ms=%s\n' "$fase8_t1_iso" "$fase8_t1_ms" \
  | tee -a evidencias/fase8/resultados/tiempos.txt

if [ -z "$fase8_t1_ms" ]; then
  echo 'ERROR: ninguna operación recuperó el servicio; no calcular RTO todavía'
  false
fi
```

Sirve para: identificar el primer instante comprobado en que nodo2 atendió
una escritura mediante ProxySQL.

Resultado esperado: puede existir algún intento fallido durante la detección,
pero al menos uno termina exitosamente. Si ninguno tiene éxito, la arquitectura
no recuperó escritura y primero se diagnostica ProxySQL/Fase 3.

> **CAPTURA F8-02:** registro de operaciones fallidas/exitosas y T1.

---

## 3. Calcular el RTO

### Ejecuta: Byron. Verifica: Carlos

```bash
fase8_rto_ms=$((fase8_t1_ms - fase8_t0_ms))
printf 'RTO_servicio_ms=%s\n' "$fase8_rto_ms" \
  | tee -a evidencias/fase8/resultados/tiempos.txt
```

Resultado esperado: un número no negativo. Se reporta en milisegundos y en
segundos (`milisegundos / 1000`). Este resultado incluye el intervalo de
detección de ProxySQL y el costo del cliente Docker usado para comprobarlo;
esa metodología debe mencionarse en el informe.

---

## 4. Generar operaciones antes y durante la falla

Este punto ya se ejecutó deliberadamente en los puntos 1 y 2:

- Previas: correos `fase8.previa.1` a `fase8.previa.5`.
- Durante: correos `fase8.durante.6` a `fase8.durante.10`.
- El archivo `operaciones.txt` indica cuáles recibieron confirmación.

Byron guarda el conteo disponible durante la falla:

```bash
docker run --rm --network host \
  -e MYSQL_PWD="$fase8_app_password" mysql:8.4 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
    SELECT COUNT(*) AS marcas_fase8
    FROM cliente
    WHERE correo LIKE 'fase8.%@example.com';" \
  | tee evidencias/fase8/resultados/conteo-durante.txt
```

Sirve para: comparar posteriormente las operaciones visibles.

---

## 5. Recuperar el nodo afectado

### Ejecuta: Byron

```bash
fase8_t2_iso=$(date --iso-8601=seconds)
fase8_t2_ms=$(date +%s%3N)
docker start mysql-node1
```

Cuando MySQL esté saludable, ejecutar sin bootstrap:

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
START GROUP_REPLICATION;
"'
```

Esperar hasta que nodo1 aparezca `ONLINE`:

```bash
while true; do
  estado=$(docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "
    SELECT MEMBER_STATE
    FROM performance_schema.replication_group_members
    WHERE MEMBER_HOST=@@report_host;"' 2>/dev/null)

  [ "$estado" = 'ONLINE' ] && break
  printf 'Estado actual: %s\n' "$estado"
  sleep 2
done

fase8_t3_iso=$(date --iso-8601=seconds)
fase8_t3_ms=$(date +%s%3N)
printf 'T2=%s epoch_ms=%s\nT3=%s epoch_ms=%s\n' \
  "$fase8_t2_iso" "$fase8_t2_ms" "$fase8_t3_iso" "$fase8_t3_ms" \
  | tee -a evidencias/fase8/resultados/tiempos.txt
```

Sirve para: medir por separado cuánto tarda nodo1 en reintegrarse.

---

## 6. Comparar información antes y después de la recuperación

Cada integrante ejecuta el mismo conteo en su nodo.

### Byron — nodo1

```bash
docker exec mysql-node1 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT correo,nombre FROM data_bugs.cliente
WHERE correo LIKE '\''fase8.%@example.com'\'' ORDER BY correo;
SELECT @@global.gtid_executed;
"'
```

### Michael — nodo2

```bash
docker exec mysql-node2 sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
SELECT correo,nombre FROM data_bugs.cliente
WHERE correo LIKE '\''fase8.%@example.com'\'' ORDER BY correo;
SELECT @@global.gtid_executed;
"'
```

### Carlos — nodo3

```powershell
docker exec -it mysql-nodo3 mysql -uroot -p -e "SELECT correo,nombre FROM data_bugs.cliente WHERE correo LIKE 'fase8.%@example.com' ORDER BY correo; SELECT @@global.gtid_executed;"
```

Resultado esperado: los tres muestran exactamente las mismas filas y el mismo
conjunto GTID.

> **CAPTURA F8-03:** comparación de filas y GTID de los tres nodos.

---

## 7. Determinar si existió pérdida de datos

Carlos compara `operaciones.txt` con las filas finales:

- Una operación marcada `EXITOSA` y ausente representa pérdida.
- Una operación marcada `FALLIDA` y ausente no representa pérdida confirmada.
- Una operación que dio error pero aparece se reporta como resultado ambiguo;
  nunca se reintenta sin una clave idempotente.

Registrar:

```text
confirmadas = ____
confirmadas presentes en los tres nodos = ____
confirmadas perdidas = ____
```

---

## 8. Estimar el RPO obtenido

Fórmula observada:

```text
RPO_operaciones = confirmadas - confirmadas presentes después
```

Si todas las confirmadas existen en los tres nodos:

```text
RPO observado = 0 operaciones confirmadas perdidas durante esta prueba
```

Esto no significa que cualquier falla posible garantice siempre RPO cero; es
el resultado del escenario controlado y la configuración probada.

Calcular también la reintegración:

```bash
fase8_reintegracion_ms=$((fase8_t3_ms - fase8_t2_ms))
printf 'Tiempo_reintegracion_ms=%s\n' "$fase8_reintegracion_ms" \
  | tee -a evidencias/fase8/resultados/tiempos.txt
```

> **CAPTURA F8-04:** RTO, tiempo de reintegración y RPO observado.

## Limpieza posterior — solo después de las capturas

```bash
docker run --rm --network host \
  -e MYSQL_PWD="$fase8_app_password" mysql:8.4 \
  mysql -h127.0.0.1 -P6033 -uapp_user -Ddata_bugs -e "
    DELETE FROM cliente WHERE correo LIKE 'fase8.%@example.com';"

unset fase8_app_password fase8_t0_iso fase8_t0_ms fase8_t1_iso fase8_t1_ms
unset fase8_t2_iso fase8_t2_ms fase8_t3_iso fase8_t3_ms
unset fase8_rto_ms fase8_reintegracion_ms
```

## Tabla para el informe

| Escenario | T0 | T1 | RTO servicio | T2 | T3 | Reintegración | Confirmadas | Perdidas | RPO |
|---|---|---|---:|---|---|---:|---:|---:|---:|
| Caída nodo1 | | | | | | | | | |
| Caída nodo2 (datos de F4/F6) | | | | | | | | | |

## Criterio de cierre

- [ ] Se registraron T0, T1, T2 y T3 con una misma metodología.
- [ ] RTO del servicio y tiempo de reintegración están separados.
- [ ] Se generaron y registraron operaciones antes/durante la falla.
- [ ] Los tres nodos terminaron con datos y GTID iguales.
- [ ] RPO se calculó usando operaciones confirmadas, no suposiciones.
- [ ] Resultados y capturas se añadieron a la bitácora.
