FROM alpine:edge

ENV TERM xterm
ENV LANG C.UTF-8

RUN apk add --update weechat python bash \
    && rm -rf /var/cache/apk/* \
    && addgroup weechat \
    && adduser -D -s /bin/bash -G weechat weechat 

VOLUME /home/weechat/.weechat

WORKDIR /home/weechat

USER weechat

EXPOSE 9001

ENTRYPOINT ["/usr/bin/weechat"]
