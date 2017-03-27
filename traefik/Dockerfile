FROM traefik:1.2.0-alpine

RUN mkdir /traefik

ADD traefik.toml /traefik

VOLUME /traefik

ENTRYPOINT ["traefik"]

CMD ["-c", "/traefik/traefik.toml"]
