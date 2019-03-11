FROM alpine:latest

ENV LEANOTE_VERSION=2.6.1
ENV LEANOTE_SECRET=changemeplease
ENV LEANOTE_DB_HOST=mongodb
ENV LEANOTE_SITE_URL=http://localhost

ADD run.sh /

RUN apk --update add curl mongodb-tools \
    && curl -L http://sourceforge.net/projects/leanote-bin/files/${LEANOTE_VERSION}/leanote-linux-amd64-v${LEANOTE_VERSION}.bin.tar.gz/download > /usr/local/leanote-linux-amd64.bin.tar.gz \
    && apk del --purge curl \ 
    && rm -rf /var/cache/apk/* \
    && tar -xzvf /usr/local/leanote-linux-amd64.bin.tar.gz -C / \
    && rm -f /usr/local/leanote-linux-amd64.bin.tar.gz \
    && mkdir -p /leanote/data/public/upload \
    && mkdir -p /leanote/data/files \
    && rm -r /leanote/public/upload \
    && ln -s /leanote/data/public/upload /leanote/public/upload \
    && ln -s /leanote/data/files /leanote/files \
    && chmod +x /leanote/bin/run.sh \
    && chmod +x /run.sh

VOLUME /leanote/data/

EXPOSE 9000

WORKDIR  /leanote/bin

ENTRYPOINT ["sh", "/run.sh"]
