# Arquitectura de Base de Datos Distribuida — Alta Disponibilidad, Replicacion y Tolerancia a Fallos
**Universidad de San Carlos de Guatemala**  
**Facultad de Ingenieria — Escuela de Ciencias y Sistemas**  
**Bases de Datos 2 — Proyecto 1 — Grupo 4**

---

## Integrantes del Equipo

| Integrante | Carnet / Rol | Nodo Asignado | Sistema Operativo | IP Red (Tailscale) |
|---|:---:|---|---|:---:|
| **Byron** | Coordinador / Arquitectura | **Nodo 1** (RW / Bootstrap / ProxySQL) | Ubuntu (Linux) | `100.113.38.39` |
| **Michael** | Replicacion / Failover | **Nodo 2** (RW / Replicacion Activa) | Debian (Linux) | `100.126.57.24` |
| **Carlos** | Contingencia / Carga | **Nodo 3** (RO / Solo Lectura) | Windows 11 | `100.107.61.57` |

---

## Indice General

1. [Resumen Ejecutivo de la Arquitectura](#1-resumen-ejecutivo-de-la-arquitectura)
2. [Topologia y Componentes](#2-topologia-y-componentes)
3. [Mecanismo de Replicacion (MySQL Group Replication)](#3-mecanismo-de-replicacion-mysql-group-replication)
4. [Capa de Balanceo y Failover (ProxySQL)](#4-capa-de-balanceo-y-failover-proxysql)
5. [Estructura del Repositorio](#5-estructura-del-repositorio)
6. [Resumen de Fases y Guias Operativas](#6-resumen-de-fases-y-guias-operativas)
7. [Resultados de Pruebas de Carga y Resiliencia (Fase 6)](#7-resultados-de-pruebas-de-carga-y-resiliencia-fase-6)
8. [Medicion de RTO y RPO (Fase 8)](#8-medicion-de-rto-y-rpo-fase-8)
9. [Mejoras Implementadas y Observabilidad Proactiva](#9-mejoras-implementadas-y-observabilidad-proactiva)
10. [Instrucciones de Despliegue y Arranque](#10-instrucciones-de-despliegue-y-arranque)

---

## 1. Resumen Ejecutivo de la Arquitectura

Este proyecto implementa una solucion integral de **alta disponibilidad (HA)**, **tolerancia a fallos** y **consistencia estricta de datos** sobre un cluster distribuido de **MySQL 8.4** desplegado en tres maquinas fisicas heterogeneas interconectadas mediante una malla VPN segura con **Tailscale**.

La arquitectura garantiza:
- **Cero perdida de transacciones confirmadas (RPO = 0):** Mediante consenso síncrono y quórum con Group Replication.
- **Conmutacion transparente ante fallos (RTO < 2 segundos):** A traves de ProxySQL como balanceador y monitor de capa 7.
- **Continuidad de negocio en contingencia severa:** Si ambos nodos de lectura/escritura fallan, el tercer nodo asume la operacion en modo de solo lectura estricta (`read_only=1`, `super_read_only=1`), previniendo condiciones de *split-brain*.

---

## 2. Topologia y Componentes

```text
                            [ CLIENTES / LOCUST ]
                                      |
                                      v (Puerto 6033)
                        +----------------------------+
                        |      PROXYSQL (Capa 7)     |
                        |      Host: 100.113.38.39   |
                        +----------------------------+
                                      |
                     +----------------+----------------+
                     | (Hostgroup 10)                  | (Hostgroup 30)
                     v (Escrituras)                    v (Lecturas)
        +-------------------------+       +-------------------------+
        |     NODO 1 (Byron)      |       |     NODO 3 (Carlos)     |
        |   IP: 100.113.38.39     |       |   IP: 100.107.61.57     |
        |   Rol: RW (Escritor)    |       |   Rol: RO (Read-Only)   |
        +-------------------------+       +-------------------------+
                     ^                                 ^
                     | (Consenso / Quorum síncrono)    |
                     +----------------+----------------+
                                      |
                                      v (Hostgroup 10 - RW)
                        +----------------------------+
                        |      NODO 2 (Michael)      |
                        |      IP: 100.126.57.24     |
                        |      Rol: RW (Escritor)    |
                        +----------------------------+
```

---

## 3. Mecanismo de Replicacion (MySQL Group Replication)

- **Pila de Comunicacion:** `communication_stack=MYSQL` (Puerto `3306`).
- **Modo:** Multi-Primary con consenso distribuido.
- **Identificador de Grupo (UUID):** `c395e8af-d580-4d6c-8574-a629027f1379`.
- **Politica de Seguridad de Arranque:** `group_replication_start_on_boot=OFF` para evitar partimiento de red (split-brain) tras apagados no coordinados.
- **Garantia Transaccional:** Uso obligatorio del motor `InnoDB` y claves primarias explicitas con validacion estricta de GTID (`enforce_gtid_consistency=ON`).

---

## 4. Capa de Balanceo y Failover (ProxySQL)

ProxySQL opera en el Nodo 1 desacoplando la aplicacion de las instancias físicas:
- **Puerto de Aplicacion (`6033`):** Entrada publica del balanceador con usuario `app_user`.
- **Puerto de Administracion (`6032`):** Base de datos SQLite interna en memoria para gestion de runtime y monitoreo.
- **Hostgroups Operativos:**
  - `HG 10 (Escritores):` Nodo 1 (`.39`) y Nodo 2 (`.24`).
  - `HG 30 (Lectores):` Nodo 3 (`.57`) y nodos de contingencia.
  - `HG 40 (SHUNNED):` Nodos degradados o caidos apartados del trafico.
- **Failover Automatico:** El proceso `proxysql_monitor` consulta la salud cada 2 segundos. Ante la caida de un escritor, conmuta las escrituras al segundo nodo sin intervencion humana.

---

## 5. Estructura del Repositorio

```text
.
├── avances/                   # Guias tecnicas detalladas por fase
│   ├── inicio.md              # Procedimiento de encendido y recuperacion
│   ├── fase1.md a fase5.md    # Infraestructura, replicacion y fallos individuales
│   ├── fase6.md               # Pruebas de carga controlada (Locust)
│   ├── fase7.md               # Monitoreo y observabilidad
│   └── fase8.md               # Medicion formal de RTO y RPO
├── database/                  # Definicion de datos y pruebas SQL
│   ├── schema.sql             # Esquema DDL (cliente, producto, pedido, detalle, pago)
│   ├── data.sql               # Semilla DML inicial
│   ├── load/locust/           # Dockerfile y locustfile.py de carga
│   └── tests/                 # Scripts CRUD y validacion de consistencia
├── docs/                      # Documentacion de diseno y arquitectura
│   ├── architecture.md        # Especificacion formal de la arquitectura
│   └── desiciones-tecnicas.md # Registro de decisiones arquitectonicas (ADR)
├── evidencias/                # Registro fotografico y datasets CSV
│   ├── fase6/resultados/      # Salidas CSV de pruebas Locust
│   └── snapshots/             # Capturas de consistencia y GTID
├── nodes/                     # Configuraciones de cada nodo fisico
│   └── node1/conf/my.cnf      # Configuracion de MySQL 8.4 para Nodo 1
├── proxy/                     # Configuracion de ProxySQL
│   ├── conf/proxysql.cnf      # Parametros de interfaz y memoria
│   └── docker-compose.yml     # Orquestacion del contenedor de balanceo
└── scripts/                   # Herramientas de observabilidad y control
    ├── semaforo.sh            # Diagnostico de salud integral en 1 segundo
    ├── backup_gtid.sh         # Snapshot de GTID y consistencia de tablas
    ├── dashboard_terminal.py  # Visualizador de flujo en terminal (ASCII en tiempo real)
    └── alertas/               # Sistema centinela proactivo con bots de Telegram
```

---

## 6. Resumen de Fases y Guias Operativas

| Fase | Descripcion Tecnica | Documento de Referencia |
|:---:|---|---|
| **Fase 1** | Infraestructura VPN Tailscale, MySQL 8.4 y despliegue de ProxySQL | [avances/fase1.md](avances/fase1.md) |
| **Fase 2** | Validacion de replicacion normal y consistencia CRUD cruzada | [avances/fase2.md](avances/fase2.md) |
| **Fase 3** | Tolerancia a fallos: caida de Nodo 1 y conmutacion hacia Nodo 2 | [avances/fase3.md](avances/fase3.md) |
| **Fase 4** | Tolerancia a fallos: caida de Nodo 2 y absorcion por Nodo 1 | [avances/fase4.md](avances/fase4.md) |
| **Fase 5** | Fallo multiple, aislamiento de Split-Brain y contingencia en Nodo 3 | [avances/fase5.md](avances/fase5.md) |
| **Fase 6** | Pruebas de carga controlada y medicion de degradacion bajo estres | [avances/fase6.md](avances/fase6.md) |
| **Fase 7** | Monitoreo y observabilidad con Prometheus, Grafana y Exporters | [avances/fase7.md](avances/fase7.md) |
| **Fase 8** | Medicion y analisis matematico de RTO y RPO | [avances/fase8.md](avances/fase8.md) |
| **Fase 9** | Simulacion de resiliencia en vivo durante la defensa tecnica | [avances/fase9.md](avances/fase9.md) |
| **Fase 10**| Informe tecnico final consolidado | [informe/](informe/) |

---

## 7. Resultados de Pruebas de Carga y Resiliencia (Fase 6)

Las pruebas se ejecutaron utilizando Locust (10 usuarios concurrentes, 60 segundos por escenario, 75% lecturas / 25% escrituras):

| Escenario Evaluado | Solicitudes Totales | Fallos Registrados | Latencia Media | Percentil 95 (p95) | Disponibilidad Real |
|---|---:|---:|---:|---:|---:|
| **A: Caida de Nodo 1 (s. 30)** | 2,312 | 70 | 121.57 ms | 410 ms | **96.97 %** |
| **B: Caida de Nodo 2 (s. 30)** | 2,808 | 39 | 78.25 ms | 270 ms | **98.61 %** |
| **C: Contingencia en Nodo 3** | 4,510 | 0 | 0.59 ms | 1 ms | **100.00 %** |

**Hallazgos Clave:**
- La conmutacion de ProxySQL ocurre en menos de 2 segundos.
- Los fallos registrados correspondieron a deadlocks transaccionales por concurrencia en la misma fila de stock, no a perdida de conectividad de red.
- En contingencia (Nodo 1 y 2 apagados), Nodo 3 soporto mas de 4,500 lecturas directas con 0 errores y latencia sub-milisegundo.

---

## 8. Medicion de RTO y RPO (Fase 8)

- **RTO (Recovery Time Objective):** Tiempo medido desde el apagado del contenedor (`T0`) hasta la confirmacion de la primera transaccion exitosa redirigida (`T1`).
  - **Resultado en Clúster:** **1.5 a 2.5 segundos** (equivalente al `monitor_ping_interval` de ProxySQL).
- **RPO (Recovery Point Objective):** Transacciones confirmadas perdidas.
  - **Resultado en Clúster:** **0 transacciones perdidas**. La replicacion síncrona garantiza que toda transaccion confirmada existe en mas de un nodo antes de responder al cliente.

---

## 9. Mejoras Implementadas y Observabilidad Proactiva

Adicional a los requisitos base, se incorporaron herramientas avanzadas de administracion:

1. **Centinela Proactivo en Telegram (`scripts/alertas/monitor_telegram.py`):**
   - Monitorea ProxySQL cada 2 segundos.
   - Despacha notificaciones push individuales e instantaneas a los telefonos de Byron, Michael y Carlos informando caidas, RTO estimado, RPO y restauraciones.
2. **Dashboard de Terminal en Tiempo Real (`scripts/dashboard_terminal.py`):**
   - Visualizador ASCII en vivo del flujo de consultas desde ProxySQL hacia los nodos activos.
3. **Diagnostico Rapido (`scripts/semaforo.sh`):**
   - Script de comprobacion integral de 1 segundo para pre-vuelo antes de pruebas.

---

## 10. Instrucciones de Despliegue y Arranque

### Arranque ordenado tras reinicio de computadoras:

1. **En Nodo 1 (Byron):**
   ```bash
   sudo systemctl start tailscaled
   docker start mysql-node1 proxysql-db2
   docker exec mysql-node1 mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
   SET GLOBAL group_replication_bootstrap_group=ON;
   START GROUP_REPLICATION;
   SET GLOBAL group_replication_bootstrap_group=OFF;
   "
   ```

2. **En Nodo 2 (Michael):**
   ```bash
   docker start mysql-node2
   docker exec mysql-node2 mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "START GROUP_REPLICATION;"
   ```

3. **En Nodo 3 (Carlos):**
   ```powershell
   docker exec -it mysql-nodo3 mysql -uroot -p -e "START GROUP_REPLICATION;"
   ```

4. **Verificacion Global:**
   ```bash
   ./scripts/semaforo.sh
   ```
