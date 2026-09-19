FROM locustio/locust:2.32.10

USER root
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY locustfile.py /mnt/locust/locustfile.py
USER locust

ENTRYPOINT ["locust"]
