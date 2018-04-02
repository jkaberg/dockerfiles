FROM node:alpine

ENV URL=http://localhost
ENV HOST=0.0.0.0

RUN mkdir -p /app \
    && BUILD_DEPS=" \
    curl " \
    && apk -U upgrade && apk add ${BUILD_DEPS} \
    && curl -sSL https://github.com/tannercollin/Notica/archive/master.tar.gz -o /tmp/notica.tar.gz \
    && tar xzf /tmp/notica.tar.gz --strip 1 -C /app \
    && cd /app \
    && npm install \
    && apk del ${BUILD_DEPS} \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

EXPOSE 3000
WORKDIR /app

ENTRYPOINT npm start -- --host $HOST --url $URL
