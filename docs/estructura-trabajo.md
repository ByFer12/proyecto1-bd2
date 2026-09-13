# Estructura de trabajo

## Responsabilidad de Byron

- `database/`: esquema, datos y pruebas SQL compartidas.
- `nodes/node1/`: configuracion y ejecucion local del Nodo 1.
- `docs/architecture.md`: topologia, puertos y flujo de la solucion.
- `docs/desiciones-tecnicas.md`: razones para elegir MySQL, Group Replication, Docker y ProxySQL.
- `scripts/`: comandos repetibles de inicio, verificacion y pruebas.

## Responsabilidad de Michael

- `nodes/node2/`: configuracion del Nodo 2.
- `proxy/`: configuracion de ProxySQL y reglas de lectura/escritura.
- Evidencias de conectividad Tailscale y failover.

## Responsabilidad de Carlos

- `nodes/node3/`: configuracion del Nodo 3.
- `monitoring/`: Prometheus, Grafana y exporters.
- `load-tests/`: pruebas de carga y resultados.

## Regla de integracion

Los nodos pueden prepararse por separado. La red privada solo es necesaria para probar comunicacion entre hosts, Group Replication y failover. No se deben copiar contrasenas ni archivos `.env` al repositorio.
