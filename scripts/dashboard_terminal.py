#!/usr/bin/env python3
"""
dashboard_terminal.py - Visualizador dinamico del estado del cluster en terminal
Proyecto 1 - Bases de Datos 2 (Grupo 4)
Ejecutar en Nodo 1 (Byron)
"""

import datetime
import os
import subprocess
import time

INTERVALO = 1.5


def consultar_proxysql():
    cmd = [
        "docker", "exec", "proxysql-db2",
        "mysql", "-uadmin", "-padministradordb123", "-h127.0.0.1", "-P6032",
        "-N", "-B", "-e",
        "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers;"
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        if res.returncode != 0:
            return None
        servers = {}
        for linea in res.stdout.strip().splitlines():
            partes = linea.split()
            if len(partes) >= 3:
                servers[partes[1]] = partes[2]
        return servers
    except Exception:
        return None


def consultar_queries():
    cmd = [
        "docker", "exec", "proxysql-db2",
        "mysql", "-uadmin", "-padministradordb123", "-h127.0.0.1", "-P6032",
        "-N", "-B", "-e",
        "SELECT srv_host, Queries FROM stats_mysql_connection_pool WHERE hostgroup=10;"
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        stats = {}
        for linea in res.stdout.strip().splitlines():
            partes = linea.split()
            if len(partes) >= 2:
                stats[partes[0]] = partes[1]
        return stats
    except Exception:
        return {}


def render(servers, queries):
    os.system("clear")
    ahora = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    st_n1 = servers.get("100.113.38.39", "UNKNOWN")
    st_n2 = servers.get("100.126.57.24", "UNKNOWN")
    st_n3 = servers.get("100.107.61.57", "UNKNOWN")

    q_n1 = queries.get("100.113.38.39", "0")
    q_n2 = queries.get("100.126.57.24", "0")

    def box_status(st):
        if st == "ONLINE":
            return "[ ONLINE ]"
        elif st == "SHUNNED":
            return "[ SHUNNED ]"
        elif st == "OFFLINE":
            return "[ OFFLINE ]"
        return f"[ {st} ]"

    flecha_n1 = "======>" if st_n1 == "ONLINE" else "   x   "
    flecha_n2 = "======>" if st_n2 == "ONLINE" else "   x   "

    print("======================================================================")
    print("           MONITOR VISUAL EN TIEMPO REAL - PROXYSQL & CLUSTER         ")
    print(f"                     Ultima actualizacion: {ahora}                    ")
    print("======================================================================")
    print("")
    print("    [ CLIENTES / LOCUST ]")
    print("              |")
    print("              v")
    print("    +--------------------+")
    print("    |  PROXYSQL :6033    |")
    print("    |  (100.113.38.39)   |")
    print("    +--------------------+")
    print("              |")
    print("              +------------------------+")
    print("              |                        |")
    print(f"         {flecha_n1}                   {flecha_n2}")
    print("              |                        |")
    print("              v                        v")
    print("    +--------------------+   +--------------------+")
    print("    |  NODO 1 (Byron)    |   |  NODO 2 (Michael)  |")
    print("    |  100.113.38.39     |   |  100.126.57.24     |")
    print(f"    |  Estado: {box_status(st_n1):<10}|   |  Estado: {box_status(st_n2):<10}|")
    print(f"    |  Queries: {q_n1:<9}|   |  Queries: {q_n2:<9}|")
    print("    +--------------------+   +--------------------+")
    print("              |                        |")
    print("              +------------+-----------+")
    print("                           | (Replicacion)")
    print("                           v")
    print("                 +--------------------+")
    print("                 |  NODO 3 (Carlos)   |")
    print("                 |  100.107.61.57     |")
    print("                 |  Rol: READ-ONLY    |")
    print(f"                 |  Estado: {box_status(st_n3):<10}|")
    print("                 +--------------------+")
    print("")
    print("======================================================================")
    print("Presiona Ctrl + C para salir.")


def main():
    while True:
        try:
            servers = consultar_proxysql()
            if servers is None:
                servers = {}
            queries = consultar_queries()
            render(servers, queries)
            time.sleep(INTERVALO)
        except KeyboardInterrupt:
            print("\nMonitor detenido.")
            break


if __name__ == "__main__":
    main()

