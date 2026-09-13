USE data_bugs;

INSERT INTO cliente (nombre, correo) VALUES
    ('Ana Torres', 'ana.torres@example.com'),
    ('Luis Moreno', 'luis.moreno@example.com'),
    ('Sofia Rojas', 'sofia.rojas@example.com');

INSERT INTO producto (nombre, precio, stock) VALUES
    ('Teclado mecanico', 185.00, 25),
    ('Mouse inalambrico', 95.50, 40),
    ('Monitor 24 pulgadas', 720.00, 12),
    ('Adaptador USB-C', 45.00, 60);

INSERT INTO pedido (cliente_id, estado, total) VALUES
    (1, 'PAGADO', 280.50),
    (2, 'PENDIENTE', 720.00);

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario) VALUES
    (1, 1, 1, 185.00),
    (1, 2, 1, 95.50),
    (2, 3, 1, 720.00);

INSERT INTO pago (pedido_id, metodo, monto) VALUES
    (1, 'TARJETA', 280.50);
