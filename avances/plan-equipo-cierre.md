# Plan coordinado del equipo — cierre del proyecto

## Situación actual

- Fase 1 funcional: completa.
- Tres nodos: `ONLINE`.
- Proxy utilizado: ProxySQL, no HAProxy.
- Nodo1 y nodo2: lectura/escritura.
- Nodo3: contingencia con `read_only=1` y `super_read_only=1`.
- Pendiente inmediato: rotar secretos expuestos y repetir una captura remota
  sin escribir la contraseña en el comando.
- Fase 2 iniciada: línea base exacta e idéntica en los tres nodos; lista para
  ejecutar el primer INSERT desde nodo1.
- Entrega: sábado 19 de septiembre de 2026. La mañana debe terminar con tiempo
  suficiente para empaquetar y enviar antes de las 15:00.
- Después de apagar todos los equipos, el arranque se realiza siguiendo
  `avances/inicio.md`; no se improvisa bootstrap.

## Mensaje breve para el grupo

> Equipo: ya tenemos los tres MySQL ONLINE, replicación funcionando, nodo3 en
> solo lectura y ProxySQL como entrada única por el puerto 6033. Si una máquina
> se apaga, primero revisamos Docker, Tailscale y qué miembros siguen ONLINE.
> Si queda algún miembro ONLINE, el nodo recuperado entra solo con
> START GROUP_REPLICATION; no hacemos bootstrap. Bootstrap se usa una sola vez
> y únicamente cuando todo el grupo está apagado, después de comparar GTID.
> Nadie debe borrar volúmenes, usar down -v o cambiar configuraciones durante
> una prueba sin avisar. Trabajaremos en paralelo preparando scripts,
> monitoreo y evidencia, pero CRUD y fallos los ejecutaremos juntos y en orden.

## Regla de operación durante pruebas conjuntas

| Rol | Responsable | Acción |
|---|---|---|
| Operador SQL e integración | Byron | Ejecuta CRUD, consulta membresía y decide recuperación |
| Operador de fallos y proxy | Michael | Detiene/inicia su nodo, observa ProxySQL y registra tiempos |
| Monitor y evidencia | Carlos | Observa métricas, ejecuta verificaciones en nodo3 y toma capturas |

Solo una persona da la orden de detener o iniciar un nodo. Antes de cada prueba
se escribe en el chat `INICIO FASE N`; al terminar se escribe `FIN FASE N` con
resultado y evidencia.

## Trabajo que sí puede hacerse en paralelo

### Byron — datos, Fase 2 e integración

1. Inventariar tablas y filas actuales de `data_bugs` sin modificarlas.
2. Revisar `database/tests/*.sql` y asegurar que las pruebas sean repetibles.
3. Preparar `avances/fase2.md` con comandos, esperado y evidencia.
4. Durante la prueba conjunta, ejecutar CRUD primero desde nodo1 y después
   coordinar CRUD desde nodo2.
5. Integrar documentación y revisar que Git no contenga secretos.

Entregable: Fase 2 reproducible y verificada en los tres nodos.

### Michael — fallos, ProxySQL y recuperación

Sin apagar nada todavía:

1. Preparar checklist de Fases 3, 4 y 5.
2. Preparar comandos para observar hostgroups de ProxySQL antes/durante/después.
3. Preparar cronómetro y tabla con T0, T1 y RTO.
4. Confirmar que sabe recuperar nodo2: Tailscale, contenedor, JOIN sin
   bootstrap y validación `ONLINE`.
5. Durante la prueba conjunta, ejecutar únicamente las detenciones y arranques
   autorizados.

Entregable: procedimiento de fallo/reintegración y tiempos registrados.

### Carlos — monitoreo, carga y evidencia

Sin generar carga todavía:

1. Revisar exporters, Prometheus y Grafana existentes.
2. Preparar dashboard con CPU, memoria, disponibilidad, replicación y latencia.
3. Preparar el script de carga, pero no ejecutarlo hasta recibir la orden.
4. Crear carpetas/listado de capturas por fase.
5. Preparar una tabla de operaciones totales, exitosas, fallidas y latencia.
6. Durante las pruebas conjuntas, observar nodo3 y guardar evidencia.

Entregable: monitoreo visible, script de carga y capturas identificadas.

## Trabajo que no debe hacerse en paralelo

- Formar o reiniciar Group Replication.
- Activar bootstrap.
- Ejecutar escrituras de las pruebas oficiales.
- Detener nodo1 o nodo2.
- Cambiar usuarios, contraseñas o reglas ProxySQL.
- Ejecutar la carga.
- Hacer `git pull` o fusionar cambios que modifiquen configuraciones activas.

Estas acciones requieren que los tres estén conectados y que una sola persona
coordine el orden.

## Secuencia conjunta mínima

### Bloque 1 — Seguridad y evidencia de Fase 1

1. Rotar las credenciales expuestas.
2. Confirmar tres miembros `ONLINE`.
3. Confirmar nodo3 en solo lectura.
4. Repetir la consulta remota por ProxySQL usando `-p` interactivo.
5. Guardar la captura sin secretos.

### Bloque 2 — Fase 2: replicación normal

1. CRUD desde nodo1.
2. Verificación en nodo2 y nodo3.
3. CRUD desde nodo2.
4. Verificación en nodo1 y nodo3.
5. Guardar antes/después, membresía y logs.

### Bloque 3 — Fases 3, 4 y 5: fallos

1. Fallo de nodo1, servicio por nodo2, verificación en nodo3 y reintegración.
2. Fallo de nodo2, servicio por nodo1, verificación en nodo3 y reintegración.
3. Fallo simultáneo de nodo1/nodo2, rechazo de escritura y lectura por nodo3.
4. Recuperar primero un escritor y después el nodo restante.
5. Registrar T0, T1, RTO y posible pérdida de datos en cada escenario.

### Bloque 4 — Fases 6, 7 y 8

Ejecutarlas juntas para no repetir trabajo:

1. Carga baseline con monitoreo.
2. Carga y caída de nodo1.
3. Carga y caída de nodo2.
4. Solo lecturas con nodo1/nodo2 apagados.
5. Capturar dashboard, operaciones, errores, latencia, RTO y RPO.

### Bloque 5 — Fases 9 y 10

1. Simulacro corto de una falla escogida al azar.
2. Cada integrante explica su componente y recuperación.
3. Consolidar informe, bitácora, diagrama, scripts y capturas.

## Horario recomendado

### Desde ahora

- Cerrar seguridad/evidencia de Fase 1.
- Completar Fase 2 juntos.
- En paralelo: Michael prepara fallos y Carlos prepara monitoreo/carga.
- Ejecutar Fases 3–5 si el monitoreo básico ya permite registrar el estado.

### Sábado por la mañana

- 08:00: encendido y comprobación de salud.
- 08:30–10:30: carga, monitoreo, RTO/RPO.
- 10:30–11:30: simulacro de calificación.
- 11:30–13:00: informe, bitácora y evidencias.
- 13:00–14:00: revisión final y empaquetado.
- 14:00: congelar cambios y dejar margen para enviar antes de las 15:00.

## Protocolo Git para no estorbarse

1. Cada integrante trabaja solamente en su carpeta o rama asignada.
2. Nadie sobrescribe `.env`, datos o configuraciones privadas de otro nodo.
3. Antes de hacer pull: `git status --short --branch`.
4. No hacer pull durante una prueba activa.
5. Byron integra cambios después de terminar cada bloque.
6. Nunca subir contraseñas, claves Tailscale, datos de volúmenes o capturas que
   muestren secretos.

## Criterio para avanzar

No se inicia la siguiente prueba destructiva hasta que:

- el escenario anterior terminó;
- los tres nodos volvieron al estado esperado;
- el resultado quedó documentado;
- las capturas tienen nombre y responsable;
- el grupo confirmó en el chat que se puede continuar.
