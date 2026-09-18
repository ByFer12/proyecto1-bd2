# Bitácora técnica de pruebas

## Qué implica

La bitácora no es una fase adicional que modifique el clúster. Es el registro
cronológico obligatorio de lo que realmente se ejecutó durante todas las
fases. Se completa inmediatamente después de cada prueba; no se reconstruye
de memoria al final.

Debe incluir replicación, fallos, recuperación, reintegración, carga,
monitoreo y RTO/RPO. Las guías `fase1.md` a `fase8.md` se pueden reutilizar
como procedimiento, pero la bitácora conserva el resultado real y enlaza la
evidencia real.

## Responsabilidad

- Carlos registra durante las pruebas de nodo1.
- Byron registra durante las pruebas de nodo2/nodo3.
- Michael valida horas, RTO y referencias de evidencia.
- Al terminar cada fase, los tres revisan y confirman la fila.

El responsable puede rotar, pero nunca se deja una prueba sin registrar.

## Campos obligatorios

| Campo | Qué escribir |
|---|---|
| Fecha y hora | Hora ISO con zona, por ejemplo salida de `date --iso-8601=seconds` |
| Fase | F1, F2, etc. |
| Nodo/componente | nodo1, nodo2, nodo3, ProxySQL, Tailscale, Prometheus, Grafana |
| Acción | Comando o prueba resumida |
| Resultado esperado | Comportamiento definido en la guía |
| Resultado obtenido | Salida real, incluso si fue error |
| Recuperación | Tiempo medido o `No aplica` |
| Evidencia | Ruta/nombre exacto de imagen o archivo |
| Observaciones | Decisión, causa, limitación o corrección |

## Plantilla maestra

Copiar una fila por acción importante:

| Fecha/hora | Fase | Nodo/componente | Acción realizada | Esperado | Obtenido | Recuperación | Evidencia | Observaciones |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## Ejemplo correcto

| Fecha/hora | Fase | Nodo/componente | Acción realizada | Esperado | Obtenido | Recuperación | Evidencia | Observaciones |
|---|---|---|---|---|---|---|---|---|
| 2026-09-18T14:00:00-06:00 | F3 | nodo1/ProxySQL | Detener `mysql-node1` | nodo2 mantiene escritura; nodo1 pasa a HG40 | `.39 SHUNNED`, `.24 ONLINE` | 4.2 s | `evidencias/fase3/F3-03.png` | Detección automática del monitor |

No copiar esos números como resultado propio; son solamente el formato.

## Qué registrar por fase

| Fase | Entradas mínimas |
|---|---|
| 1 | Red, tres nodos, Group Replication, roles y ProxySQL |
| 2 | CRUD, verificación cruzada, GTID y consistencia |
| 3 | Caída/reingreso de nodo1 y RTO |
| 4 | Caída/reingreso de nodo2 y RTO |
| 5 | Fallo múltiple, bloqueo de escritura y lectura de contingencia |
| 6 | Cada lote de carga, fallos, latencias y disponibilidad |
| 7 | Targets, dashboard normal/carga/falla/recuperación/contingencia |
| 8 | T0, T1, T2, T3, operaciones confirmadas, RTO y RPO |
| 9 | Escenario elegido durante la calificación y recuperación |

## Evidencias y reutilización

Una misma captura se puede citar en la bitácora y en el informe, pero no debe
presentarse como si demostrara dos eventos distintos. Por ejemplo, la captura
de tres nodos `ONLINE` al cierre de F3 también puede documentar el estado
inicial de F4 si la hora coincide y no hubo cambios entre ambas pruebas.

Formato de nombres recomendado:

```text
F<fase>-<numero>-<descripcion>-<fecha>.png
```

Ejemplo:

```text
F7-06-caida-nodo1-dashboard-20260918.png
```

## Cómo capturar horas comparables

Linux:

```bash
date --iso-8601=seconds
date +%s%3N
```

PowerShell:

```powershell
Get-Date -Format o
[DateTimeOffset]::Now.ToUnixTimeMilliseconds()
```

Sirve para: registrar una hora legible y otra numérica para restar. Para un
RTO, T0 y T1 se miden desde el mismo equipo y reloj; no se restan relojes de
computadoras diferentes.

## Reglas de calidad

- No incluir contraseñas, tokens, auth keys ni archivos privados.
- No cambiar un error real por el resultado que “debía” salir.
- Asociar cada RTO con T0, T1 y el método usado.
- Indicar si una métrica proviene del host, VM Docker o contenedor.
- Registrar correcciones relevantes y volver a capturar el resultado final.
- Mantener las imágenes originales en `evidencias/faseN/`.

## Cierre de bitácora

Antes de entregar:

- [ ] Todas las fases ejecutadas tienen fecha y resultado.
- [ ] Toda evidencia citada existe en el repositorio/entrega.
- [ ] Los RTO/RPO coinciden con Fase 8 y el informe.
- [ ] No hay secretos visibles.
- [ ] Los tres integrantes pueden explicar al menos una fila de cada fase.
