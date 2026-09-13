USE data_bugs;

START TRANSACTION;

DELETE d
FROM detalle_pedido AS d
JOIN pedido AS p ON p.pedido_id = d.pedido_id
JOIN cliente AS c ON c.cliente_id = p.cliente_id
WHERE c.correo = 'cliente.prueba@example.com';

DELETE pa
FROM pago AS pa
JOIN pedido AS p ON p.pedido_id = pa.pedido_id
JOIN cliente AS c ON c.cliente_id = p.cliente_id
WHERE c.correo = 'cliente.prueba@example.com';

DELETE p
FROM pedido AS p
JOIN cliente AS c ON c.cliente_id = p.cliente_id
WHERE c.correo = 'cliente.prueba@example.com';

DELETE FROM cliente
WHERE correo = 'cliente.prueba@example.com';

COMMIT;

SELECT COUNT(*) AS clientes_de_prueba
FROM cliente
WHERE correo = 'cliente.prueba@example.com';
