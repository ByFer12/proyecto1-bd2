USE data_bugs;

START TRANSACTION;

INSERT INTO cliente (nombre, correo)
VALUES ('Cliente de prueba', 'cliente.prueba@example.com');

SET @cliente_id = LAST_INSERT_ID();

INSERT INTO pedido (cliente_id, estado, total)
VALUES (@cliente_id, 'PENDIENTE', 45.00);

SET @pedido_id = LAST_INSERT_ID();

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT @pedido_id, producto_id, 1, precio
FROM producto
WHERE nombre = 'Adaptador USB-C';

COMMIT;

SELECT
    p.pedido_id,
    c.nombre AS cliente,
    p.estado,
    p.total
FROM pedido AS p
JOIN cliente AS c ON c.cliente_id = p.cliente_id
WHERE c.correo = 'cliente.prueba@example.com';
