#!/bin/bash

trap 'exit 0' SIGTERM | tee -a /var/logs/cron.log

cat > crontab.tmp << EOF
$EXECUTION_CRON_EXPRESSION /run-cron.sh $@ | tee -a /var/logs/cron.log
# An empty line is required at the end of this file for a valid cron file.
EOF

crontab "crontab.tmp" 
rm -f "crontab.tmp" 
/usr/sbin/crond -L /var/logs/cron.log
tail -n 5000 -f /var/logs/cron.log
