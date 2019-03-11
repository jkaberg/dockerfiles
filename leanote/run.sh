#!/usr/bin/sh

sed -i "s/app.secret=.*$/app.secret=${LEANOTE_SECRET}/" /leanote/conf/app.conf
sed -i "s/db.host=.*$/db.host=${LEANOTE_DB_HOST}/" /leanote/conf/app.conf
sed -i "s/site.url=.*$/site.url=\${LEANOTE_SITE_URL} /" /leanote/conf/app.conf

mongorestore -h "$LEANOTE_DB_HOST" -d leanote --dir /leanote/mongodb_backup/leanote_install_data > /dev/null

/leanote/bin/run.sh
