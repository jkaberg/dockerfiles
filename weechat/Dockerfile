FROM alpine

ENV TERM xterm

RUN apk add --update weechat python bash \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /weechat/.weechat \
    && addgroup weechat \
    && adduser -D -s /bin/bash -G weechat weechat \
    && chown -R weechat:weechat /weechat

VOLUME /weechat/.weechat

WORKDIR /weechat

USER weechat

ENTRYPOINT ["/usr/bin/weechat"]

CMD ["-d", "/weechat/.weechat"]
