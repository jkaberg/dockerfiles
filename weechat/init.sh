#!/bin/sh

addgroup -g $WEECHAT_GID -S weechat
adduser -u $WEECHAT_UID -D -S -h /weechat -s /sbin/nologin -G weechat weechat
chown -R weechat:weechat /weechat
chmod -R 755 /weechat


/usr/bin/weechat "$@"
