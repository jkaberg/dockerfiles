transmission
===================

This is an automatically built Alpine Docker image for Transmission. It will rebuild everytime there is a new release on [Github](https://github.com/transmission/transmission/releases) or when the [base image](https://hub.docker.com/_/alpine/) gets updated.

[![](https://images.microbadger.com/badges/image/jkaberg/transmission.svg)](https://microbadger.com/images/jkaberg/transmission "Get your own image badge on microbadger.com")

To run it simply use ```docker run```:

``` docker run -it --name transmission -e UID=1000 -e GID=1000 -v /path/to/transmission/config:/config jkaberg/transmission```

or docker-compose:
```
  weechat:
    image: jkaberg/transmision
    restart: always
    volumes:
      - /path/to/transmission/config:/config
    environment:
      - 'UID=1000'
      - 'GID=1000'
    networks:
      - some_network
```
