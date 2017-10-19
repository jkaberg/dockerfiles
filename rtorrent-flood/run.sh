#!/bin/sh

mkdir -p /config/torrents
mkdir -p /config/.watch
mkdir -p /config/.session
mkdir -p /downloads

sed -i -e "s|<FLOOD_SECRET>|$FLOOD_SECRET|g" \
       -e "s|<CONTEXT_PATH>|$CONTEXT_PATH|g" /usr/flood/config.js

rm -f /config/.session/rtorrent.lock

chown -R $UID:$GID /downloads /config /home/torrent /tmp /usr/flood /flood-db /etc/s6.d

if [ ${RTORRENT_SCGI} -ne 0 ]; then
    sed -i -e 's|^scgi_local.*$|scgi_port = 0.0.0.0:'${RTORRENT_SCGI}'|' /home/torrent/.rtorrent.rc
    sed -i -e 's|socket: true,|socket: false,|' -e 's|port: 5000,|port: '${RTORRENT_SCGI}',|' /usr/flood/config.js
fi

exec su-exec $UID:$GID /bin/s6-svscan /etc/s6.d
