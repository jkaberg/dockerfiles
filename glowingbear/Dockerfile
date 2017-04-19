FROM nginx:alpine

RUN apk add --update ca-certificates wget openssl \
    && rm -rf /var/cache/apk/* \
    && update-ca-certificates \
    && wget -O /tmp/gb.zip https://github.com/glowing-bear/glowing-bear/archive/master.zip \
    && unzip -o /tmp/gb.zip -d /tmp \
    && mv /tmp/glowing-bear-master/* /usr/share/nginx/html/ \
    && rm -rf /tmp/*
