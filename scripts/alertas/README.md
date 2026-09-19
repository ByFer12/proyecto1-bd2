# Sistema de Alertas Proactivas en Telegram — Grupo 4

Este módulo implementa una **mejora de alto valor arquitectónico**: un centinela en tiempo real que supervisa ProxySQL y despacha alertas instantáneas e individuales a los teléfonos/cuentas de Telegram de **Byron, Carlos y Michael** ante cualquier fallo, conmutación de tráfico (failover) o recuperación de nodos.

---

## 👥 Destinatarios configurados

| Integrante | Rol en el Clúster | Chat ID de Telegram |
|---|---|---|
| **Byron** | Nodo 1 (Escritor / ProxySQL) | `1089599703` |
| **Carlos** | Nodo 3 (Solo Lectura) | `566789759` |
| **Michael** | Nodo 2 (Escritor) | `1293220319` |

---

## 🤖 ¿Qué eventos detecta y qué informa?

1. **Caída de Nodo 1:**
   - Detecta que Nodo 1 pasó a `SHUNNED`.
   - Informa que ProxySQL redirigió automáticamente las escrituras hacia Nodo 2.
   - Reporta métricas de **RTO estimado de failover (~1.5s)** y **RPO = 0**.
2. **Caída de Nodo 2:**
   - Informa que Nodo 1 absorbe el 100% de las escrituras.
3. **Contingencia Total (Nodos 1 y 2 caídos):**
   - Alerta roja de emergencia.
   - Informa que las escrituras se bloquearon para evitar split-brain y que Nodo 3 mantiene el 100% de disponibilidad de lecturas.
4. **Recuperación de nodos:**
   - Envía confirmación cuando un nodo vuelve a estar `ONLINE` y balanceado en ProxySQL.

---

## 🚀 ¿Quién lo ejecuta y cómo?

### Configuración previa (Credenciales seguras)

1. Crear el archivo `.env` a partir de la plantilla:
   ```bash
   cp scripts/alertas/.env.example scripts/alertas/.env
   ```
2. Colocar el token provisto por BotFather en `scripts/alertas/.env`:
   ```env
   TELEGRAM_BOT_TOKEN="tu_token_aqui"
   ```
   *(El archivo `.env` está protegido en `.gitignore` para no filtrarse al repositorio público).*

3. Asegúrate de que cada uno de los 3 integrantes haya abierto el bot en Telegram y le haya dado al botón **INICIAR** (o escrito `/start`).

### Ejecución

1. **Para ejecutarlo en primer plano (en una terminal visible para la sustentación):**
   ```bash
   python3 scripts/alertas/monitor_telegram.py
   ```

2. **Para ejecutarlo en segundo plano (en background):**
   ```bash
   python3 scripts/alertas/monitor_telegram.py &
   ```

---

## 🛑 ¿Cómo detenerlo?

- Si lo ejecutaste en primer plano: presiona `Ctrl + C`.
- Si lo ejecutaste en segundo plano:
  ```bash
  kill $(pgrep -f monitor_telegram.py)
  ```
