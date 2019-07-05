FROM linuxserver/transmission

RUN wget "https://raw.githubusercontent.com/ronggang/transmission-web-control/master/release/install-tr-control.sh" -O "/tmp/webui.sh" \
    && chmod +x /tmp/webui.sh \
    && /tmp/webui.sh auto \
    && rm -f /tmp/webui.sh
