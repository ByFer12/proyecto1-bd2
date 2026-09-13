USE data_bugs;

SELECT 'clientes' AS entidad, COUNT(*) AS cantidad FROM cliente
UNION ALL
SELECT 'productos', COUNT(*) FROM producto
UNION ALL
SELECT 'pedidos', COUNT(*) FROM pedido
UNION ALL
SELECT 'detalles', COUNT(*) FROM detalle_pedido
UNION ALL
SELECT 'pagos', COUNT(*) FROM pago;

SELECT
    p.pedido_id,
    c.nombre AS cliente,
    p.estado,
    p.total,
    COALESCE(SUM(d.cantidad * d.precio_unitario), 0) AS total_calculado
FROM pedido AS p
JOIN cliente AS c ON c.cliente_id = p.cliente_id
LEFT JOIN detalle_pedido AS d ON d.pedido_id = p.pedido_id
GROUP BY p.pedido_id, c.nombre, p.estado, p.total
ORDER BY p.pedido_id;

SELECT
    pedido_id,
    COUNT(*) AS pagos
FROM pago
GROUP BY pedido_id
HAVING COUNT(*) > 1;
