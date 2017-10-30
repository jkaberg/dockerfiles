FROM alpine

RUN apk add mariadb-client mariadb-client-libs --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/main/ --allow-untrusted \
    && apk add --no-cache git python zeromq \
    && apk add --no-cache --virtual .build-deps gcc g++ python-dev mariadb-dev zeromq-dev \
    && python -m ensurepip \
    && rm -r /usr/lib/python*/ensurepip \
    && pip install --upgrade pip setuptools gunicorn \
    && rm -r /root/.cache \
    && mkdir -p /etc/gunicorn.d \
    && git clone https://github.com/Pushjet/Pushjet-Server-Api/ /opt/pushjet \
    && pip install -r /opt/pushjet/requirements.txt \
    && apk del --no-cache .build-deps \
    && rm -rf /var/cache/apk/*

COPY ./files/gunicorn /etc/gunicorn.d/pushjet

VOLUME /opt/pushjet/config.py 

WORKDIR /opt/pushjet

ENTRYPOINT ["/usr/bin/gunicorn", "-b", "0.0.0.0:8000", "-w 4", "--timeout=30", "application:app"]
