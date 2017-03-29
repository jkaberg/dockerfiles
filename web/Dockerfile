FROM nginx:alpine

ADD conf/* /etc/nginx/conf.d/

RUN mkdir /html \
    && mkdir /stats

VOLUME ["/html", "/munin"]
