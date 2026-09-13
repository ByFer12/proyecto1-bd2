USE data_bugs;

START TRANSACTION;

UPDATE producto
SET stock = stock - 1
WHERE nombre = 'Adaptador USB-C'
  AND stock > 0;

UPDATE pedido
SET estado = 'PAGADO'
WHERE pedido_id = (
    SELECT pedido_id
    FROM (
        SELECT p.pedido_id
        FROM pedido AS p
        JOIN cliente AS c ON c.cliente_id = p.cliente_id
        WHERE c.correo = 'cliente.prueba@example.com'
        ORDER BY p.pedido_id DESC
        LIMIT 1
    ) AS pedido_prueba
);

COMMIT;

SELECT nombre, stock
FROM producto
WHERE nombre = 'Adaptador USB-C';

SELECT p.pedido_id, p.estado
FROM pedido AS p
JOIN cliente AS c ON c.cliente_id = p.cliente_id
WHERE c.correo = 'cliente.prueba@example.com';
