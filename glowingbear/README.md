Glowing-Bear
===================

This is an automatically built Alpine Docker image for Glowing-Bear. It will rebuild everytime there is a new commit is made to master branch at [Github](https://github.com/weechat/weechat/releases) or when the [base image](https://hub.docker.com/_/nginx/) gets updated.

To run it simply use ```docker run```:

``` docker run -it --name glowingbear jkaberg/glowingbear```

or docker-compose:
```
  glowingbear:
    image: jkaberg/glowingbear
    restart: always
    networks:
      - some_network
```
