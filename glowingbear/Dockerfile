FROM nginx:alpine

RUN BUILD_DEPS=" \
    nodejs \
    nodejs-npm \
    git \
    make" \
    && apk -U upgrade \
    && apk add \
    ${BUILD_DEPS} \ 
    ca-certificates \
    wget openssl \
    && update-ca-certificates \
    && wget -O /tmp/gb.zip https://github.com/glowing-bear/glowing-bear/archive/master.zip \
    && unzip -o /tmp/gb.zip -d /tmp \
    && mv /tmp/glowing-bear-master/* /usr/share/nginx/html/ \
    && cd /usr/share/nginx/html/ \
    && echo '{ "allow_root": true }' > /root/.bowerrc \
    && npm install \
    && npm run make-local \
    && rm -rf /tmp/* \
    && rm -rf /var/cache/apk/* \
    && rm -rf /usr/share/nginx/html/node_modules \
    && rm -rf /usr/share/nginx/html/bower_components \
    && rm -rf /root/.cache/* \
    && apk del ${BUILD_DEPS}
