#!/bin/sh

usermod -o -u "$GID" weechat
groupmod -o -g "$UID" weechat

chown -R weechat:weechat /weechat
chmod -R 755 /weechat


su-exec weechat /usr/bin/weechat "$@"
