FROM alpine

ENV UID=911 \
    GID=911

RUN addgroup -g $GID -S transmission \
    && adduser -u $UID -D -S -h /config -s /sbin/nologin -G transmission transmission \
    && apk add --update \
        wget \
        bash \
        unrar \
        unzip \
        su-exec \
        shadow \
        transmission-daemon \
        && wget "https://raw.githubusercontent.com/ronggang/transmission-web-control/master/release/install-tr-control.sh" -O "/tmp/webui.sh" \
        && chmod +x /tmp/webui.sh \
        && /tmp/webui.sh \
        && mkdir -p /downloads /config /watch \
        && rm -rf /tmp/* \
        && rm -rf /var/cache/apk/*

ADD run.sh /
ADD settings.json /config

VOLUME ["/config", "/downloads", "/watch"]

EXPOSE 9091 51413/tcp 51413/udp

ENTRYPOINT ["/run.sh"]
CMD ["-g", "/config", "-c", "/watch", "-f"]
