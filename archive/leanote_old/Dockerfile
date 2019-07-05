FROM alpine

ENV LEANOTE_VER=2.6.1

RUN mkdir -p /app \
    && BUILD_DEPS=" \
    curl" \
    && apk -U upgrade \
    && apk add ${BUILD_DEPS} \
    && apk add mongodb mongodb-tools \
    && curl -L http://sourceforge.net/projects/leanote-bin/files/${LEANOTE_VER}/leanote-linux-amd64-v${LEANOTE_VER}.bin.tar.gz/download -o /tmp/leanote.tar.gz \
    && tar xzf /tmp/leanote.tar.gz --strip 1 -C /app \
    && chmod +x /app/bin/run.sh \
    && mkdir -p /data \
    && apk del ${BUILD_DEPS} \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

ADD run.sh /app
EXPOSE 9000
WORKDIR /app

ENTRYPOINT /app/run.sh
