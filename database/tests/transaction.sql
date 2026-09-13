USE data_bugs;

START TRANSACTION;

UPDATE producto
SET stock = stock - 1
WHERE nombre = 'Teclado mecanico'
  AND stock > 0;

SELECT nombre, stock
FROM producto
WHERE nombre = 'Teclado mecanico';

ROLLBACK;

SELECT nombre, stock
FROM producto
WHERE nombre = 'Teclado mecanico';

START TRANSACTION;

UPDATE producto
SET stock = stock - 1
WHERE nombre = 'Teclado mecanico'
  AND stock > 0;

COMMIT;

SELECT nombre, stock
FROM producto
WHERE nombre = 'Teclado mecanico';
