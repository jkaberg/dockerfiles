#!/bin/sh

usermod -o -u "$GID" transmission > /dev/null 2>&1
groupmod -o -g "$UID" transmission > /dev/null 2>&1

chown -R transmission:transmission /downloads /config /watch

su-exec transmission /usr/bin/transmission-daemon "$@"
