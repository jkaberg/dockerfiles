weechat
===================

This is an automatically built Alpine Docker image for Weechat. It will rebuild everytime there is a new release on [Github](https://github.com/weechat/weechat/releases) or when the [base image](https://hub.docker.com/_/alpine/) gets updated.

[![](https://images.microbadger.com/badges/image/jkaberg/weechat.svg)](https://microbadger.com/images/jkaberg/weechat "Get your own image badge on microbadger.com") [![](https://images.microbadger.com/badges/version/jkaberg/weechat.svg)](https://microbadger.com/images/jkaberg/weechat "Get your own version badge on microbadger.com")

To run it simply use ```docker run```:

``` docker run -it --name weechat -e UID=1000 -e GID=1000 -v /path/to/weechat/config:/weechat jkaberg/weechat```

or docker-compose:
```
  weechat:
    image: jkaberg/weechat
    restart: always
    stdin_open: true
    tty: true
    volumes:
      - /path/to/weechat/config:/weechat
    environment:
      - 'UID=1000'
      - 'GID=1000'
    networks:
      - some_network
```

Once up and running, use ```ctrl-p```, ```ctrl-q``` to deattach from the session and ```docker attach weechat``` to reattach. 
