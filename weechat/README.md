weechat
===================

This is an automatically built Alpine Docker image for Weechat. It will rebuild everytime there is a new release on [Github](https://github.com/weechat/weechat/releases) or when the [base image](https://hub.docker.com/_/alpine/) gets updated.

[![](https://images.microbadger.com/badges/image/jkaberg/weechat.svg)](https://microbadger.com/images/jkaberg/weechat "Get your own image badge on microbadger.com") [![](https://images.microbadger.com/badges/version/jkaberg/weechat.svg)](https://microbadger.com/images/jkaberg/weechat "Get your own version badge on microbadger.com")

To run it simply use ```docker run```:

``` docker run -it --tty --name weechat -v /path/to/weechat/config:/weechat jkaberg/weechat```

or docker-compose:
```
  weechat:
    image: jkaberg/weechat
    restart: always
    tty: true
    volumes:
      - /path/to/weechat/config:/weechat
    networks:
      - some_network
```
