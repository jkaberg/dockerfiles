#!/bin/sh
mongod --dbpath /data &
mongorestore -h localhost -d leanote --dir /app/mongodb_backup/leanote_install_data/

/app/bin/run.sh
