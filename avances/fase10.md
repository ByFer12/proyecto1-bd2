# Fase 10 — Informe final y entrega

## Objetivo oficial

Consolidar arquitectura, configuraciones, pruebas, métricas, RTO/RPO,
bitácora, limitaciones y conclusiones en un informe reproducible y sin
secretos.

El borrador se encuentra en `informe/informe-final.md`. Esta guía indica qué
agregar y quién lo prepara; no se inventan resultados que todavía no hayan
sido ejecutados.

## Reparto recomendado

| Responsable | Apartados iniciales |
|---|---|
| Byron | Arquitectura, red, ProxySQL, Fases 1/3/8 |
| Michael | Configuración nodo2, Fases 4/6, ventajas y limitaciones |
| Carlos | Nodo3, monitoreo, Fases 2/5/7, edición de evidencias |
| Los tres | Fase 9, mejoras, conclusiones y revisión oral |

Asignar secciones acelera la redacción, pero los tres deben leer y comprender
el documento completo.

---

## 1. Introducción — redacta Carlos

Incluir problema de Data Bug's, riesgo del servidor único, objetivo de alta
disponibilidad y alcance de la demostración.

Resultado esperado: uno o dos párrafos propios, no una copia del enunciado.

## 2. Arquitectura implementada — redacta Byron

Describir tres hosts independientes, MySQL 8.4, Group Replication
multi-primary, Tailscale, ProxySQL y Prometheus/Grafana.

Insertar diagrama con flujo:

```text
Cliente -> ProxySQL (.39:6033) -> nodo1/nodo2 escritores
                              -> nodo3 lectura/contingencia
Tres MySQL <-> Group Replication sobre Tailscale:3306
Exporters -> Prometheus -> Grafana
```

No presentar ProxySQL como redundante: actualmente vive en el equipo de nodo1.

## 3. Topología de red — redacta Byron

Tabla mínima:

| Componente | IP privada | Puertos | Propósito |
|---|---|---|---|
| nodo1 | `100.113.38.39` | 3306 | MySQL escritor |
| nodo2 sidecar | `100.126.57.24` | 3306 | MySQL escritor |
| nodo3 | `100.107.61.57` | 3306 | lectura/contingencia |
| ProxySQL | `100.113.38.39` | 6033/6032 local | datos/admin |
| Exporters | Por nodo | 9104/9100 | MySQL/sistema |
| Prometheus/Grafana | nodo3 | 9090/3000 | métricas/dashboard |

Explicar que `.122` es el Tailscale del host de Michael, pero MySQL del
proyecto utiliza `.24` del sidecar.

## 4. Función de cada nodo — redactan los tres

- Nodo1 y nodo2: lectura/escritura, miembros `PRIMARY` multi-primary.
- Nodo3: miembro replicado mantenido con `super_read_only=ON` para contingencia.
- ProxySQL: distribución y aislamiento de miembros no saludables.
- Monitoreo: observación, no participa en la consistencia.

## 5. Replicación utilizada — redacta Michael

Explicar Group Replication, GTID, pila `MYSQL`, grupo compartido, recuperación
distribuida, quórum y razón para bloquear escrituras sin mayoría. Citar las
configuraciones reales `nodes/node*/conf/my.cnf` sin copiar secretos.

## 6. Proxy o balanceador — redacta Byron

Documentar ProxySQL, puerto de aplicación `6033`, administrador local `6032`,
usuario monitor y hostgroups:

- HG10: escritores.
- HG20: respaldo de escritores.
- HG30: lectores.
- HG40: aislados/`SHUNNED`.

Incluir captura normal y de detección de fallo. No publicar credenciales.

## 7. Estrategia de failover — redactan Byron y Michael

Explicar detección de ProxySQL, continuidad con el escritor restante,
protección de nodo3, `START GROUP_REPLICATION` para reintegro y bootstrap solo
cuando todo el grupo está detenido y se comparó GTID.

Referenciar `avances/inicio.md`, no pegar sus comandos completos en el cuerpo;
pueden colocarse en anexos.

## 8. Resultados de replicación — redacta Carlos

Usar únicamente datos ejecutados en Fase 2:

- CRUD y verificación cruzada.
- GTID de los tres miembros.
- resultado de `consistency.sql` (el éxito puede ser salida vacía).
- captura de tres `ONLINE`.

## 9. Fallas de nodo1 y nodo2 — redactan Byron y Michael

Crear una subsección por Fase 3 y Fase 4 con:

- estado antes/durante/después;
- operación que continuó;
- cambio en ProxySQL;
- reintegración;
- RTO medido.

No reutilizar el mismo valor de RTO para fallos diferentes.

## 10. Falla simultánea — redacta Carlos

Resumir Fase 5: pérdida de quórum, rechazo obligatorio de escrituras, datos
legibles directamente en nodo3 `1/1` y recuperación gradual de escritores.

## 11. Pruebas de carga — redacta Michael

Usar la tabla real de Fase 6:

- herramienta y parámetros;
- operaciones totales;
- completadas antes/después;
- fallidas;
- promedio, mínimo y máximo;
- disponibilidad calculada;
- comparación normal/falla/contingencia.

Adjuntar archivos de resultados, no solo capturas.

## 12. Monitoreo y métricas — redacta Carlos

Describir exporters, Prometheus, Grafana, intervalo de scrape y paneles. Incluir
capturas de Fase 7: normal, carga, caída, recuperación y contingencia.

Declarar que en Docker Desktop las métricas de `node_exporter` representan la
VM Linux de Docker, no necesariamente todo el host físico.

## 13. RTO y RPO — redacta Byron; valida Carlos

Copiar la tabla calculada en Fase 8 con T0/T1/T2/T3, metodología, unidades,
operaciones confirmadas/perdidas y RPO observado. Diferenciar recuperación del
servicio y reintegración del nodo.

## 14. Bitácora — mantiene Carlos

Insertar o anexar la tabla de `avances/bitacora.md`. Toda evidencia citada debe
existir y conservar su nombre original.

## 15. Ventajas y limitaciones — redactan los tres

### Ventajas comprobadas

- Datos replicados en tres hosts independientes.
- Continuidad de escritura ante la caída de un escritor.
- Contingencia de lectura protegida.
- Aislamiento automático por ProxySQL.
- Observación de fallos y recuperación.

### Limitaciones reales

- ProxySQL y su IP son un punto único de acceso.
- Dependencia de Tailscale, Internet y equipos de estudiantes.
- Sin quórum se bloquean escrituras.
- `super_read_only` de nodo3 se reafirma manualmente tras ciertos reinicios.
- Métricas del host limitadas por Docker Desktop.
- No se implementó todavía backup/PITR ni TLS entre todos los componentes, si
  esas mejoras no fueron realmente probadas.

## 16. Mejoras futuras — redacta Michael

Proponer, sin afirmar que ya existe:

- segundo ProxySQL con IP virtual o balanceador externo;
- automatizar protección/reingreso de nodo3;
- TLS y rotación centralizada de secretos;
- alertas de Grafana/Prometheus;
- backups verificados y recuperación a punto en el tiempo;
- hosts permanentes o nube para reducir dependencia de laptops.

## 17. Conclusiones — redactan los tres

Relacionar evidencias con disponibilidad, consistencia, failover, RTO/RPO y
limitaciones. Cada integrante aporta una conclusión técnica breve.

---

## Anexos y archivos de entrega

Incluir:

- configuraciones `.example` sin secretos;
- scripts de base de datos y carga;
- guías de `avances/`;
- índice de evidencias;
- bitácora completa;
- resultados de texto de Fases 6/8;
- diagrama de arquitectura;
- historial de al menos cinco commits significativos.

## Revisión de seguridad — ejecuta Byron

Desde la raíz:

```bash
git status --short
git ls-files | grep -E '(^|/)(\.env|\.my\.cnf|proxysql\.cnf)$' \
  && echo 'REVISAR: posible archivo privado versionado' \
  || echo 'OK: no se detectaron archivos privados conocidos'
```

Luego los tres revisan visualmente imágenes y Markdown. No buscar ni imprimir
valores de contraseñas en la terminal durante una captura.

## Validación de enlaces y formato — ejecuta Byron

```bash
git diff --check
find avances evidencias informe -type f -name '*.md' -print | sort
```

Esperado: `git diff --check` sin salida y todos los documentos listados.

## Reutilización de evidencia

- Una captura existente puede citarse en el informe y la bitácora.
- No se repite una fase solo para producir una captura si el archivo original
  muestra claramente comando, resultado y fecha.
- Si falta una medición obligatoria, sí se repite únicamente esa prueba bajo
  condiciones controladas.
- Fase 9 usa resultados de Fases 3–8 para explicar la respuesta, pero debe
  registrar por separado el escenario que realmente seleccione el auxiliar.

## Criterio de cierre

- [ ] Están los 17 contenidos exigidos por el enunciado.
- [ ] Cada afirmación importante tiene evidencia o resultado asociado.
- [ ] RTO/RPO y bitácora coinciden entre sí.
- [ ] Ventajas comprobadas y mejoras futuras están separadas.
- [ ] No hay contraseñas, tokens ni auth keys en Git o capturas.
- [ ] Hay al menos cinco commits significativos.
- [ ] Los tres integrantes revisaron el informe y practicaron Fase 9.
