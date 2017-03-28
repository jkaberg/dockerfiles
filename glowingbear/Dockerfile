FROM nginx:alpine

ADD default.conf /etc/nginx/conf.d

RUN apk add --update ca-certificates wget openssl \
    && rm -rf /var/cache/apk/* \
    && update-ca-certificates \
#    && openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/CN=localhost" -keyout /etc/nginx/server.key -out /etc/nginx/server.crt \
    && wget -O /tmp/gb.zip https://github.com/glowing-bear/glowing-bear/archive/master.zip \
    && unzip -o /tmp/gb.zip -d /tmp \
    && mv /tmp/glowing-bear-master/* /usr/share/nginx/html/ \
    && rm -rf /tmp/*
