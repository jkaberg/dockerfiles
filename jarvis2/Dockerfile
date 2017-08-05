FROM python:3-alpine

ENV JARVIS_SETTINGS config.py

RUN apk add --no-cache --virtual .build-deps build-base python3-dev libxml2-dev zlib-dev git \
    && apk add --no-cache make libxml2 libxslt zlib \
    && python -m ensurepip \
    && pip install --upgrade pip setuptools \
    && git clone https://github.com/mpolden/jarvis2 /app\
    && pip install -r /app/requirements.txt \
    && rm -rf /tmp/* \
    && rm -r /root/.cache \
    && rm -r /usr/lib/python*/ensurepip \
    && apk del --no-cache .build-deps

VOLUME /app/app/config.py

EXPOSE 5000

WORKDIR /app

ENTRYPOINT ["python"]

CMD ["app/run.py"]
