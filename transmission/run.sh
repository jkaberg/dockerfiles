#!/bin/bash

usermod -o -u "$GID" transmission
groupmod -o -g "$UID" transmission

chown -R transmission:transmission /downloads /config /watch

/usr/bin/transmission-daemon -g /config -c /watch -f
