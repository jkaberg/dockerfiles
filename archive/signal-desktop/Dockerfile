FROM node:10.13

RUN apt update \
    && apt install -y python gcc g++ make git \
    && git clone https://github.com/signalapp/Signal-Desktop.git /app \
    && cd /app \
    && npm install --global yarn \
    && yarn install --frozen-lockfile \
    && yarn grunt \
    && yarn icon-gen

WORKDIR /app

ENTRYPOINT yarn start
