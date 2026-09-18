# Informe final — Arquitectura MySQL distribuida

## 1. Portada

- Curso y sección.
- Proyecto 1.
- Integrantes y carnés.
- Motor asignado: MySQL.
- Fecha de entrega.

## 2. Resumen ejecutivo

Problema, arquitectura implementada, resultado general y principales métricas.

## 3. Arquitectura

- Diagrama con tres hosts, IP Tailscale, puertos y ProxySQL.
- Justificación de MySQL Group Replication multi-primary.
- Nodo1/nodo2 como escritores y nodo3 como contingencia.
- ProxySQL como entrada única y punto único restante.

## 4. Configuración y seguridad

- Docker por host.
- Tailscale.
- GTID y Group Replication.
- Usuarios de mínimo privilegio.
- Manejo de secretos sin publicar contraseñas.

## 5. Fase 1 — Preparación

Seguir los ocho incisos oficiales y agregar las capturas F1 indicadas en
`avances/fase1.md`.

## 6. Fase 2 — Replicación normal

CRUD desde nodo1 y nodo2, verificación cruzada, GTID y consistencia final.

## 7. Fase 3 — Fallo de nodo1

Estado antes/durante/después, ProxySQL, operación desde nodo2, reintegración y
RTO.

## 8. Fase 4 — Fallo de nodo2

Estado antes/durante/después, operación desde nodo1, reintegración y RTO.

## 9. Fase 5 — Fallo múltiple

Pérdida de quórum, escrituras bloqueadas, lectura en nodo3 y recuperación.

## 10. Fase 6 — Carga

- Herramienta y configuración.
- Operaciones totales/exitosas/fallidas.
- Latencia antes, durante y después del fallo.

## 11. Fase 7 — Monitoreo

- Exporters, Prometheus y Grafana.
- CPU, memoria, disponibilidad, replicación y latencia.
- Capturas normal, carga, fallo y contingencia.

## 12. Fase 8 — RTO y RPO

Tabla de T0, T1, RTO, transacciones emitidas/confirmadas y RPO por escenario.

## 13. Fase 9 — Resiliencia para la calificación

Runbook breve de detección, continuidad y recuperación.

## 14. Resultados y limitaciones

- Resultados alcanzados.
- ProxySQL alojado en nodo1 como punto único restante.
- Dependencia de Tailscale y conectividad de los integrantes.
- Comportamiento sin quórum.

## 15. Mejoras implementadas y futuras

Separar claramente mejoras realmente probadas de propuestas como TLS, backups,
PITR, alertas externas o un segundo proxy.

## 16. Conclusiones

Relacionar disponibilidad, consistencia, recuperación, RTO/RPO y aprendizaje
del equipo.

## 17. Anexos

- Bitácora completa.
- Comandos principales.
- Configuraciones sin secretos.
- Scripts CRUD y de carga.
- Índice de evidencias.
