"""Carga MySQL controlada para la Fase 6, ejecutada por Locust."""

import os
import time

import pymysql
from locust import User, between, events, task


class MySQLUser(User):
    """Cada usuario virtual conserva una conexión a ProxySQL o MySQL."""

    wait_time = between(0.05, 0.20)

    def on_start(self):
        self.connection = None
        self.load_mode = os.getenv("LOAD_MODE", "mixed").lower()
        self._connect()

    def _connect(self):
        self.connection = pymysql.connect(
            host=os.getenv("DB_HOST", "127.0.0.1"),
            port=int(os.getenv("DB_PORT", "6033")),
            user=os.getenv("DB_USER", "app_user"),
            password=os.environ["DB_PASSWORD"],
            database=os.getenv("DB_SCHEMA", "data_bugs"),
            connect_timeout=5,
            read_timeout=10,
            write_timeout=10,
            autocommit=True,
        )

    def _execute(self, name, sql):
        started = time.perf_counter()
        try:
            if self.connection is None or not self.connection.open:
                self._connect()
            with self.connection.cursor() as cursor:
                cursor.execute(sql)
                rows = cursor.fetchall() if cursor.description else ()
            events.request.fire(
                request_type="MYSQL",
                name=name,
                response_time=(time.perf_counter() - started) * 1000,
                response_length=len(rows),
            )
        except Exception as error:  # Locust debe contabilizar el fallo real.
            events.request.fire(
                request_type="MYSQL",
                name=name,
                response_time=(time.perf_counter() - started) * 1000,
                response_length=0,
                exception=error,
            )
            if self.connection is not None:
                try:
                    self.connection.close()
                except Exception:
                    pass
            self.connection = None

    @task(3)
    def consultar_producto(self):
        self._execute(
            "SELECT producto",
            "SELECT nombre, stock FROM producto WHERE producto_id=1",
        )

    @task(1)
    def operacion_secundaria(self):
        if self.load_mode == "read":
            self._execute(
                "SELECT conteo",
                "SELECT COUNT(*) FROM cliente",
            )
        else:
            self._execute(
                "UPDATE sin cambio",
                "UPDATE producto SET stock=stock WHERE producto_id=1",
            )

    def on_stop(self):
        if self.connection is not None:
            self.connection.close()
