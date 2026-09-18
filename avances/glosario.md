# Glosario práctico del proyecto

Este glosario explica los términos utilizados durante la configuración y las
pruebas. Está pensado para que cualquier integrante pueda explicar el proyecto
durante la evaluación.

## Conceptos principales

### Nodo

Una computadora o instancia de MySQL que participa en la arquitectura.

- Nodo1: Byron, `100.113.38.39`.
- Nodo2: Michael, sidecar Tailscale `100.126.57.24`.
- Nodo3: Carlos, `100.107.61.57`.

### Clúster

Conjunto de los tres nodos MySQL trabajando como un solo sistema replicado. Un
nodo puede apagarse y los demás conservar el servicio, dependiendo del quórum
y del escenario de fallo.

### MySQL Group Replication

Mecanismo que comunica los nodos, replica las transacciones y mantiene una
vista de cuáles miembros pertenecen al grupo. En este proyecto funciona en
modo multi-primary con pila de comunicación `MYSQL` por el puerto `3306`.

### Bootstrap

Operación que crea la primera vista del grupo cuando **no existe ningún grupo
activo**. No significa iniciar MySQL ni crear la base de datos.

Debe ejecutarse en un solo nodo y solo cuando se confirmó que todos están
`OFFLINE`. Después de `START GROUP_REPLICATION`, la variable debe volver a
`OFF` inmediatamente.

Si dos nodos hacen bootstrap por separado pueden formar grupos independientes
(`split-brain`) y aceptar datos incompatibles.

Resumen:

```text
Hay al menos un grupo ONLINE  -> JOIN sin bootstrap.
Todos están OFFLINE           -> comparar GTID y hacer un solo bootstrap.
```

### JOIN o reincorporación

Entrada de un nodo a un grupo que ya existe mediante:

```sql
START GROUP_REPLICATION;
```

El nodo obtiene las transacciones que le falten y normalmente pasa por
`RECOVERING` antes de quedar `ONLINE`.

### `STOP GROUP_REPLICATION`

Retira ordenadamente una instancia del grupo, pero mantiene MySQL encendido y
no elimina sus datos. Es recomendable antes de apagar, aunque un apagado normal
sin este comando no destruye el volumen. No debe confundirse con `docker stop`,
que detiene el contenedor completo.

### GTID

Significa **Global Transaction Identifier**. Es el identificador único que
MySQL asigna a cada transacción replicada. Permite saber qué operaciones posee
cada nodo y cuáles le faltan.

Ejemplo conceptual:

```text
uuid-del-grupo:1-25
```

Significa que el nodo ha ejecutado las transacciones 1 a 25 de ese origen. Al
recuperar un clúster completamente apagado se comparan los GTID para evitar
iniciar el grupo desde un nodo atrasado.

### `gtid_executed`

Conjunto de todos los GTID ejecutados por un servidor:

```sql
SELECT @@global.gtid_executed;
```

No debe confundirse con la cantidad de filas ni con el contenido visible de
una tabla.

### `GTID_SUBSET`

Función que comprueba si un conjunto GTID está contenido en otro. Devuelve `1`
si todas las transacciones del primer conjunto existen en el segundo y `0` si
falta alguna.

Se usa para elegir de manera segura el nodo más actualizado cuando los GTID no
son idénticos.

### Quórum

Mayoría de miembros necesaria para que el grupo tome decisiones de forma
segura. En un grupo de tres nodos, normalmente se necesitan dos comunicándose.
Si queda solo uno, puede perder la vista operativa para impedir escrituras
inseguras.

### Split-brain

Situación peligrosa donde dos grupos independientes creen ser el grupo válido
y aceptan escrituras diferentes. Se evita usando bootstrap en un único nodo y
uniendo los demás sin bootstrap.

## Estados y roles

### `ONLINE`

El miembro pertenece al grupo y está listo para trabajar.

### `RECOVERING`

El miembro está descargando o aplicando transacciones faltantes. Hay que
esperar; todavía no se considera listo para las pruebas.

### `OFFLINE`

MySQL puede estar encendido, pero el servidor no pertenece actualmente al
grupo de replicación.

### `ERROR`

El nodo intentó incorporarse y falló. Se revisan los logs y la conectividad;
no se repite `START` indefinidamente.

### `PRIMARY`

En este proyecto indica que el miembro puede aceptar escrituras porque el
grupo está configurado como multi-primary. No significa que solo exista un
servidor principal.

### Multi-primary

Modo en el cual nodo1 y nodo2 pueden aceptar escrituras. Group Replication
certifica las transacciones para evitar conflictos. Nodo3 se protege
manualmente como solo lectura aunque forme parte del mismo grupo.

## Protección y recuperación

### `read_only`

Impide escrituras de usuarios normales, pero ciertos usuarios privilegiados
todavía podrían escribir.

### `super_read_only`

Protección más estricta que también bloquea escrituras administrativas. En
nodo3 deben estar ambos valores en `1` después de cada arranque o JOIN.

### Recovery channel

Canal interno `group_replication_recovery` utilizado para que un nodo nuevo o
atrasado descargue las transacciones que le faltan. Usa el usuario `repl`.

### Usuario `repl`

Cuenta técnica de MySQL con permisos de replicación y recuperación. No es el
usuario de la aplicación ni debe usarse para consultas normales.

### Persistencia

Los datos sobreviven a reinicios porque MySQL y Tailscale utilizan volúmenes
Docker. `docker compose down` no debería borrar esos datos, pero
`docker compose down -v`, `docker volume rm` o borrar `data/*` sí podría
destruirlos.

## Red y contenedores

### Tailscale

VPN privada que permite que los tres equipos se comuniquen sin publicar MySQL
directamente en Internet.

### Tailnet

Red privada lógica de Tailscale donde deben aparecer los tres integrantes y el
sidecar del nodo2.

### Sidecar Tailscale del nodo2

Contenedor `tailscale-node2` que comparte su espacio de red con
`mysql-node2`. Por eso MySQL nodo2 utiliza `100.126.57.24`, no la IP
`100.109.4.122` del Tailscale instalado en el host de Michael.

### Pila de comunicación `MYSQL`

Modo usado por Group Replication para comunicarse a través del protocolo y
puerto MySQL. En la configuración final las direcciones locales y semillas
usan el puerto `3306`.

### Seed o semilla

Dirección conocida que un nodo intenta contactar para encontrar un grupo
existente. Las semillas ayudan a descubrir el grupo, pero no crean el grupo ni
reemplazan el bootstrap.

### Puerto `3306`

Puerto MySQL de los nodos y, con la pila `MYSQL`, puerto de comunicación del
grupo en esta implementación.

### Puerto `6033`

Puerto de ProxySQL utilizado por los clientes y por la aplicación para acceder
a la base de datos.

### Puerto `6032`

Puerto administrativo de ProxySQL. Debe permanecer accesible solo localmente
y no se usa como entrada de la aplicación.

## Proxy y balanceo

### ProxySQL

Proxy utilizado por el proyecto. Recibe conexiones en nodo1 y las dirige a un
backend adecuado según disponibilidad y reglas. No se está utilizando
HAProxy.

### Backend

Servidor MySQL real al que ProxySQL envía una consulta: nodo1, nodo2 o nodo3.

### Hostgroup

Grupo lógico de servidores dentro de ProxySQL:

- HG10: servidores de escritura.
- HG30: servidores de lectura.
- HG40: servidores apartados o no disponibles.

### Usuario `app_user`

Cuenta usada por la aplicación o por las pruebas a través del puerto `6033`.
Tiene permisos CRUD sobre `data_bugs`, pero no permisos administrativos.

### Usuario `proxysql_monitor`

Cuenta que ProxySQL utiliza para consultar el estado de MySQL y Group
Replication. No se utiliza para ejecutar el CRUD del proyecto.

### Punto único de fallo (SPOF)

Componente cuya caída interrumpe una función completa. Actualmente ProxySQL
está alojado en nodo1; si se apaga toda la computadora de Byron, el puerto
`6033` deja de existir aunque otro MySQL continúe activo. Las fases de fallo
detienen el contenedor MySQL de nodo1, no toda la computadora, para mantener el
proxy disponible.

## Pruebas y mediciones

### CRUD

Las cuatro operaciones básicas:

- `CREATE`/`INSERT`: crear datos.
- `READ`/`SELECT`: leer datos.
- `UPDATE`: modificar datos.
- `DELETE`: eliminar datos.

### Consistencia

Comprobación de que los nodos muestran el mismo resultado después de replicar
una transacción.

### RTO

Tiempo que tarda el servicio en recuperarse después de una falla.

### RPO

Cantidad de datos que podrían perderse por una falla. En las pruebas se
comprueba comparando GTID y contenido replicado.

### Evidencia

Captura o salida guardada que demuestra una condición del enunciado. Debe
mostrar el comando, el resultado relevante y el momento lógico de la prueba,
sin revelar contraseñas, claves Tailscale ni otros secretos.

## Regla mental para recuperación

```text
Primero red y Docker.
Después GTID y membresía.
Si hay grupo ONLINE: JOIN.
Si todos están OFFLINE: un solo bootstrap.
Luego tres ONLINE, nodo3 protegido y ProxySQL operativo.
```
