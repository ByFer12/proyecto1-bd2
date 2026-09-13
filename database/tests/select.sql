USE data_bugs;

SELECT
    p.pedido_id,
    c.nombre AS cliente,
    p.estado,
    p.total,
    p.creado_en
FROM pedido AS p
JOIN cliente AS c ON c.cliente_id = p.cliente_id
ORDER BY p.pedido_id;

SELECT
    p.nombre AS producto,
    p.precio,
    p.stock,
    SUM(d.cantidad) AS unidades_vendidas
FROM producto AS p
LEFT JOIN detalle_pedido AS d ON d.producto_id = p.producto_id
GROUP BY p.producto_id, p.nombre, p.precio, p.stock
ORDER BY unidades_vendidas DESC, p.nombre;

SELECT
    c.nombre AS cliente,
    COUNT(p.pedido_id) AS pedidos,
    COALESCE(SUM(p.total), 0) AS valor_total
FROM cliente AS c
LEFT JOIN pedido AS p ON p.cliente_id = c.cliente_id
GROUP BY c.cliente_id, c.nombre
ORDER BY valor_total DESC;
