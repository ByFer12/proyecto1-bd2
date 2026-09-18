# Contexto de continuidad del proyecto

Este archivo permite retomar el trabajo con otra sesión o asistente sin volver
a diagnosticar desde cero. No contiene contraseñas, claves de Tailscale ni
otros secretos.

## Fuentes que se deben leer primero

1. `Proyecto 1 - Grupos de 3.md`: enunciado oficial.
2. `Plan_Trabajo_Proyecto1_Bases2_Grupo4.md`: plan interno y mejoras.
3. `nodes/node1/README.md`: bitácora técnica general.
4. `avances/fase1.md`: procedimiento y evidencia de la Fase 1.

La prioridad es completar las fases oficiales en orden. Las mejoras se dejan
para después de cumplir el enunciado obligatorio.

## Arquitectura confirmada

| Componente | Dirección | Estado/función |
|---|---|---|
| MySQL nodo1 | `100.113.38.39:3306` | Escritura y lectura |
| MySQL nodo2 | `100.126.57.24:3306` | Escritura y lectura |
| MySQL nodo3 | `100.107.61.57:3306` | Lectura/contingencia |
| ProxySQL clientes | `100.113.38.39:6033` | Punto de entrada |
| ProxySQL administración | `127.0.0.1:6032` | Solo local |

Group Replication usa MySQL 8.4, pila `MYSQL`, modo multi-primary y el puerto
`3306`. Nodo3 se protege con `read_only=1` y `super_read_only=1`.

## Estado comprobado el 18 de septiembre de 2026

- `mysql-node1` y `proxysql-db2` están saludables.
- Tailscale alcanza nodo2 y nodo3.
- Los tres nodos tienen el mismo conjunto GTID.
- Después de un apagado inesperado, nodo2 y nodo3 conservaron el grupo.
- Nodo1 regresó con `START GROUP_REPLICATION`, sin bootstrap.
- Los tres miembros quedaron `ONLINE / PRIMARY`.
- ProxySQL tiene servidores saludables y separa lecturas/escrituras.
- `app_user` está activo en runtime con `default_hostgroup=10`.
- La autenticación local de `app_user` funciona directamente en MySQL y a
  través de ProxySQL `127.0.0.1:6033`.
- Desde Windows ya se validó que `100.113.38.39:6033` es alcanzable por
  Tailscale.

## Diagnóstico de las pruebas remotas

La primera prueba desde nodo3 devolvió `ERROR 1045` porque se entregó a Carlos la
contraseña de otra cuenta del archivo privado, no la contraseña correspondiente
a `app_user`. Después se confirmó, sin imprimir secretos, que:

- la clave de `app_user` en `proxy/sql/mysql-users.sql` coincide con la de
  `proxy/sql/proxysql-admin.sql`;
- la clave registrada en `runtime_mysql_users` también coincide;
- MySQL y ProxySQL aceptan esa clave;
- el usuario permanece activo y en el hostgroup `10`.

Al utilizar después la contraseña correspondiente a `app_user`, Carlos se
autenticó correctamente por `100.113.38.39:6033` y ProxySQL dirigió el `SELECT`
a nodo3. Una primera salida mostró temporalmente `read_only=0`; la comprobación
remota final devolvió `read_only=1`. ProxySQL confirmó nodo3 `ONLINE`,
`read_only=YES`, viable, sin atraso y únicamente en HG 30. La implementación
funcional quedó completa; falta rotar secretos y repetir una captura limpia.

No se debe ejecutar la propuesta externa que usa `admin/admin` y cambia
`default_hostgroup` a `1`. El administrador real fue rotado, el hostgroup de
escritura del proyecto es `10` y nunca se deben incrustar secretos en comandos
compartidos.

## Seguridad pendiente antes de repetir la prueba

Durante el intercambio quedaron visibles contraseñas privadas. Deben
considerarse comprometidas y rotarse sin escribir sus valores en Markdown,
Git, capturas ni mensajes grupales.

Procedimiento seguro:

1. Generar nuevas contraseñas distintas para `proxysql_monitor` y `app_user`.
2. Colocarlas en los archivos privados ignorados
   `proxy/sql/mysql-users.sql` y `proxy/sql/proxysql-admin.sql`, respetando qué
   clave corresponde a cada cuenta.
3. Ejecutar `mysql-users.sql` en nodo1 para actualizar las cuentas MySQL.
4. Ejecutar `proxysql-admin.sql` por `127.0.0.1:6032` usando la credencial
   administrativa privada vigente.
5. Confirmar que se ejecutaron `LOAD ... TO RUNTIME` y `SAVE ... TO DISK`.
6. Validar sin mostrar secretos que el monitor ve los tres backends y que
   `app_user` autentica localmente por el puerto `6033`.
7. Enviar solamente la nueva clave de `app_user` a Carlos por un canal privado.

No borrar el volumen de ProxySQL ni volúmenes de MySQL para rotar claves.

## Última prueba para cerrar funcionalmente la Fase 1

Carlos debe ejecutar una sola vez en PowerShell:

```powershell
docker exec -it mysql-nodo3 mysql -h100.113.38.39 -P6033 -uapp_user -p -Ddata_bugs -e "SELECT @@report_host AS backend, @@server_id AS server_id, @@global.read_only AS read_only;"
```

Debe introducir la nueva contraseña solamente en el prompt `Enter password:`.
No se usa `-pCONTRASEÑA`.

La consulta puede llegar a nodo1, nodo2 o nodo3 porque los tres pertenecen al
hostgroup lector. El resultado y una captura completa constituyen la evidencia
remota final.

## Avance y siguiente orden

- Fase 1 funcional: `100 %`; falta la limpieza de credenciales expuestas y una
  captura remota sin secretos para el informe.
- Enunciado obligatorio: estimación técnica `33 %`.
- Plan completo con mejoras: estimación técnica `23 %`.

Después de cerrar la Fase 1:

1. Inventariar esquema y datos existentes sin ejecutar todavía cargas
   destructivas o duplicadas.
2. Utilizar `avances/fase2.md`.
3. Ejecutar y evidenciar CRUD desde nodo1 y después desde nodo2, verificando en
   los otros dos nodos.
4. Continuar secuencialmente con fallos, carga, monitoreo, RTO/RPO, simulacro e
   informe.

## Reglas críticas

- No ejecutar `docker compose down -v`.
- No borrar volúmenes ni `data/*`.
- No hacer bootstrap si existe algún miembro `ONLINE`.
- Nunca hacer bootstrap en más de un nodo.
- No modificar simultáneamente varias fases críticas.
- No imprimir secretos durante verificaciones.
- Documentar cada resultado confirmado en el archivo de su fase.
