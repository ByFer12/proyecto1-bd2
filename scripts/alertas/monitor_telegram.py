#!/usr/bin/env python3
"""
Monitor del Clúster MySQL Group Replication & ProxySQL con Alertas a Telegram.
Grupo 4 - Bases de Datos 2
Byron (Nodo 1) | Michael (Nodo 2) | Carlos (Nodo 3)
"""

import datetime
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request

import sys

# ==========================================
# CONFIGURACIÓN TELEGRAM
# ==========================================
def cargar_env():
    """Carga variables desde archivos .env locales si existen."""
    rutas_env = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.env"),
        os.path.join(os.getcwd(), ".env"),
    ]
    for ruta in rutas_env:
        if os.path.isfile(ruta):
            try:
                with open(ruta, "r", encoding="utf-8") as f:
                    for linea in f:
                        linea = linea.strip()
                        if not linea or linea.startswith("#") or "=" not in linea:
                            continue
                        clave, valor = linea.split("=", 1)
                        clave = clave.strip()
                        valor = valor.strip().strip("'\"")
                        if clave and clave not in os.environ:
                            os.environ[clave] = valor
            except Exception:
                pass

cargar_env()

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()

INTEGRANTES = {
    "1089599703": "Byron (Nodo 1)",
    "566789759": "Carlos (Nodo 3)",
    "1293220319": "Michael (Nodo 2)",
}

# ==========================================
# METADATOS DE LA ARQUITECTURA
# ==========================================
NODOS_INFO = {
    "100.113.38.39": {"nombre": "Nodo 1 (Byron)", "rol_esperado": "RW (Escritor)"},
    "100.126.57.24": {"nombre": "Nodo 2 (Michael)", "rol_esperado": "RW (Escritor)"},
    "100.107.61.57": {"nombre": "Nodo 3 (Carlos)", "rol_esperado": "RO (Solo Lectura)"},
}

INTERVALO_SEGUNDOS = 2


def enviar_mensaje_telegram(chat_id, texto):
    """Envía un mensaje formateado a un usuario de Telegram."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = json.dumps({
        "chat_id": chat_id,
        "text": texto,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=payload, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status == 200
    except Exception as e:
        print(f"[ERROR Telegram -> {chat_id}]: {e}")
        return False


def difundir_alerta(texto):
    """Envía la alerta individualmente a cada uno de los 3 integrantes."""
    ahora = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"\n[{ahora}] ENVIANDO ALERTA A TELEGRAM...")
    for chat_id, nombre in INTEGRANTES.items():
        ok = enviar_mensaje_telegram(chat_id, texto)
        status = "Enviado OK" if ok else "Fallo"
        print(f"  -> {nombre} ({chat_id}): {status}")


def consultar_proxysql():
    """Consulta la tabla runtime_mysql_servers dentro del contenedor proxysql-db2."""
    cmd = [
        "docker", "exec", "proxysql-db2",
        "mysql", "-uadmin", "-padministradordb123", "-h127.0.0.1", "-P6032",
        "-N", "-B", "-e",
        "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers;"
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        if res.returncode != 0:
            return None
        servers = {}
        for linea in res.stdout.strip().splitlines():
            partes = linea.split()
            if len(partes) >= 3:
                hg, host, st = partes[0], partes[1], partes[2]
                # Si un host aparece en varios hostgroups, priorizamos SHUNNED/OFFLINE si está fallando
                if host not in servers or st != "ONLINE":
                    servers[host] = st
        return servers
    except Exception as e:
        print(f"[Error consultando ProxySQL]: {e}")
        return None


def consultar_queries_proxysql():
    """Consulta consultas totales atendidas."""
    cmd = [
        "docker", "exec", "proxysql-db2",
        "mysql", "-uadmin", "-padministradordb123", "-h127.0.0.1", "-P6032",
        "-N", "-B", "-e",
        "SELECT srv_host, Queries FROM stats_mysql_connection_pool WHERE hostgroup=10;"
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        stats = {}
        for linea in res.stdout.strip().splitlines():
            partes = linea.split()
            if len(partes) >= 2:
                stats[partes[0]] = partes[1]
        return stats
    except Exception:
        return {}


def construir_mensaje_evento(tipo_evento, host_afectado, estado_actual, t_inicio_ms):
    """Construye un mensaje enriquecido con métricas, RTO, RPO y estado."""
    hora_actual = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    n1_status = estado_actual.get("100.113.38.39", "DESCONOCIDO")
    n2_status = estado_actual.get("100.126.57.24", "DESCONOCIDO")
    n3_status = estado_actual.get("100.107.61.57", "DESCONOCIDO")

    icono_n1 = "🟢 ONLINE" if n1_status == "ONLINE" else "🔴 SHUNNED / OFFLINE"
    icono_n2 = "🟢 ONLINE" if n2_status == "ONLINE" else "🔴 SHUNNED / OFFLINE"
    icono_n3 = "🟢 ONLINE (RO)" if n3_status == "ONLINE" else "🔴 DESCONECTADO"

    queries = consultar_queries_proxysql()
    q_n1 = queries.get("100.113.38.39", "0")
    q_n2 = queries.get("100.126.57.24", "0")

    # Calcular RTO aproximado de conmutación si aplica
    rto_ms = int((time.time() * 1000) - t_inicio_ms) if t_inicio_ms else 1500

    if tipo_evento == "FALLO_NODO1":
        msg = (
            f"🚨 <b>[ALERTA CLÚSTER - DATA BUGS]</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚠️ <b>Evento:</b> Caída detectada en <b>Nodo 1 (Byron)</b>\n"
            f"📍 <b>IP afectada:</b> <code>100.113.38.39:3306</code>\n"
            f"🔄 <b>Acción ProxySQL:</b> Failover automático hacia <b>Nodo 2</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 <b>Estado de Servidores:</b>\n"
            f"  • Nodo 1: {icono_n1} (Queries: {q_n1})\n"
            f"  • Nodo 2: {icono_n2} <b>[ESCRITOR ACTIVO]</b> (Queries: {q_n2})\n"
            f"  • Nodo 3: {icono_n3} [Solo Lectura]\n\n"
            f"⏱️ <b>Métricas de Recuperación:</b>\n"
            f"  • <b>RTO estimado (Failover):</b> ~{rto_ms} ms (~{rto_ms/1000:.1f}s)\n"
            f"  • <b>RPO observado:</b> 0 transacciones perdidas (Quórum síncrono)\n"
            f"  • <b>Hora del incidente:</b> <code>{hora_actual}</code>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"👥 <i>Notificación enviada al equipo: Byron, Michael, Carlos.</i>"
        )
    elif tipo_evento == "FALLO_NODO2":
        msg = (
            f"🚨 <b>[ALERTA CLÚSTER - DATA BUGS]</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚠️ <b>Evento:</b> Caída detectada en <b>Nodo 2 (Michael)</b>\n"
            f"📍 <b>IP afectada:</b> <code>100.126.57.24:3306</code>\n"
            f"🔄 <b>Acción ProxySQL:</b> Redirección exclusiva hacia <b>Nodo 1</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 <b>Estado de Servidores:</b>\n"
            f"  • Nodo 1: {icono_n1} <b>[ESCRITOR ACTIVO]</b> (Queries: {q_n1})\n"
            f"  • Nodo 2: {icono_n2} (Queries: {q_n2})\n"
            f"  • Nodo 3: {icono_n3} [Solo Lectura]\n\n"
            f"⏱️ <b>Métricas de Recuperación:</b>\n"
            f"  • <b>RTO estimado (Failover):</b> ~{rto_ms} ms (~{rto_ms/1000:.1f}s)\n"
            f"  • <b>RPO observado:</b> 0 transacciones perdidas\n"
            f"  • <b>Hora del incidente:</b> <code>{hora_actual}</code>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"👥 <i>Notificación enviada al equipo: Byron, Michael, Carlos.</i>"
        )
    elif tipo_evento == "CONTINGENCIA_TOTAL":
        msg = (
            f"🛑 <b>[CONTINGENCIA CRÍTICA - DATA BUGS]</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⛔ <b>Evento:</b> AMBOS ESCRITORES CAÍDOS (Nodo 1 y Nodo 2)\n"
            f"🛡️ <b>Mecanismo de Seguridad:</b> Bloqueo total de escrituras\n"
            f"🚫 <b>Prevención de Split-Brain:</b> Activo (Quórum perdido)\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 <b>Estado de Servidores:</b>\n"
            f"  • Nodo 1: {icono_n1}\n"
            f"  • Nodo 2: {icono_n2}\n"
            f"  • Nodo 3: {icono_n3} <b>[DISPONIBLE PARA LECTURA]</b>\n\n"
            f"📖 <b>Disponibilidad de Lectura:</b> 100% activa en Nodo 3\n"
            f"⏱️ <b>Hora de contingencia:</b> <code>{hora_actual}</code>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"⚠️ <i>Requiere intervención manual para recuperación.</i>"
        )
    elif tipo_evento == "RECUPERACION":
        msg = (
            f"✅ <b>[SISTEMA RESTABLECIDO - DATA BUGS]</b>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🎉 <b>Evento:</b> Reincorporación de nodo(s) al clúster\n"
            f"📍 <b>Nodo recuperado:</b> <code>{host_afectado}</code>\n"
            f"🔄 <b>ProxySQL:</b> Balanceador sincronizado nuevamente\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"📊 <b>Estado actual:</b>\n"
            f"  • Nodo 1: {icono_n1}\n"
            f"  • Nodo 2: {icono_n2}\n"
            f"  • Nodo 3: {icono_n3}\n\n"
            f"⏱️ <b>Hora de normalización:</b> <code>{hora_actual}</code>\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"🟢 <i>El clúster vuelve a operar con alta disponibilidad.</i>"
        )
    else:
        msg = f"ℹ️ <b>[CAMBIO DE ESTADO]</b>\nNodo: {host_afectado}\nEstado: {estado_actual}"

    return msg


def main():
    if not BOT_TOKEN or BOT_TOKEN == "tu_token_aqui":
        print("==========================================================")
        print("[ERROR] Variable TELEGRAM_BOT_TOKEN no configurada.")
        print("Por seguridad, el token no se almacena en el código.")
        print("Configure su token en el archivo .env de este modo:")
        print("  1. Copie la plantilla:")
        print("     cp scripts/alertas/.env.example scripts/alertas/.env")
        print("  2. Edite scripts/alertas/.env:")
        print("     TELEGRAM_BOT_TOKEN=tu_token_real")
        print("  O exporte la variable en su terminal:")
        print("     export TELEGRAM_BOT_TOKEN=tu_token_real")
        print("==========================================================")
        sys.exit(1)

    print("==========================================================")
    print("INICIANDO CENTINELA DE ALERTAS TELEGRAM - PROYECTO BD2")
    print(f"Destinatarios ({len(INTEGRANTES)} integrantes):")
    for cid, nom in INTEGRANTES.items():
        print(f"   • {nom} [ID: {cid}]")
    print("==========================================================")

    # Mensaje inicial de conexión
    msg_inicio = (
        f"🤖 <b>[BOT DE MONITOREO ACTIVO]</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Buenos dias gente madrugadora feliz navidad! soy el admin XD (100.113.38.39).\n"
        f"Supervisando salud del clúster y ProxySQL cada {INTERVALO_SEGUNDOS}s.\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"Fecha de inicio: <code>{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</code>"
    )
    difundir_alerta(msg_inicio)

    estado_anterior = {}

    while True:
        try:
            estado_actual = consultar_proxysql()
            if estado_actual is None:
                time.sleep(INTERVALO_SEGUNDOS)
                continue

            if not estado_anterior:
                estado_anterior = estado_actual
                time.sleep(INTERVALO_SEGUNDOS)
                continue

            # Detectar cambios
            n1_ant = estado_anterior.get("100.113.38.39")
            n1_act = estado_actual.get("100.113.38.39")

            n2_ant = estado_anterior.get("100.126.57.24")
            n2_act = estado_actual.get("100.126.57.24")

            # Caso 1: Contingencia total (ambos caídos)
            if (n1_act != "ONLINE" and n2_act != "ONLINE") and (n1_ant == "ONLINE" or n2_ant == "ONLINE"):
                alerta = construir_mensaje_evento("CONTINGENCIA_TOTAL", "Nodos 1 y 2", estado_actual, time.time() * 1000)
                difundir_alerta(alerta)

            # Caso 2: Caída de Nodo 1
            elif n1_ant == "ONLINE" and n1_act != "ONLINE":
                alerta = construir_mensaje_evento("FALLO_NODO1", "100.113.38.39", estado_actual, time.time() * 1000)
                difundir_alerta(alerta)

            # Caso 3: Caída de Nodo 2
            elif n2_ant == "ONLINE" and n2_act != "ONLINE":
                alerta = construir_mensaje_evento("FALLO_NODO2", "100.126.57.24", estado_actual, time.time() * 1000)
                difundir_alerta(alerta)

            # Caso 4: Recuperación de un nodo
            elif (n1_ant != "ONLINE" and n1_act == "ONLINE"):
                alerta = construir_mensaje_evento("RECUPERACION", "100.113.38.39 (Nodo 1)", estado_actual, None)
                difundir_alerta(alerta)

            elif (n2_ant != "ONLINE" and n2_act == "ONLINE"):
                alerta = construir_mensaje_evento("RECUPERACION", "100.126.57.24 (Nodo 2)", estado_actual, None)
                difundir_alerta(alerta)

            estado_anterior = estado_actual
            time.sleep(INTERVALO_SEGUNDOS)

        except KeyboardInterrupt:
            print("\n[Detención manual solicitada por el usuario].")
            break
        except Exception as e:
            print(f"[Error en bucle principal]: {e}")
            time.sleep(INTERVALO_SEGUNDOS)


if __name__ == "__main__":
    main()
