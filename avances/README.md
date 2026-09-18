# Guías de ejecución por fase

Esta carpeta está en la raíz para que los tres integrantes utilicen el mismo
procedimiento.

| Fase | Guía | Estado |
|---|---|---|
| 1 | [Preparación](./fase1.md) | Funcionalmente completa; falta limpieza de secretos/captura segura |
| 2 | [Replicación normal](./fase2.md) | Preparada; requiere recuperar nodo2 antes de iniciar |
| 3 | [Fallo de nodo1](./fase3.md) | Guía preparada, no ejecutada |
| 4 | [Fallo de nodo2](./fase4.md) | Guía preparada, no ejecutada |
| 5 | [Fallo múltiple](./fase5.md) | Guía preparada, no ejecutada |

Documentos auxiliares:

- [Inicio y recuperación después de apagados](./inicio.md)
- [Glosario práctico](./glosario.md)
- [Contexto para retomar](./continuidad.md)
- [Plan de coordinación](./plan-equipo-cierre.md)
- [Índice de evidencias](../evidencias/README.md)
- [Borrador del informe](../informe/informe-final.md)

Los responsables indicados en cada guía organizan la prueba, pero todos deben
comprender y practicar todos los procedimientos. Solo las operaciones locales
de Docker quedan limitadas al dueño físico del equipo correspondiente.

No ejecutar fases destructivas simultáneamente. Antes de avanzar se recupera
el estado esperado, se documenta el resultado y se guardan las capturas.
