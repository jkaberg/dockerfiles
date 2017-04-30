Glowing-Bear
===================

This is an automatically built Alpine Docker image for Glowing-Bear. It will rebuild everytime a new commit is made to master branch at [Github](https://github.com/glowing-bear/glowing-bear/tree/master) or when the [base image](https://hub.docker.com/_/nginx/) gets updated.

[![](https://images.microbadger.com/badges/image/jkaberg/glowingbear.svg)](https://microbadger.com/images/jkaberg/glowingbear "Get your own image badge on microbadger.com")
[![](https://images.microbadger.com/badges/version/jkaberg/glowingbear.svg)](https://microbadger.com/images/jkaberg/glowingbear "Get your own version badge on microbadger.com")


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
