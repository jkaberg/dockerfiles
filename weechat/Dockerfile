FROM alpine

ARG WEECHAT_HOME=/home/weechat

ENV TERM=screen-256color
ENV LANG=C.UTF-8

RUN BUILD_DEPS=" \
    cmake \
    build-base \
    libcurl \
    zlib-dev \
    curl-dev \
    gnutls-dev \
    ncurses-dev \
    libgcrypt-dev \
    ca-certificates \
    jq \
    tar" \
    && apk -U upgrade && apk add \
    ${BUILD_DEPS} \
    gnutls \
    ncurses \ 
    libgcrypt \
    curl \
    && update-ca-certificates \
    && WEECHAT_TARBALL="$(curl -sS https://api.github.com/repos/weechat/weechat/releases/latest | jq .tarball_url -r)" \
    && echo $WEECHAT_TARBALL \
    && curl -sSL $WEECHAT_TARBALL -o /tmp/weechat.tar.gz \
    && mkdir -p /tmp/weechat/build \
    && tar xzf /tmp/weechat.tar.gz --strip 1 -C /tmp/weechat \
    && cd /tmp/weechat/build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr \
    && make && make install \
    && addgroup -S weechat \
    && adduser -D -S -h $WEECHAT_HOME -s /sbin/nologin -G weechat weechat \
    && chown -R weechat:weechat $WEECHAT_HOME \
    && apk del ${BUILD_DEPS} \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

VOLUME /home/weechat/.weechat

WORKDIR /home/weechat

USER weechat

EXPOSE 9001

ENTRYPOINT ["/usr/bin/weechat"]
