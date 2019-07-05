Notica
===================

This is an Alpine Docker image for Notica. 

To run it simply use ```docker run```:

``` docker run -it --name notica -e URL=https://my.url jkaberg/notica```

or docker-compose:
```
  notica:
    image: jkaberg/notica
    restart: always
    environment:
      - URL=https://my.url
    networks:
      - some_network
```
