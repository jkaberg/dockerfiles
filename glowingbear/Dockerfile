FROM nginx:alpine

RUN BUILD_DEPS=" \
    nodejs \
    nodejs-npm" \
    && apk -U upgrade \
    && apk add \
    ${BUILD_DEPS \ 
    ca-certificates \
    wget openssl \
    && update-ca-certificates \
    && wget -O /tmp/gb.zip https://github.com/glowing-bear/glowing-bear/archive/master.zip \
    && unzip -o /tmp/gb.zip -d /tmp \
    && mv /tmp/glowing-bear-master/* /usr/share/nginx/html/ \
    && cd /usr/share/nginx/html/ \
    && npm run make-local \
    && rm -rf /tmp/* \
    && rm -rf /var/cache/apk/* \
    && apk del ${BUILD_DEPS}
