#!/bin/sh

usermod -o -u "$GID" weechat > /dev/null 2>&1
groupmod -o -g "$UID" weechat > /dev/null 2>&1

chown -R weechat:weechat /weechat

su-exec weechat /usr/bin/weechat "$@"
