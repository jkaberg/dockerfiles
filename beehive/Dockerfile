FROM golang:1.8-alpine

ENV URL=http://localhost:8181 \
    PORT=8181

RUN apk add --no-cache git build-base --no-cache && \
    rm -rf /var/cache/apk/* &&\ 
    go get github.com/muesli/beehive
    
WORKDIR /go/src/github.com/muesli/beehive

EXPOSE 8181

ENTRYPOINT beehive -config /conf/beehive.conf -bind 0.0.0.0:${PORT} -canonicalurl ${URL}
