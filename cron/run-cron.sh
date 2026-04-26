#!/bin/bash -eu

DL_DIR=/var/www/dl

if [ ! -d "${DL_DIR}" ]; then
  exit 0
fi

CURRENT_TS=$(date '+%s')

find "${DL_DIR}" -type f -name "expires-at-*" -print0 | while IFS= read -r -d '' expires_file; do
  TS=$(basename -- "${expires_file}" | sed -E 's/^expires-at-([0-9]+)$/\1/')
  if ! [[ ${TS} =~ ^[0-9]+$ ]]; then
    continue
  fi
  if (( CURRENT_TS > TS )); then
    dir=$(dirname -- "${expires_file}")
    echo "$(date -d @${CURRENT_TS}) > $(date -d @${TS}) >> DELETING ${dir}"
    rm -r -- "${dir}"
  fi
done
