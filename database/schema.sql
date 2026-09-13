CREATE DATABASE IF NOT EXISTS data_bugs
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE data_bugs;

CREATE TABLE cliente (
    cliente_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(160) NOT NULL UNIQUE,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE producto (
    producto_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    precio DECIMAL(12, 2) NOT NULL,
    stock INT UNSIGNED NOT NULL DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT producto_precio_no_negativo CHECK (precio >= 0)
) ENGINE = InnoDB;

CREATE TABLE pedido (
    pedido_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cliente_id BIGINT UNSIGNED NOT NULL,
    estado ENUM('PENDIENTE', 'PAGADO', 'ENVIADO', 'CANCELADO') NOT NULL DEFAULT 'PENDIENTE',
    total DECIMAL(12, 2) NOT NULL DEFAULT 0,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pedido_cliente_fk FOREIGN KEY (cliente_id) REFERENCES cliente (cliente_id),
    CONSTRAINT pedido_total_no_negativo CHECK (total >= 0),
    INDEX pedido_cliente_idx (cliente_id)
) ENGINE = InnoDB;

CREATE TABLE detalle_pedido (
    pedido_id BIGINT UNSIGNED NOT NULL,
    producto_id BIGINT UNSIGNED NOT NULL,
    cantidad INT UNSIGNED NOT NULL,
    precio_unitario DECIMAL(12, 2) NOT NULL,
    PRIMARY KEY (pedido_id, producto_id),
    CONSTRAINT detalle_pedido_fk FOREIGN KEY (pedido_id) REFERENCES pedido (pedido_id),
    CONSTRAINT detalle_producto_fk FOREIGN KEY (producto_id) REFERENCES producto (producto_id),
    CONSTRAINT detalle_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT detalle_precio_no_negativo CHECK (precio_unitario >= 0)
) ENGINE = InnoDB;

CREATE TABLE pago (
    pago_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    pedido_id BIGINT UNSIGNED NOT NULL,
    metodo ENUM('TARJETA', 'TRANSFERENCIA', 'EFECTIVO') NOT NULL,
    monto DECIMAL(12, 2) NOT NULL,
    pagado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pago_pedido_fk FOREIGN KEY (pedido_id) REFERENCES pedido (pedido_id),
    CONSTRAINT pago_monto_positivo CHECK (monto > 0),
    UNIQUE KEY pago_pedido_unico (pedido_id)
) ENGINE = InnoDB;
