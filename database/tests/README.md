# Pruebas SQL

Ejecutar los archivos en este orden sobre un nodo inicial:

1. `../schema.sql`
2. `../data.sql`
3. `select.sql`
4. `insert.sql`
5. `update.sql`
6. `transaction.sql`
7. `consistency.sql`
8. `delete.sql`
9. `consistency.sql`

Para comprobar replicacion, ejecutar una prueba de escritura desde Nodo 1 y consultar el resultado desde Nodo 2 y Nodo 3. Repetir la prueba escribiendo desde Nodo 2.

El archivo `delete.sql` elimina solamente el cliente de prueba creado por `insert.sql`. No ejecutarlo antes de esa insercion.
