FROM alpine

ENV TERM=screen-256color
ENV LANG=C.UTF-8
ENV UID=1000
ENV GID=1000

ADD run.sh /

RUN BUILD_DEPS=" \
    cmake \
    build-base \
    libcurl \
    libintl \
    zlib-dev \
    curl-dev \
    perl-dev \
    gnutls-dev \
    python2-dev \
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
    python \
    su-exec \
    perl \
    curl \
    shadow \
    && update-ca-certificates \
    && WEECHAT_TARBALL="$(curl -sS https://api.github.com/repos/weechat/weechat/releases/latest | jq .tarball_url -r)" \
    && curl -sSL $WEECHAT_TARBALL -o /tmp/weechat.tar.gz \
    && mkdir -p /tmp/weechat/build \
    && tar xzf /tmp/weechat.tar.gz --strip 1 -C /tmp/weechat \
    && cd /tmp/weechat/build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr \
    && make && make install \
    && mkdir /weechat \
    && addgroup -g $GID -S weechat \
    && adduser -u $UID -D -S -h /weechat -s /sbin/nologin -G weechat weechat \
    && apk del ${BUILD_DEPS} \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

VOLUME /weechat

WORKDIR /weechat

EXPOSE 9001

ENTRYPOINT ["/run.sh"]
CMD ["--dir /weechat"]
