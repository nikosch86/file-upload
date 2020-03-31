#!/bin/bash -eux

DL_DIR=/var/www/dl

if [ ! -d ${DL_DIR} ]; then
  exit 0
fi

CURRENT_TS=$(date '+%s')
find "${DL_DIR}" -type f -name "expires-at-*" | while read expires_file; do
  # /var/www/dl/c1984d98fcc6/expires-at-1585729013
  TS=$(basename ${expires_file} | sed -E 's/^expires-at-(\d+)$/\1/g')
  if [ $(echo ${TS} | grep -q '^\d\+$') -gt 0 ]; then
    continue;
  fi
  if (( CURRENT_TS > TS )); then
    echo -en $(date -d @${CURRENT_TS})
    echo -en " > "
    echo -en $(date -d @${TS})
    echo " >> DELETING $(dirname ${expires_file})"
    rm -r $(dirname ${expires_file})
  fi
done
