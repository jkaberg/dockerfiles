#!/bin/sh

usermod -o -u "$GID" transmission
groupmod -o -g "$UID" transmission

chown -R transmission:transmission /downloads /config /watch

exec su-exec transmission /usr/bin/transmission-daemon "$@"
