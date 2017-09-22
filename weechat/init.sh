#!/bin/sh

if [ ! "$(id -u weechat)" -eq "$WEECHAT_GID" ]; then usermod -o -u "$WEECHAT_GID" weechat ; fi
if [ ! "$(id -g weechat)" -eq "$WEECHAT_UID" ]; then groupmod -o -g "$WEECHAT_UID" weechat ; fi

chown -R weechat:weechat /weechat
chmod -R 755 /weechat


/usr/bin/weechat "$@"
